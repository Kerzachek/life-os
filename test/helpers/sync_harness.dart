import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_organizer/core/database/app_database.dart';
import 'package:home_organizer/core/sync/sync_engine.dart';
import 'package:home_organizer/core/sync/sync_payload.dart';

/// Базовое время тестов; `at(n)` — момент через n минут после него.
final DateTime t0 = DateTime.utc(2026, 1, 1, 12);
DateTime at(int minutes) => t0.add(Duration(minutes: minutes));

/// Два «устройства» (in-memory БД со своими движками синхронизации).
class SyncHarness {
  final AppDatabase dbA = AppDatabase.forTesting(NativeDatabase.memory());
  final AppDatabase dbB = AppDatabase.forTesting(NativeDatabase.memory());
  late final SyncEngine engineA = SyncEngine(dbA);
  late final SyncEngine engineB = SyncEngine(dbB);

  Future<void> close() async {
    await dbA.close();
    await dbB.close();
  }

  Future<void> insertTask(
    AppDatabase db,
    String id, {
    String title = 'Задача',
    required DateTime updatedAt,
    String? description,
    DateTime? deletedAt,
  }) {
    return db.into(db.tasks).insert(
          TasksCompanion.insert(
            id: id,
            createdAt: at(0),
            updatedAt: updatedAt,
            title: title,
            description: Value(description),
            deletedAt: Value(deletedAt),
          ),
        );
  }

  Future<TaskEntity?> task(AppDatabase db, String id) {
    return (db.select(db.tasks)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  /// Передача «облачного» файла: JSON-кодирование туда и обратно.
  Future<SyncPayload> cloudOf(SyncEngine engine) async {
    final payload = await engine.exportToSyncPayload();
    return SyncPayload.decode(payload.encode());
  }

  /// Сливает снимок устройства A в устройство B.
  Future<MergeResult> pushAtoB() async =>
      engineB.mergeFromSyncPayload(await cloudOf(engineA));

  /// Сливает снимок устройства B в устройство A.
  Future<MergeResult> pushBtoA() async =>
      engineA.mergeFromSyncPayload(await cloudOf(engineB));
}

/// Регистрирует setUp/tearDown и возвращает «геттер» стенда.
SyncHarness Function() useSyncHarness() {
  late SyncHarness harness;
  setUp(() {
    // Два «устройства» = две БД в одном процессе: предупреждение ожидаемо.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    harness = SyncHarness();
  });
  tearDown(() => harness.close());
  return () => harness;
}
