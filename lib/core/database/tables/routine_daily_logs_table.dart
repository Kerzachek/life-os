import 'package:drift/drift.dart';
import 'syncable_table.dart';

/// Итог рутины за день. `id` детерминирован по дате (`routine-YYYY-MM-DD`),
/// чтобы записи одного дня с разных устройств сливались, а не дублировались.
@DataClassName('RoutineDailyLogEntity')
class RoutineDailyLogs extends Table with SyncableTable {
  /// Локальная дата в формате `YYYY-MM-DD`.
  TextColumn get date => text()();
  IntColumn get completedCount => integer()();
  IntColumn get totalCount => integer()();

  /// Доля выполнения 0.0–1.0.
  RealColumn get completionRate => real()();
}
