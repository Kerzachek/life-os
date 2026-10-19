import 'package:drift/drift.dart';
import 'categories_table.dart';
import 'syncable_table.dart';

@DataClassName('TaskEntity')
class Tasks extends Table with SyncableTable {
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  DateTimeColumn get dueDate => dateTime().nullable()();
  IntColumn get priority => integer().withDefault(const Constant(1))(); // 0=low, 1=medium, 2=high, 3=urgent
  IntColumn get status => integer().withDefault(const Constant(0))(); // 0=todo, 1=inProgress, 2=completed, 3=cancelled
  TextColumn get recurrenceRule => text().nullable()();
  TextColumn get categoryId => text().nullable().references(Categories, #id)();
  TextColumn get parentId => text().nullable().references(Tasks, #id)();
}
