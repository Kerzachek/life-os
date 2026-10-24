import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:home_organizer/core/backup/local_backup_service.dart';
import 'package:home_organizer/core/sync/sync_payload.dart';

import 'helpers/sync_harness.dart';

Uint8List _bytes(String text) => Uint8List.fromList(utf8.encode(text));

void main() {
  final h = useSyncHarness();

  LocalBackupService serviceA() => LocalBackupService(h().engineA);
  LocalBackupService serviceB() => LocalBackupService(h().engineB);

  test('имя файла по умолчанию', () {
    expect(
      backupFileName(DateTime(2026, 3, 5, 9, 7)),
      'LifeOS_Backup_2026-03-05_0907.json',
    );
  });

  group('сериализация', () {
    test(
      'копия — читаемый JSON со всеми синхронизируемыми таблицами',
      () async {
        await h().insertTask(
          h().dbA,
          'task-1',
          title: 'Купить хлеб',
          updatedAt: at(1),
        );

        final bytes = await serviceA().createBackup();
        final text = utf8.decode(bytes);

        expect(text, contains('\n  "version": ${SyncPayload.currentVersion}'));
        final json = jsonDecode(text) as Map<String, dynamic>;
        expect(
          (json['tables'] as Map).keys,
          containsAll(h().engineA.tableNames),
        );
        final tasks = (json['tables'] as Map)['tasks'] as List;
        expect(tasks.single['title'], 'Купить хлеб');
        expect(tasks.single['updatedAt'], at(1).toIso8601String());
      },
    );

    test('создание → разбор возвращает тот же снимок', () async {
      await h().insertTask(h().dbA, 'task-1', updatedAt: at(1));
      final original = await h().engineA.exportToSyncPayload();

      final parsed = serviceA().parseBackup(
        LocalBackupService.encodeBackup(original),
      );

      expect(parsed.version, original.version);
      expect(parsed.deviceId, original.deviceId);
      expect(parsed.lastSyncTimestamp, original.lastSyncTimestamp);
      expect(jsonEncode(parsed.tables), jsonEncode(original.tables));
    });
  });

  group('восстановление', () {
    test(
      'копия устройства A полностью восстанавливается в пустую базу',
      () async {
        await h().insertTask(
          h().dbA,
          'task-1',
          title: 'Задача А',
          updatedAt: at(1),
        );
        await h().insertTask(
          h().dbA,
          'task-2',
          updatedAt: at(2),
          deletedAt: at(2),
        );

        final bytes = await serviceA().createBackup();
        final payload = serviceB().parseBackup(bytes);
        expect(
          LocalBackupService.countRecords(payload),
          LocalBackupService.countRecords(
            await h().engineA.exportToSyncPayload(),
          ),
        );

        final result = await serviceB().restore(payload);

        expect(result.inserted, greaterThanOrEqualTo(2));
        expect((await h().task(h().dbB, 'task-1'))!.title, 'Задача А');
        expect((await h().task(h().dbB, 'task-2'))!.deletedAt, isNotNull);
        final a = await h().engineA.exportToSyncPayload();
        final b = await h().engineB.exportToSyncPayload();
        expect(jsonEncode(b.tables), jsonEncode(a.tables));
      },
    );

    test('более свежая локальная правка не перезаписывается', () async {
      await h().insertTask(
        h().dbA,
        'task-1',
        title: 'Старое',
        updatedAt: at(1),
      );
      final bytes = await serviceA().createBackup();
      await h().insertTask(h().dbB, 'task-1', title: 'Новое', updatedAt: at(5));

      final result = await serviceB().restore(serviceB().parseBackup(bytes));

      expect(result.skipped, greaterThanOrEqualTo(1));
      expect((await h().task(h().dbB, 'task-1'))!.title, 'Новое');
    });

    test('повторное восстановление той же копии ничего не меняет', () async {
      await h().insertTask(h().dbA, 'task-1', updatedAt: at(1));
      final bytes = await serviceA().createBackup();
      await serviceB().restore(serviceB().parseBackup(bytes));

      final again = await serviceB().restore(serviceB().parseBackup(bytes));

      expect(again.changed, 0);
    });
  });

  group('валидация файла', () {
    Map<String, dynamic> validJson() => {
      'version': 1,
      'lastSyncTimestamp': at(0).toIso8601String(),
      'deviceId': 'device',
      'tables': <String, Object>{
        'tasks': [
          {'id': 't', 'updatedAt': at(0).toIso8601String()},
        ],
      },
    };

    test('BOM в начале файла допускается', () {
      final payload = serviceA().parseBackup(
        _bytes('\uFEFF${jsonEncode(validJson())}'),
      );
      expect(payload.tables['tasks'], hasLength(1));
    });

    void expectRejected(Uint8List bytes, Matcher message) {
      expect(
        () => serviceA().parseBackup(bytes),
        throwsA(
          isA<SyncFormatException>().having(
            (e) => e.message,
            'message',
            message,
          ),
        ),
      );
    }

    test('не JSON', () {
      expectRejected(_bytes('not json'), contains('повреждён'));
    });

    test('не UTF-8', () {
      expectRejected(Uint8List.fromList([0xFF, 0xFE, 0x00]), contains('UTF-8'));
    });

    test('чужая структура', () {
      expectRejected(_bytes('{"foo": 1}'), contains('Некорректная структура'));
    });

    test('версия новее приложения', () {
      expectRejected(
        _bytes(jsonEncode(validJson()..['version'] = 99)),
        contains('более новой версией'),
      );
    });

    test('неизвестная таблица', () {
      final json = validJson();
      (json['tables'] as Map)['passwords'] = <Object>[];
      expectRejected(_bytes(jsonEncode(json)), contains('passwords'));
    });

    test('пустой список таблиц', () {
      expectRejected(
        _bytes(jsonEncode(validJson()..['tables'] = <String, Object>{})),
        contains('нет данных'),
      );
    });

    test('запись без id', () {
      final json = validJson();
      (json['tables'] as Map)['tasks'] = [
        {'updatedAt': at(0).toIso8601String()},
      ];
      expectRejected(_bytes(jsonEncode(json)), contains('tasks'));
    });
  });
}
