import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../habits/presentation/providers/habits_provider.dart';
import '../../../routine/presentation/providers/routine_provider.dart';
import '../../../settings/domain/app_module.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../../tasks/domain/task_status.dart';
import '../../../tasks/presentation/providers/tasks_provider.dart';
import '../../domain/productivity.dart';

/// Блок «Прогресс и продуктивность». Показывает прогресс-бары только
/// включённых разделов; общий процент считается по ним же.
///
/// Если отключены Задачи, Привычки и Рутина — карточка не отображается.
class WeeklyProgressCard extends ConsumerWidget {
  const WeeklyProgressCard({super.key});

  /// Нужно ли показывать блок при данном наборе разделов.
  static bool isVisibleFor(Set<AppModule> enabled) =>
      enabled.contains(AppModule.tasks) ||
      enabled.contains(AppModule.habits) ||
      enabled.contains(AppModule.routine);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final enabled = ref.watch(enabledModulesProvider);
    final tasksOn = enabled.contains(AppModule.tasks);
    final habitsOn = enabled.contains(AppModule.habits);
    final routineOn = enabled.contains(AppModule.routine);

    if (!isVisibleFor(enabled)) return const SizedBox.shrink();

    // Данные отключённого раздела не читаются.
    int totalTasks = 0;
    int completedTasks = 0;
    if (tasksOn) {
      final tasks = ref.watch(rawTasksStreamProvider).value ?? const [];
      totalTasks = tasks.length;
      completedTasks =
          tasks.where((t) => t.status == TaskStatus.completed.value).length;
    }

    int totalHabits = 0;
    int completedHabitsToday = 0;
    if (habitsOn) {
      final habits = ref.watch(habitsWithStatusProvider).value ?? const [];
      totalHabits = habits.length;
      completedHabitsToday = habits.where((h) => h.isCompletedToday).length;
    }

    RoutineTodaySummary routine =
        const RoutineTodaySummary(completed: 0, total: 0);
    if (routineOn) {
      routine = ref.watch(routineTodaySummaryProvider).value ?? routine;
    }

    final taskRatio = totalTasks > 0 ? completedTasks / totalTasks : null;
    final habitRatio =
        totalHabits > 0 ? completedHabitsToday / totalHabits : null;
    final overall = overallProductivity([
      if (tasksOn) taskRatio,
      if (habitsOn) habitRatio,
      if (routineOn) routine.ratio,
    ]);

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
              Expanded(
                child: Text(
                  'Прогресс и Продуктивность',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              if (overall != null)
                Container(
                  key: const ValueKey('overall_productivity'),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Итого ${(overall * 100).round()}%',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
            ],
          ),
          if (tasksOn) ...[
            const SizedBox(height: 16),
            _ProgressRow(
              label: 'Выполнение задач',
              done: completedTasks,
              total: totalTasks,
              color: colorScheme.primary,
            ),
          ],
          if (habitsOn) ...[
            const SizedBox(height: 16),
            _ProgressRow(
              label: 'Привычки за сегодня',
              done: completedHabitsToday,
              total: totalHabits,
              color: Colors.orange,
            ),
          ],
          if (routineOn) ...[
            const SizedBox(height: 16),
            _ProgressRow(
              label: 'Рутина',
              done: routine.completed,
              total: routine.total,
              color: const Color(0xFFFDCB6E),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProgressRow extends StatelessWidget {
  final String label;
  final int done;
  final int total;
  final Color color;

  const _ProgressRow({
    required this.label,
    required this.done,
    required this.total,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final ratio = total > 0 ? done / total : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$done / $total (${(ratio * 100).toInt()}%)',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 8,
            backgroundColor: colorScheme.surfaceContainerHighest,
            color: color,
          ),
        ),
      ],
    );
  }
}
