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

final activeChallengesStreamProvider = StreamProvider<List<ChallengeEntity>>((
  ref,
) {
  final repo = ref.watch(habitsRepositoryProvider);
  return repo.watchActiveChallenges();
});

final habitsWithStatusProvider = Provider<AsyncValue<List<HabitWithStatus>>>((
  ref,
) {
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

  final todayDate = habitDay(DateTime.now());

  final result = habits.map((habit) {
    final habitLogs = logs.where((l) => l.habitId == habit.id).toList();

    // Сумма отмеченных значений по календарным дням.
    final dailyTotals = <DateTime, int>{};
    for (final log in habitLogs) {
      final day = habitDay(log.completedAt);
      dailyTotals[day] = (dailyTotals[day] ?? 0) + log.value;
    }

    final todayLoggedVal = dailyTotals[todayDate] ?? 0;

    return HabitWithStatus(
      habit: habit,
      isCompletedToday: todayLoggedVal >= habit.targetValue,
      todayLoggedValue: todayLoggedVal,
      streakCount: calculateHabitStreak(
        schedule:
            HabitSchedule.parse(habit.frequencyType, habit.frequencyValue),
        dailyTotals: dailyTotals,
        targetValue: habit.targetValue,
        today: todayDate,
      ),
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
    String? frequencyValue,
    int targetValue = 1,
    String? unit,
    String? color,
    String? icon,
  }) async {
    await _repository.createHabit(
      title: title,
      description: description,
      frequencyType: frequencyType,
      frequencyValue: frequencyValue,
      targetValue: targetValue,
      unit: unit,
      color: color,
      icon: icon,
    );
  }

  Future<void> updateHabit({
    required String id,
    required String title,
    String? description,
    HabitFrequencyType frequencyType = HabitFrequencyType.daily,
    String? frequencyValue,
    int targetValue = 1,
    String? unit,
    String? color,
    String? icon,
  }) async {
    await _repository.updateHabit(
      id: id,
      title: title,
      description: description,
      frequencyType: frequencyType,
      frequencyValue: frequencyValue,
      targetValue: targetValue,
      unit: unit,
      color: color,
      icon: icon,
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
