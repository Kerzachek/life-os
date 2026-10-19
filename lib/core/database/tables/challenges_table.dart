import 'package:drift/drift.dart';
import 'syncable_table.dart';

@DataClassName('ChallengeEntity')
class Challenges extends Table with SyncableTable {
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get endDate => dateTime()();
  IntColumn get status => integer().withDefault(const Constant(1))(); // 0=upcoming, 1=active, 2=completed, 3=failed
}
