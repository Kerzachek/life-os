import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/widgets/responsive.dart';
import '../../domain/task_category.dart';
import '../../domain/task_priority.dart';
import '../../domain/task_recurrence.dart';
import '../../domain/task_reminder.dart';
import '../../domain/task_status.dart';
import '../providers/tasks_provider.dart';
import 'add_task_dialog.dart';
import 'category_badge.dart';
import 'due_date_badge.dart';
import 'priority_badge.dart';
import 'reminder_badge.dart';
import 'subtask_list.dart';

class TaskItemWidget extends ConsumerStatefulWidget {
  final TaskEntity task;

  const TaskItemWidget({super.key, required this.task});

  @override
  ConsumerState<TaskItemWidget> createState() => _TaskItemWidgetState();
}

class _TaskItemWidgetState extends ConsumerState<TaskItemWidget> {
  bool _expanded = false;

  TaskEntity get task => widget.task;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final recurrence = TaskRecurrence.parse(task.recurrenceRule);
    final subtasks = ref.watch(subtasksProvider(task.id));
    final completedSubtasks = subtasks
        .where((t) => t.status == TaskStatus.completed.value)
        .length;
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
                      if (recurrence != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Tooltip(
                            message: recurrence.label,
                            child: Icon(
                              Icons.repeat_rounded,
                              key: ValueKey('task-recurring-${task.id}'),
                              size: 16,
                              color: theme.colorScheme.primary,
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
                  if (subtasks.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    SubtaskProgress(
                      key: ValueKey('task-subtask-progress-${task.id}'),
                      completed: completedSubtasks,
                      total: subtasks.length,
                    ),
                  ],
                  if (_expanded) ...[
                    const SizedBox(height: 4),
                    SubtaskList(parent: task, subtasks: subtasks),
                  ],
                ],
              ),
            ),
            IconButton(
              key: ValueKey('task-expand-${task.id}'),
              tooltip: _expanded ? 'Свернуть подзадачи' : 'Подзадачи',
              icon: Icon(
                _expanded
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
                size: 20,
              ),
              color: theme.colorScheme.onSurfaceVariant,
              onPressed: () => setState(() => _expanded = !_expanded),
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
              onPressed: () => _confirmDelete(subtasks.length),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(int subtaskCount) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить задачу?'),
        content: Text(
          subtaskCount == 0
              ? 'Вы действительно хотите удалить эту задачу?'
              : 'Вы действительно хотите удалить эту задачу '
                  'и её подзадачи ($subtaskCount)?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      ref.read(tasksControllerProvider).deleteTask(task.id);
    }
  }
}
