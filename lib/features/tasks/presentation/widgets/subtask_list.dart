import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../domain/task_status.dart';
import '../providers/tasks_provider.dart';

/// Счётчик «Подзадачи: 2/5» с линейным прогрессом.
class SubtaskProgress extends StatelessWidget {
  final int completed;
  final int total;

  const SubtaskProgress({
    super.key,
    required this.completed,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Text(
          'Подзадачи: $completed/$total',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : completed / total,
              minHeight: 4,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
          ),
        ),
      ],
    );
  }
}

/// Раскрытый список подзадач с чекбоксами и полем быстрого добавления.
class SubtaskList extends ConsumerStatefulWidget {
  final TaskEntity parent;
  final List<TaskEntity> subtasks;

  const SubtaskList({super.key, required this.parent, required this.subtasks});

  @override
  ConsumerState<SubtaskList> createState() => _SubtaskListState();
}

class _SubtaskListState extends ConsumerState<SubtaskList> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final title = _controller.text.trim();
    if (title.isEmpty) return;
    _controller.clear();
    _focusNode.requestFocus();
    await ref.read(tasksControllerProvider).addSubtask(widget.parent.id, title);
  }

  Future<void> _toggle(TaskEntity subtask) async {
    final controller = ref.read(tasksControllerProvider);
    await controller.toggleTaskStatus(subtask);

    final completing = subtask.status != TaskStatus.completed.value;
    final othersDone = widget.subtasks
        .where((t) => t.id != subtask.id)
        .every((t) => t.status == TaskStatus.completed.value);
    if (!completing ||
        !othersDone ||
        widget.parent.status == TaskStatus.completed.value ||
        !mounted) {
      return;
    }

    final close = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Все подзадачи выполнены'),
        content: Text('Завершить задачу «${widget.parent.title}»?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Позже'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Завершить'),
          ),
        ],
      ),
    );
    if (close == true) await controller.toggleTaskStatus(widget.parent);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final subtask in widget.subtasks)
          _SubtaskRow(
            key: ValueKey('subtask-${subtask.id}'),
            subtask: subtask,
            onToggle: () => _toggle(subtask),
            onDelete: () =>
                ref.read(tasksControllerProvider).deleteTask(subtask.id),
          ),
        TextField(
          key: ValueKey('subtask-add-${widget.parent.id}'),
          controller: _controller,
          focusNode: _focusNode,
          style: theme.textTheme.bodyMedium,
          decoration: InputDecoration(
            isDense: true,
            hintText: '+ Добавить подзадачу',
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 4,
              vertical: 10,
            ),
            suffixIcon: IconButton(
              tooltip: 'Добавить',
              icon: const Icon(Icons.add, size: 18),
              onPressed: _add,
            ),
          ),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _add(),
        ),
      ],
    );
  }
}

class _SubtaskRow extends StatelessWidget {
  final TaskEntity subtask;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  const _SubtaskRow({
    super.key,
    required this.subtask,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCompleted = subtask.status == TaskStatus.completed.value;
    return Row(
      children: [
        Checkbox(
          value: isCompleted,
          visualDensity: VisualDensity.compact,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          onChanged: (_) => onToggle(),
        ),
        Expanded(
          child: Text(
            subtask.title,
            style: theme.textTheme.bodyMedium?.copyWith(
              decoration: isCompleted ? TextDecoration.lineThrough : null,
              color: isCompleted
                  ? theme.colorScheme.onSurfaceVariant
                  : theme.colorScheme.onSurface,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Удалить подзадачу',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.close, size: 16),
          color: theme.colorScheme.onSurfaceVariant,
          onPressed: onDelete,
        ),
      ],
    );
  }
}
