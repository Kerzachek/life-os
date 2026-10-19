import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../tasks/domain/task_category.dart';
import '../../../tasks/domain/task_priority.dart';
import '../../../tasks/domain/task_status.dart';
import '../../../tasks/presentation/providers/tasks_provider.dart';
import '../../../tasks/presentation/widgets/add_task_dialog.dart';
import '../../../tasks/presentation/widgets/category_badge.dart';
import '../../../tasks/presentation/widgets/priority_badge.dart';

/// Компактная строка задачи для дашборда: чекбокс + название + бейдж приоритета.
///
/// Клик по чекбоксу меняет статус в Drift; Life Score пересчитывается
/// реактивно через [todayTasksStreamProvider]. Тап по названию или по
/// кнопке-карандашу открывает форму редактирования.
class DashboardTaskTile extends ConsumerWidget {
  final TaskEntity task;

  const DashboardTaskTile({super.key, required this.task});

  void _openEdit(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AddTaskDialog(taskToEdit: task),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final isCompleted = task.status == TaskStatus.completed.value;
    final priority = TaskPriority.fromValue(task.priority);
    final category =
        task.categoryId == null ? null : TaskCategory.fromId(task.categoryId);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest
            .withValues(alpha: isCompleted ? 0.4 : 0.8),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.6)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Row(
          children: [
            // Цветная полоска приоритета слева.
            Container(
              width: 3,
              height: 44,
              color: isCompleted
                  ? priority.color.withValues(alpha: 0.25)
                  : priority.color,
            ),
            Checkbox(
              key: ValueKey('dashboard-task-checkbox-${task.id}'),
              value: isCompleted,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
              onChanged: (_) =>
                  ref.read(tasksControllerProvider).toggleTaskStatus(task),
            ),
            // Тап по области текста открывает редактирование.
            Expanded(
              child: InkWell(
                key: ValueKey('dashboard-task-edit-area-${task.id}'),
                onTap: () => _openEdit(context),
                child: Container(
                  height: 44,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    task.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      decoration:
                          isCompleted ? TextDecoration.lineThrough : null,
                      color: isCompleted
                          ? colorScheme.onSurfaceVariant
                          : colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Opacity(
              opacity: isCompleted ? 0.5 : 1,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (category != null) ...[
                    CategoryBadge(
                      key: ValueKey('dashboard-task-category-${task.id}'),
                      category: category,
                      compact: true,
                    ),
                    const SizedBox(width: 6),
                  ],
                  PriorityBadge(priority: priority),
                ],
              ),
            ),
            IconButton(
              key: ValueKey('dashboard-task-edit-${task.id}'),
              tooltip: 'Редактировать',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.edit_outlined, size: 18),
              color: colorScheme.onSurfaceVariant,
              onPressed: () => _openEdit(context),
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}
