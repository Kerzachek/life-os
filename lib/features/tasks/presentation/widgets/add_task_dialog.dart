import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/database/app_database.dart';
import '../../domain/task_category.dart';
import '../../domain/task_priority.dart';
import '../providers/tasks_provider.dart';
import 'category_dropdown_field.dart';

/// Универсальная форма задачи: создание (`taskToEdit == null`) или
/// редактирование существующей задачи.
class AddTaskDialog extends ConsumerStatefulWidget {
  final TaskEntity? taskToEdit;

  const AddTaskDialog({super.key, this.taskToEdit});

  @override
  ConsumerState<AddTaskDialog> createState() => _AddTaskDialogState();
}

class _AddTaskDialogState extends ConsumerState<AddTaskDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;

  DateTime? _dueDate;
  late TaskPriority _priority;
  late TaskCategory _category;

  bool get _isEditing => widget.taskToEdit != null;

  @override
  void initState() {
    super.initState();
    final task = widget.taskToEdit;
    _titleController = TextEditingController(text: task?.title ?? '');
    _descriptionController =
        TextEditingController(text: task?.description ?? '');
    _dueDate = task?.dueDate;
    _priority =
        task != null ? TaskPriority.fromValue(task.priority) : TaskPriority.medium;
    _category = TaskCategory.fromId(task?.categoryId);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final title = _titleController.text.trim();
    final description = _descriptionController.text.trim().isEmpty
        ? null
        : _descriptionController.text.trim();
    final controller = ref.read(tasksControllerProvider);
    final task = widget.taskToEdit;

    if (task != null) {
      controller.updateTask(
        id: task.id,
        title: title,
        description: description,
        dueDate: _dueDate,
        priority: _priority,
        category: _category,
      );
    } else {
      controller.createTask(
        title: title,
        description: description,
        dueDate: _dueDate,
        priority: _priority,
        category: _category,
      );
    }
    Navigator.of(context).pop();
  }

  Future<void> _confirmDelete() async {
    final task = widget.taskToEdit;
    if (task == null) return;

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
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      ref.read(tasksControllerProvider).deleteTask(task.id);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEditing ? 'Редактировать задачу' : 'Новая задача'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Название *',
                  hintText: 'Что нужно сделать?',
                  border: OutlineInputBorder(),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Введите название задачи';
                  }
                  return null;
                },
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Описание',
                  hintText: 'Заметки, подробности...',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<TaskPriority>(
                initialValue: _priority,
                decoration: const InputDecoration(
                  labelText: 'Приоритет',
                  border: OutlineInputBorder(),
                ),
                items: TaskPriority.values.map((p) {
                  return DropdownMenuItem(
                    value: p,
                    child: Row(
                      children: [
                        Icon(Icons.circle, size: 12, color: p.color),
                        const SizedBox(width: 8),
                        Text(p.label),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _priority = val);
                },
              ),
              const SizedBox(height: 12),
              CategoryDropdownField(
                value: _category,
                onChanged: (val) => setState(() => _category = val),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.calendar_today, size: 18),
                      label: Text(
                        _dueDate == null
                            ? 'Срок выполнения'
                            : DateFormat('dd.MM.yyyy').format(_dueDate!),
                      ),
                      onPressed: () async {
                        final now = DateTime.now();
                        var firstDate = now.subtract(const Duration(days: 1));
                        var lastDate = now.add(const Duration(days: 365 * 5));
                        // Существующий срок может выходить за обычные границы.
                        final current = _dueDate;
                        if (current != null) {
                          if (current.isBefore(firstDate)) firstDate = current;
                          if (current.isAfter(lastDate)) lastDate = current;
                        }
                        final date = await showDatePicker(
                          context: context,
                          initialDate: current ?? now,
                          firstDate: firstDate,
                          lastDate: lastDate,
                        );
                        if (date != null) {
                          setState(() => _dueDate = date);
                        }
                      },
                    ),
                  ),
                  if (_dueDate != null)
                    IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () => setState(() => _dueDate = null),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (_isEditing)
          TextButton(
            onPressed: _confirmDelete,
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Удалить'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(_isEditing ? 'Сохранить изменения' : 'Создать'),
        ),
      ],
    );
  }
}
