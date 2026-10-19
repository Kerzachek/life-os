import 'package:drift/drift.dart';
import 'challenges_table.dart';
import 'habits_table.dart';
import 'syncable_table.dart';

@DataClassName('ChallengeHabitEntity')
class ChallengeHabits extends Table with SyncableTable {
  TextColumn get challengeId => text().references(Challenges, #id)();
  TextColumn get habitId => text().references(Habits, #id)();
}
