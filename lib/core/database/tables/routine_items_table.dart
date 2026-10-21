import 'package:drift/drift.dart';
import 'syncable_table.dart';

/// Пункты ежедневной рутины (чек-лист дня с автосбросом в 00:00).
///
/// [completedAt] — момент отметки: по нему сброс отличает вчерашние отметки
/// от сегодняшних (в том числе пришедших с другого устройства).
@DataClassName('RoutineItemEntity')
class RoutineItems extends Table with SyncableTable {
  TextColumn get title => text()();

  /// 0 — общее, 1 — утро, 2 — день, 3 — вечер.
  IntColumn get category => integer().withDefault(const Constant(0))();
  BoolColumn get isCompleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get completedAt => dateTime().nullable()();

  /// Порядок сортировки в списке.
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
}
