import 'package:drift/drift.dart';
import 'syncable_table.dart';

@DataClassName('HabitEntity')
class Habits extends Table with SyncableTable {
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  IntColumn get frequencyType => integer().withDefault(const Constant(0))(); // 0=daily, 1=weeklyDays, 2=customInterval
  TextColumn get frequencyValue => text().nullable()(); // JSON string with extra configs
  IntColumn get targetValue => integer().withDefault(const Constant(1))();
  TextColumn get unit => text().nullable()();
  TextColumn get color => text().nullable()();
  TextColumn get icon => text().nullable()();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
}
