import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:home_organizer/core/backup/auto_backup_service.dart';
import 'package:home_organizer/core/backup/local_backup_service.dart';
import 'package:home_organizer/core/backup/local_backup_store.dart';
import 'package:path/path.dart' as p;

import 'helpers/sync_harness.dart';

Uint8List _bytes(String text) => Uint8List.fromList(utf8.encode(text));

void main() {
  final h = useSyncHarness();
  late Directory root;
  late Directory backups;
  late LocalBackupStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('lifeos_backup_test');
    backups = Directory(p.join(root.path, 'backups'));
    store = LocalBackupStore(() async => backups);
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  group('LocalBackupStore', () {
    test('имя ежедневной копии', () {
      expect(
        LocalBackupStore.dailyFileName(DateTime(2026, 3, 5, 23, 59)),
        'LifeOS_Backup_2026-03-05.json',
      );
    });

    test('без папки список пуст', () async {
      expect(await store.list(), isEmpty);
      expect(await store.hasCopyFor(DateTime(2026, 10, 25)), isFalse);
    });

    test('сохранение создаёт папку, повтор за день перезаписывает', () async {
      await store.save(_bytes('first'), DateTime(2026, 10, 25, 9));
      await store.save(_bytes('second'), DateTime(2026, 10, 25, 18));

      final copies = await store.list();
      expect(copies, hasLength(1));
      expect(copies.single.fileName, 'LifeOS_Backup_2026-10-25.json');
      expect(copies.single.date, DateTime(2026, 10, 25));
      expect(utf8.decode(await store.read(copies.single)), 'second');
      expect(await store.hasCopyFor(DateTime(2026, 10, 25, 1)), isTrue);
      // Временный файл записи не остаётся.
      expect(backups.listSync().map((e) => p.basename(e.path)), [
        'LifeOS_Backup_2026-10-25.json',
      ]);
    });

    test('ротация оставляет последние копии, чужие файлы не трогает', () async {
      await backups.create(recursive: true);
      final foreign = File(p.join(backups.path, 'notes.txt'))
        ..writeAsStringSync('keep');
      for (var day = 1; day <= LocalBackupStore.maxCopies + 3; day++) {
        await store.save(_bytes('day $day'), DateTime(2026, 10, day));
      }

      final copies = await store.list();
      expect(copies, hasLength(LocalBackupStore.maxCopies));
      expect(copies.first.date, DateTime(2026, 10, 13));
      expect(copies.last.date, DateTime(2026, 10, 4));
      expect(foreign.existsSync(), isTrue);
    });
  });

  group('AutoBackupService', () {
    var now = DateTime(2026, 10, 25, 10);

    AutoBackupService service() => AutoBackupService(
      LocalBackupService(h().engineA),
      store,
      now: () => now,
    );

    setUp(() => now = DateTime(2026, 10, 25, 10));

    test('пустая база — копия не создаётся', () async {
      await service().ensureDaily();
      expect(await store.list(), isEmpty);
    });

    test('создаёт копию за день один раз, backupNow обновляет её', () async {
      await h().insertTask(
        h().dbA,
        'task-1',
        title: 'Первая',
        updatedAt: at(1),
      );
      final auto = service();

      await auto.ensureDaily();
      final first = await store.list();
      expect(first, hasLength(1));
      final parsed = LocalBackupService(h().engineA)
          .parseBackup(await store.read(first.single));
      expect(parsed.tables['tasks']!.single['title'], 'Первая');

      await h().insertTask(
        h().dbA,
        'task-2',
        title: 'Вторая',
        updatedAt: at(2),
      );
      await auto.ensureDaily();
      var tasks = LocalBackupService(h().engineA)
          .parseBackup(await store.read((await store.list()).single))
          .tables['tasks']!;
      expect(tasks, hasLength(1), reason: 'копия дня уже есть');

      await auto.backupNow();
      tasks = LocalBackupService(h().engineA)
          .parseBackup(await store.read((await store.list()).single))
          .tables['tasks']!;
      expect(tasks, hasLength(2));
    });

    test('новый день — новая копия', () async {
      await h().insertTask(h().dbA, 'task-1', updatedAt: at(1));
      final auto = service();
      await auto.ensureDaily();
      now = DateTime(2026, 10, 26, 0, 5);
      await auto.ensureDaily();

      expect((await store.list()).map((e) => e.fileName), [
        'LifeOS_Backup_2026-10-26.json',
        'LifeOS_Backup_2026-10-25.json',
      ]);
    });

    test('ошибка записи не пробрасывается', () async {
      await h().insertTask(h().dbA, 'task-1', updatedAt: at(1));
      // Вместо папки — файл: создать каталог не получится.
      final blocker = File(p.join(root.path, 'blocked'))..writeAsStringSync('');
      final broken = AutoBackupService(
        LocalBackupService(h().engineA),
        LocalBackupStore(() async => Directory(blocker.path)),
        now: () => now,
      );
      await expectLater(broken.ensureDaily(), completes);
    });
  });
}
