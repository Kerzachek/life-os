import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/widgets/responsive.dart';
import '../../domain/task_category.dart';
import '../../domain/task_priority.dart';
import '../../domain/task_reminder.dart';
import '../../domain/task_status.dart';
import '../providers/tasks_provider.dart';
import 'add_task_dialog.dart';
import 'category_badge.dart';
import 'due_date_badge.dart';
import 'priority_badge.dart';
import 'reminder_badge.dart';

class TaskItemWidget extends ConsumerWidget {
  final TaskEntity task;

  const TaskItemWidget({super.key, required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isCompleted = task.status == TaskStatus.completed.value;
    final priority = TaskPriority.fromValue(task.priority);
    final category = task.categoryId == null
        ? null
        : TaskCategory.fromId(task.categoryId);

    final now = DateTime.now();
    final isOverdue =
        !isCompleted &&
        task.dueDate != null &&
        task.dueDate!.isBefore(DateTime(now.year, now.month, now.day));

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isOverdue
              ? theme.colorScheme.error.withValues(alpha: 0.6)
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      color: isCompleted
          ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4)
          : theme.colorScheme.surface,
      // Статус меняется только через чекбокс, тап по телу карточки ничего не делает.
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: isCompleted,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
              onChanged: (_) =>
                  ref.read(tasksControllerProvider).toggleTaskStatus(task),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          task.title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            decoration: isCompleted
                                ? TextDecoration.lineThrough
                                : null,
                            color: isCompleted
                                ? theme.colorScheme.onSurfaceVariant
                                : theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (task.description?.isNotEmpty == true) ...[
                    const SizedBox(height: 4),
                    Text(
                      task.description!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        decoration: isCompleted
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      PriorityBadge(priority: priority),
                      // Задачи без категории — без бейджа, чтобы не шуметь.
                      if (category != null)
                        CategoryBadge(
                          key: ValueKey('task-category-${task.id}'),
                          category: category,
                        ),
                      if (task.dueDate != null)
                        DueDateBadge(
                          dueDate: task.dueDate!,
                          isOverdue: isOverdue,
                        ),
                      if (task.reminderAt != null)
                        ReminderBadge(
                          key: ValueKey('task-reminder-${task.id}'),
                          reminderAt: task.reminderAt!,
                          isActive:
                              isReminderPending(task) &&
                              task.reminderAt!.isAfter(now),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              key: ValueKey('task-edit-${task.id}'),
              tooltip: 'Редактировать',
              icon: const Icon(Icons.edit_outlined, size: 20),
              color: theme.colorScheme.onSurfaceVariant,
              onPressed: () => showFormSheet(
                context: context,
                builder: (_) => AddTaskDialog(taskToEdit: task),
              ),
            ),
            IconButton(
              tooltip: 'Удалить',
              icon: const Icon(Icons.delete_outline, size: 20),
              color: theme.colorScheme.onSurfaceVariant,
              onPressed: () => _confirmDelete(context, ref),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить задачу?'),
        content: const Text('Вы действительно хотите удалить эту задачу?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      ref.read(tasksControllerProvider).deleteTask(task.id);
    }
  }
}
