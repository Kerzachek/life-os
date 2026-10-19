import '../../../../core/database/app_database.dart';

class HabitWithStatus {
  final HabitEntity habit;
  final bool isCompletedToday;
  final int todayLoggedValue;
  final int streakCount;
  final List<HabitLogEntity> recentLogs;

  const HabitWithStatus({
    required this.habit,
    required this.isCompletedToday,
    required this.todayLoggedValue,
    required this.streakCount,
    required this.recentLogs,
  });
}
