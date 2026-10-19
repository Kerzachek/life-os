import 'package:flutter_test/flutter_test.dart';
import 'package:home_organizer/core/sync/sync_payload.dart';

import 'helpers/sync_harness.dart';

void main() {
  final h = useSyncHarness();

  group('soft-delete (deletedAt)', () {
    test('удаление с другого устройства распространяется локально', () async {
      await h().insertTask(h().dbB, 'task-1', updatedAt: at(10));
      await h().insertTask(h().dbA, 'task-1',
          updatedAt: at(20), deletedAt: at(20));

      await h().pushAtoB();

      final local = await h().task(h().dbB, 'task-1');
      expect(local, isNotNull, reason: 'запись остаётся как tombstone');
      expect(local!.deletedAt, isNotNull);
    });

    test('удалённая запись из облака вставляется как tombstone', () async {
      await h().insertTask(h().dbA, 'task-1',
          updatedAt: at(20), deletedAt: at(20));

      await h().pushAtoB();

      expect((await h().task(h().dbB, 'task-1'))!.deletedAt, isNotNull);
    });

    test('экспорт включает soft-deleted записи', () async {
      await h().insertTask(h().dbA, 'task-1',
          updatedAt: at(20), deletedAt: at(20));

      final payload = await h().engineA.exportToSyncPayload();

      final row = payload.tables['tasks']!.single;
      expect(row['id'], 'task-1');
      expect(row['deletedAt'], isNotNull);
    });

    test('удаление не воскресает от более старой живой копии', () async {
      await h().insertTask(h().dbB, 'task-1',
          updatedAt: at(30), deletedAt: at(30));
      await h().insertTask(h().dbA, 'task-1', updatedAt: at(20));

      await h().pushAtoB();

      expect((await h().task(h().dbB, 'task-1'))!.deletedAt, isNotNull);
    });

    test('удаление позже чужой правки побеждает (deletedAt > updatedAt)',
        () async {
      await h().insertTask(h().dbB, 'task-1',
          title: 'Правка', updatedAt: at(20));
      await h().insertTask(h().dbA, 'task-1',
          updatedAt: at(15), deletedAt: at(25));

      await h().pushAtoB();

      expect((await h().task(h().dbB, 'task-1'))!.deletedAt, isNotNull);
    });

    test('правка новее удаления возвращает запись к жизни', () async {
      await h().insertTask(h().dbB, 'task-1',
          updatedAt: at(10), deletedAt: at(10));
      await h().insertTask(h().dbA, 'task-1',
          title: 'Восстановлена', updatedAt: at(40));

      await h().pushAtoB();

      final local = await h().task(h().dbB, 'task-1');
      expect(local!.deletedAt, isNull);
      expect(local.title, 'Восстановлена');
    });

    test('при равных метках удаление побеждает', () async {
      await h().insertTask(h().dbB, 'task-1', updatedAt: at(10));
      await h().insertTask(h().dbA, 'task-1',
          updatedAt: at(10), deletedAt: at(10));

      await h().pushAtoB();

      expect((await h().task(h().dbB, 'task-1'))!.deletedAt, isNotNull);
    });
  });

  group('SyncPayload', () {
    test('JSON-кодирование сохраняет метаданные и версию', () async {
      final payload = await h().engineA.exportToSyncPayload();
      final decoded = SyncPayload.decode(payload.encode());

      expect(decoded.version, SyncPayload.currentVersion);
      expect(decoded.deviceId, payload.deviceId);
      expect(decoded.lastSyncTimestamp, payload.lastSyncTimestamp);
      expect(decoded.tables.keys, containsAll(h().engineA.tableNames));
    });

    test('deviceId стабилен между вызовами и различается у устройств',
        () async {
      final a = h().engineA;
      expect(await a.getDeviceId(), await a.getDeviceId());
      expect(await a.getDeviceId(), isNot(await h().engineB.getDeviceId()));
    });

    test('app_settings не попадает в снимок', () async {
      final payload = await h().engineA.exportToSyncPayload();
      expect(payload.tables.containsKey('app_settings'), isFalse);
    });

    test('повреждённый и слишком новый файл отклоняются', () {
      expect(() => SyncPayload.decode('не json'),
          throwsA(isA<SyncFormatException>()));
      expect(() => SyncPayload.decode('[]'),
          throwsA(isA<SyncFormatException>()));
      expect(
        () => SyncPayload.decode(
          '{"version": 99, "lastSyncTimestamp": "2026-01-01T00:00:00Z", '
          '"deviceId": "x", "tables": {}}',
        ),
        throwsA(isA<SyncFormatException>()),
      );
    });
  });
}
