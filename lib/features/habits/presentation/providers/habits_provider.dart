import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../data/repositories/habits_repository.dart';
import '../../domain/habit_frequency.dart';
import '../../domain/habit_with_status.dart';

final rawHabitsStreamProvider = StreamProvider<List<HabitEntity>>((ref) {
  final repo = ref.watch(habitsRepositoryProvider);
  return repo.watchHabits();
});

final rawHabitLogsStreamProvider = StreamProvider<List<HabitLogEntity>>((ref) {
  final repo = ref.watch(habitsRepositoryProvider);
  return repo.watchAllHabitLogs();
});

final activeChallengesStreamProvider = StreamProvider<List<ChallengeEntity>>((ref) {
  final repo = ref.watch(habitsRepositoryProvider);
  return repo.watchActiveChallenges();
});

final habitsWithStatusProvider = Provider<AsyncValue<List<HabitWithStatus>>>((ref) {
  final habitsAsync = ref.watch(rawHabitsStreamProvider);
  final logsAsync = ref.watch(rawHabitLogsStreamProvider);

  if (habitsAsync is AsyncError) {
    return AsyncError(habitsAsync.error!, habitsAsync.stackTrace!);
  }
  if (logsAsync is AsyncError) {
    return AsyncError(logsAsync.error!, logsAsync.stackTrace!);
  }

  if (habitsAsync is AsyncLoading || logsAsync is AsyncLoading) {
    return const AsyncLoading();
  }

  final habits = habitsAsync.value ?? [];
  final logs = logsAsync.value ?? [];

  final now = DateTime.now();
  final todayDate = DateTime(now.year, now.month, now.day);

  final result = habits.map((habit) {
    final habitLogs = logs.where((l) => l.habitId == habit.id).toList();

    final loggedDates = <DateTime>{};
    int todayLoggedVal = 0;

    for (final log in habitLogs) {
      final local = log.completedAt.toLocal();
      final dateOnly = DateTime(local.year, local.month, local.day);
      loggedDates.add(dateOnly);

      if (dateOnly == todayDate) {
        todayLoggedVal += log.value;
      }
    }

    final isCompletedToday = todayLoggedVal >= habit.targetValue;

    // Расчет серии выполнений (стрика)
    int streak = 0;
    DateTime checkDate = isCompletedToday
        ? todayDate
        : todayDate.subtract(const Duration(days: 1));

    while (loggedDates.contains(checkDate)) {
      streak++;
      checkDate = checkDate.subtract(const Duration(days: 1));
    }

    return HabitWithStatus(
      habit: habit,
      isCompletedToday: isCompletedToday,
      todayLoggedValue: todayLoggedVal,
      streakCount: streak,
      recentLogs: habitLogs,
    );
  }).toList();

  return AsyncData(result);
});

final habitsControllerProvider = Provider<HabitsController>((ref) {
  return HabitsController(ref.watch(habitsRepositoryProvider));
});

class HabitsController {
  final HabitsRepository _repository;

  HabitsController(this._repository);

  Future<void> createHabit({
    required String title,
    String? description,
    HabitFrequencyType frequencyType = HabitFrequencyType.daily,
    int targetValue = 1,
    String? unit,
    String? color,
  }) async {
    await _repository.createHabit(
      title: title,
      description: description,
      frequencyType: frequencyType,
      targetValue: targetValue,
      unit: unit,
      color: color,
    );
  }

  Future<void> toggleHabitToday(HabitEntity habit) async {
    await _repository.toggleHabitCheckIn(
      habitId: habit.id,
      date: DateTime.now(),
      targetValue: habit.targetValue,
    );
  }

  Future<void> deleteHabit(String id) async {
    await _repository.deleteHabit(id);
  }

  Future<void> createChallenge({
    required String title,
    String? description,
    required DateTime startDate,
    required DateTime endDate,
    List<String>? habitIds,
  }) async {
    await _repository.createChallenge(
      title: title,
      description: description,
      startDate: startDate,
      endDate: endDate,
      habitIds: habitIds,
    );
  }
}
