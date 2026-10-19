import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../habits/presentation/providers/habits_provider.dart';
import '../../../settings/domain/app_module.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../../tasks/data/repositories/tasks_repository.dart';
import '../../../tasks/domain/task_status.dart';
import '../../domain/life_score.dart';

/// Поток задач за сегодня (выборка на стороне Drift).
final todayTasksStreamProvider = StreamProvider<List<TaskEntity>>((ref) {
  return ref.watch(tasksRepositoryProvider).watchTodayTasks();
});

/// Life Score за текущий день.
///
/// Учитывает только включённые модули: данные отключённого модуля
/// не читаются, а веса оставшихся компонентов нормируются.
/// Пока данные загружаются, возвращает [AsyncLoading].
final lifeScoreProvider = Provider<AsyncValue<LifeScore>>((ref) {
  final enabled = ref.watch(enabledModulesProvider);
  final tasksOn = enabled.contains(AppModule.tasks);
  final habitsOn = enabled.contains(AppModule.habits);

  double? taskRatio;
  double? habitRatio;
  double? streakRatio;

  if (tasksOn) {
    final tasksAsync = ref.watch(todayTasksStreamProvider);
    if (tasksAsync.hasError) {
      return AsyncError(tasksAsync.error!, tasksAsync.stackTrace!);
    }
    final tasks = tasksAsync.value;
    if (tasks == null) return const AsyncLoading();

    if (tasks.isNotEmpty) {
      final done =
          tasks.where((t) => t.status == TaskStatus.completed.value).length;
      taskRatio = done / tasks.length;
    }
  }

  if (habitsOn) {
    final habitsAsync = ref.watch(habitsWithStatusProvider);
    if (habitsAsync.hasError) {
      return AsyncError(habitsAsync.error!, habitsAsync.stackTrace!);
    }
    final habits = habitsAsync.value;
    if (habits == null) return const AsyncLoading();

    if (habits.isNotEmpty) {
      final done = habits.where((h) => h.isCompletedToday).length;
      habitRatio = done / habits.length;

      // Стрик: средняя длина серий, ограниченная порогом streakCapDays.
      final streakSum = habits.fold<double>(
        0,
        (sum, h) =>
            sum +
            (h.streakCount.clamp(0, LifeScore.streakCapDays) /
                LifeScore.streakCapDays),
      );
      streakRatio = streakSum / habits.length;
    }
  }

  return AsyncData(
    LifeScore.calculate(
      taskRatio: taskRatio,
      habitRatio: habitRatio,
      streakRatio: streakRatio,
    ),
  );
});
