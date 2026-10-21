import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../tasks/domain/task_status.dart';
import '../providers/dashboard_tasks_provider.dart';
import 'dashboard_task_tile.dart';

class TodayTasksOverviewCard extends ConsumerWidget {
  const TodayTasksOverviewCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tasksAsync = ref.watch(dashboardTasksProvider);

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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(Icons.task_alt, size: 18, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Задачи на сегодня',
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              tasksAsync.maybeWhen(
                data: (tasks) {
                  final active = tasks
                      .where((t) => t.status != TaskStatus.completed.value)
                      .length;
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$active активных',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                    ),
                  );
                },
                orElse: () => const SizedBox.shrink(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          tasksAsync.when(
            data: (tasks) {
              if (tasks.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Text(
                      'На сегодня задач нет',
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                  ),
                );
              }

              final allDone =
                  tasks.every((t) => t.status == TaskStatus.completed.value);
              final visible = tasks.take(dashboardTasksLimit).toList();

              return Column(
                children: [
                  if (allDone)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Все задачи выполнены! 🎉',
                        style: TextStyle(color: colorScheme.onSurfaceVariant),
                      ),
                    ),
                  for (final task in visible)
                    DashboardTaskTile(key: ValueKey(task.id), task: task),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Text('Ошибка: $err'),
          ),
        ],
      ),
    );
  }
}
