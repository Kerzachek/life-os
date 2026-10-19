import 'package:drift/drift.dart';
import 'syncable_table.dart';

@DataClassName('Category')
class Categories extends Table with SyncableTable {
  TextColumn get name => text()();
  TextColumn get color => text().nullable()();
  TextColumn get icon => text().nullable()();
}
