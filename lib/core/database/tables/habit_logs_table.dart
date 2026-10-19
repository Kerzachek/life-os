import 'package:drift/drift.dart';
import 'habits_table.dart';
import 'syncable_table.dart';

@DataClassName('HabitLogEntity')
class HabitLogs extends Table with SyncableTable {
  TextColumn get habitId => text().references(Habits, #id)();
  DateTimeColumn get completedAt => dateTime()();
  IntColumn get value => integer().withDefault(const Constant(1))();
  TextColumn get notes => text().nullable()();
}
