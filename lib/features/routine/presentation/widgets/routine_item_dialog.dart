import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/widgets/responsive.dart';
import '../../domain/routine_category.dart';
import '../providers/routine_provider.dart';

/// Добавление (если [item] не задан) или редактирование пункта рутины.
class RoutineItemDialog extends ConsumerStatefulWidget {
  final RoutineItemEntity? item;

  const RoutineItemDialog({super.key, this.item});

  @override
  ConsumerState<RoutineItemDialog> createState() => _RoutineItemDialogState();
}

class _RoutineItemDialogState extends ConsumerState<RoutineItemDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController =
      TextEditingController(text: widget.item?.title ?? '');
  late RoutineCategory _category = widget.item == null
      ? RoutineCategory.general
      : RoutineCategory.fromValue(widget.item!.category);

  bool get _isEditing => widget.item != null;

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final controller = ref.read(routineControllerProvider);
    final title = _titleController.text;
    if (_isEditing) {
      controller.updateItem(widget.item!, title, _category);
    } else {
      controller.createItem(title, _category);
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveFormDialog(
      title: Text(_isEditing ? 'Редактировать действие' : 'Новое действие'),
      content: SizedBox(
        width: 420,
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
                  hintText: 'Почистить зубы, Заправить кровать...',
                  border: OutlineInputBorder(),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Введите название действия';
                  }
                  return null;
                },
                onFieldSubmitted: (_) => _submit(),
                autofocus: true,
              ),
              const SizedBox(height: 16),
              Text(
                'Время дня',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in RoutineCategory.values)
                    ChoiceChip(
                      avatar: Icon(c.icon, size: 16, color: c.color),
                      label: Text(c.label),
                      selected: _category == c,
                      onSelected: (_) => setState(() => _category = c),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(_isEditing ? 'Сохранить' : 'Добавить'),
        ),
      ],
    );
  }
}
