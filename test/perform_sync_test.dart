import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:home_organizer/core/database/app_database.dart';
import 'package:home_organizer/core/sync/sync_payload.dart';
import 'package:home_organizer/core/sync/sync_remote_store.dart';

import 'helpers/fake_sync_cloud.dart';
import 'helpers/sync_harness.dart';

void main() {
  final h = useSyncHarness();

  test('первая синхронизация создаёт файл в облаке', () async {
    final cloud = FakeRemoteStore();
    await h().insertTask(h().dbA, 'task-1', title: 'Первая', updatedAt: at(5));

    final outcome = await performSync(h().engineA, cloud);

    expect(outcome.uploaded, isTrue);
    expect(cloud.uploads, 1);
    final stored = SyncPayload.decode(cloud.content!);
    expect(stored.tables['tasks']!.single['title'], 'Первая');
  });

  test('данные доезжают с устройства A на устройство B через облако',
      () async {
    final cloud = FakeRemoteStore();
    await h().insertTask(h().dbA, 'task-1', title: 'С A', updatedAt: at(5));
    await performSync(h().engineA, cloud);

    await h().insertTask(h().dbB, 'task-2', title: 'С B', updatedAt: at(6));
    await performSync(h().engineB, cloud);
    await performSync(h().engineA, cloud);

    for (final db in [h().dbA, h().dbB]) {
      expect(await h().task(db, 'task-1'), isNotNull);
      expect(await h().task(db, 'task-2'), isNotNull);
    }
  });

  test('soft-delete на A доезжает до B и не воскресает', () async {
    final cloud = FakeRemoteStore();
    await h().insertTask(h().dbA, 'task-1', updatedAt: at(5));
    await performSync(h().engineA, cloud);
    await performSync(h().engineB, cloud);
    expect((await h().task(h().dbB, 'task-1'))!.deletedAt, isNull);

    await (h().dbA.update(h().dbA.tasks)..where((t) => t.id.equals('task-1')))
        .write(TasksCompanion(deletedAt: Value(at(30)), updatedAt: Value(at(30))));
    await performSync(h().engineA, cloud);
    await performSync(h().engineB, cloud);
    await performSync(h().engineA, cloud);

    expect((await h().task(h().dbB, 'task-1'))!.deletedAt, isNotNull);
    expect((await h().task(h().dbA, 'task-1'))!.deletedAt, isNotNull);
  });

  test('повторная синхронизация без изменений не перезагружает файл',
      () async {
    final cloud = FakeRemoteStore();
    await h().insertTask(h().dbA, 'task-1', updatedAt: at(5));

    await performSync(h().engineA, cloud);
    final second = await performSync(h().engineA, cloud);

    expect(second.uploaded, isFalse);
    expect(cloud.uploads, 1);
  });

  test('повреждённый облачный файл не затирается и сообщает об ошибке',
      () async {
    final cloud = FakeRemoteStore()..content = 'это не json';
    await h().insertTask(h().dbA, 'task-1', updatedAt: at(5));

    await expectLater(
      performSync(h().engineA, cloud),
      throwsA(isA<SyncFormatException>()),
    );
    expect(cloud.content, 'это не json');
    expect(cloud.uploads, 0);
  });
}
