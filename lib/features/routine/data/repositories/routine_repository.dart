import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_provider.dart';
import '../../domain/routine_category.dart';
import '../../domain/routine_day.dart';

final routineRepositoryProvider = Provider<RoutineRepository>((ref) {
  return RoutineRepository(ref.watch(appDatabaseProvider));
});

class RoutineRepository {
  /// Дата последнего сброса (`YYYY-MM-DD`) в `app_settings`. Хранится
  /// на устройстве: каждое устройство сбрасывает свой чек-лист само.
  static const String lastResetDateKey = 'routine_last_reset_date';

  final AppDatabase _db;
  final _uuid = const Uuid();

  RoutineRepository(this._db);

  /// Поток активных пунктов рутины в порядке сортировки.
  Stream<List<RoutineItemEntity>> watchItems() {
    return (_db.select(_db.routineItems)
          ..where((r) => r.deletedAt.isNull())
          ..orderBy([
            (r) => OrderingTerm(expression: r.sortOrder),
            (r) => OrderingTerm(expression: r.createdAt),
          ]))
        .watch();
  }

  /// Поток истории выполнения (по возрастанию даты).
  Stream<List<RoutineDailyLogEntity>> watchLogs() {
    return (_db.select(_db.routineDailyLogs)
          ..where((l) => l.deletedAt.isNull())
          ..orderBy([(l) => OrderingTerm(expression: l.date)]))
        .watch();
  }

  Future<void> createItem({
    required String title,
    RoutineCategory category = RoutineCategory.general,
  }) async {
    final now = DateTime.now().toUtc();
    final maxOrder = _db.routineItems.sortOrder.max();
    final last = await (_db.selectOnly(_db.routineItems)
          ..addColumns([maxOrder])
          ..where(_db.routineItems.deletedAt.isNull()))
        .getSingle();
    await _db.into(_db.routineItems).insert(
          RoutineItemsCompanion.insert(
            id: _uuid.v4(),
            createdAt: now,
            updatedAt: now,
            title: title,
            category: Value(category.value),
            sortOrder: Value((last.read(maxOrder) ?? -1) + 1),
          ),
        );
  }

  Future<void> updateItem({
    required String id,
    required String title,
    required RoutineCategory category,
  }) async {
    await (_db.update(_db.routineItems)..where((r) => r.id.equals(id))).write(
      RoutineItemsCompanion(
        title: Value(title),
        category: Value(category.value),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  /// Отмечает пункт выполненным / снимает отметку.
  Future<void> setCompleted(String id, bool completed) async {
    final now = DateTime.now().toUtc();
    await (_db.update(_db.routineItems)..where((r) => r.id.equals(id))).write(
      RoutineItemsCompanion(
        isCompleted: Value(completed),
        completedAt: Value(completed ? now : null),
        updatedAt: Value(now),
      ),
    );
  }

  /// Мягкое удаление пункта.
  Future<void> deleteItem(String id) async {
    final now = DateTime.now().toUtc();
    await (_db.update(_db.routineItems)..where((r) => r.id.equals(id))).write(
      RoutineItemsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
  }

  /// Сохраняет новый порядок пунктов (список id сверху вниз).
  Future<void> reorder(List<String> orderedIds) async {
    final now = DateTime.now().toUtc();
    await _db.transaction(() async {
      for (var i = 0; i < orderedIds.length; i++) {
        await (_db.update(_db.routineItems)
              ..where((r) => r.id.equals(orderedIds[i])))
            .write(
          RoutineItemsCompanion(sortOrder: Value(i), updatedAt: Value(now)),
        );
      }
    });
  }

  /// Ежедневный сброс чек-листа. Возвращает `true`, если сброс выполнен.
  ///
  /// Если сегодняшняя дата отличается от `lastResetDate`:
  /// 1. итог дня `lastResetDate` пишется в `routine_daily_logs`
  ///    (только при [writeLog] и если был хотя бы один пункт);
  /// 2. снимаются отметки, поставленные до начала текущих суток;
  /// 3. `lastResetDate` становится сегодняшней датой.
  ///
  /// При первом запуске (`lastResetDate` нет) итог не пишется.
  Future<bool> performDailyReset({DateTime? now, bool writeLog = true}) {
    final moment = now ?? DateTime.now();
    final today = routineDayKey(moment);
    final dayStartUtc = startOfLocalDay(moment).toUtc();

    return _db.transaction(() async {
      final lastRow = await (_db.select(_db.appSettings)
            ..where((s) => s.settingKey.equals(lastResetDateKey)))
          .getSingleOrNull();
      final lastResetDate = lastRow?.settingValue;
      if (lastResetDate == today) return false;

      final items = await (_db.select(_db.routineItems)
            ..where((r) => r.deletedAt.isNull()))
          .get();
      bool completedBeforeToday(RoutineItemEntity item) {
        final at = item.completedAt;
        return item.isCompleted && (at == null || at.isBefore(dayStartUtc));
      }

      if (lastResetDate != null && writeLog) {
        // Пункты, созданные уже сегодня, во вчерашний итог не входят.
        final dayItems =
            items.where((i) => i.createdAt.isBefore(dayStartUtc)).toList();
        if (dayItems.isNotEmpty) {
          await _upsertLog(
            date: lastResetDate,
            completed: dayItems.where(completedBeforeToday).length,
            total: dayItems.length,
          );
        }
      }

      final stale = [
        for (final item in items)
          if (completedBeforeToday(item)) item.id,
      ];
      if (stale.isNotEmpty) {
        await (_db.update(_db.routineItems)..where((r) => r.id.isIn(stale)))
            .write(
          RoutineItemsCompanion(
            isCompleted: const Value(false),
            completedAt: const Value(null),
            updatedAt: Value(moment.toUtc()),
          ),
        );
      }

      await _db.into(_db.appSettings).insertOnConflictUpdate(
            AppSettingsCompanion.insert(
              settingKey: lastResetDateKey,
              settingValue: today,
            ),
          );
      return true;
    });
  }

  /// Пишет итог дня. Уже имеющийся (например, с другого устройства) итог
  /// с большим числом выполненных пунктов не перезаписывается.
  Future<void> _upsertLog({
    required String date,
    required int completed,
    required int total,
  }) async {
    final id = 'routine-$date';
    final existing = await (_db.select(_db.routineDailyLogs)
          ..where((l) => l.id.equals(id)))
        .getSingleOrNull();
    if (existing != null &&
        existing.deletedAt == null &&
        existing.completedCount > completed) {
      return;
    }
    final now = DateTime.now().toUtc();
    await _db.into(_db.routineDailyLogs).insertOnConflictUpdate(
          RoutineDailyLogsCompanion.insert(
            id: id,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now,
            deletedAt: const Value(null),
            date: date,
            completedCount: completed,
            totalCount: total,
            completionRate: total > 0 ? completed / total : 0,
          ),
        );
  }
}
