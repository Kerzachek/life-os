import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../habits/presentation/providers/habits_provider.dart';
import '../../../tasks/presentation/providers/tasks_provider.dart';

class WeeklyProgressCard extends ConsumerWidget {
  const WeeklyProgressCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final tasksAsync = ref.watch(rawTasksStreamProvider);
    final habitsAsync = ref.watch(habitsWithStatusProvider);

    int totalTasks = 0;
    int completedTasks = 0;
    double taskRatio = 0.0;

    tasksAsync.whenData((tasks) {
      totalTasks = tasks.length;
      completedTasks = tasks.where((t) => t.status == 2).length;
      if (totalTasks > 0) {
        taskRatio = completedTasks / totalTasks;
      }
    });

    int totalHabits = 0;
    int completedHabitsToday = 0;
    double habitRatio = 0.0;

    habitsAsync.whenData((habits) {
      totalHabits = habits.length;
      completedHabitsToday = habits.where((h) => h.isCompletedToday).length;
      if (totalHabits > 0) {
        habitRatio = completedHabitsToday / totalHabits;
      }
    });

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.insights_rounded, size: 18, color: colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'Прогресс и Продуктивность',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Выполнение задач',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    '$completedTasks / $totalTasks (${(taskRatio * 100).toInt()}%)',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: taskRatio,
                  minHeight: 8,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                  color: colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Привычки за сегодня',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    '$completedHabitsToday / $totalHabits (${(habitRatio * 100).toInt()}%)',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: habitRatio,
                  minHeight: 8,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                  color: Colors.orange,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
