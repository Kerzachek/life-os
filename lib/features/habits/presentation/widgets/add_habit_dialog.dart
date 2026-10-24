import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/widgets/responsive.dart';
import '../../../finance/presentation/widgets/choice_tile.dart';
import '../../domain/habit_appearance.dart';
import '../../domain/habit_frequency.dart';
import '../providers/habits_provider.dart';

/// Форма создания / редактирования привычки. При переданном [habit] поля
/// предзаполняются, а сохранение обновляет привычку, не трогая её историю.
class AddHabitDialog extends ConsumerStatefulWidget {
  const AddHabitDialog({super.key, this.habit});

  final HabitEntity? habit;

  @override
  ConsumerState<AddHabitDialog> createState() => _AddHabitDialogState();
}

class _AddHabitDialogState extends ConsumerState<AddHabitDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _targetValueController;
  late final TextEditingController _unitController;

  late final TextEditingController _intervalController;

  late HabitFrequencyType _frequencyType;
  late Set<int> _weekdays;
  late String _iconKey;
  late Color _color;

  bool get _isEdit => widget.habit != null;

  @override
  void initState() {
    super.initState();
    final h = widget.habit;
    _titleController = TextEditingController(text: h?.title ?? '');
    _descriptionController = TextEditingController(text: h?.description ?? '');
    _targetValueController = TextEditingController(
      text: '${h?.targetValue ?? 1}',
    );
    _unitController = TextEditingController(
      text: h == null ? 'раз' : h.unit ?? '',
    );
    final schedule = h == null
        ? const HabitSchedule.daily()
        : HabitSchedule.parse(h.frequencyType, h.frequencyValue);
    _frequencyType = schedule.type;
    _weekdays = schedule.weekdays.isEmpty
        ? habitWeekdayLabels.keys.toSet()
        : {...schedule.weekdays};
    _intervalController = TextEditingController(
      text: '${schedule.intervalDays < 2 ? 2 : schedule.intervalDays}',
    );
    _iconKey = habitIcons.containsKey(h?.icon) ? h!.icon! : defaultHabitIconKey;
    _color = habitColorFromHex(h?.color) ?? habitColorPalette.first;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _targetValueController.dispose();
    _unitController.dispose();
    _intervalController.dispose();
    super.dispose();
  }

  /// Значение `frequencyValue` для выбранной регулярности.
  String? _frequencyValue() {
    switch (_frequencyType) {
      case HabitFrequencyType.daily:
        return null;
      case HabitFrequencyType.weekly:
        return HabitSchedule.weekly(_weekdays).encode();
      case HabitFrequencyType.interval:
        return HabitSchedule.interval(
          int.tryParse(_intervalController.text.trim()) ?? 1,
        ).encode();
    }
  }

  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      final targetVal = int.tryParse(_targetValueController.text.trim()) ?? 1;
      final title = _titleController.text.trim();
      final description = _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim();
      final unit = _unitController.text.trim().isEmpty
          ? null
          : _unitController.text.trim();
      final controller = ref.read(habitsControllerProvider);

      if (_isEdit) {
        controller.updateHabit(
          id: widget.habit!.id,
          title: title,
          description: description,
          frequencyType: _frequencyType,
          frequencyValue: _frequencyValue(),
          targetValue: targetVal,
          unit: unit,
          color: habitColorToHex(_color),
          icon: _iconKey,
        );
      } else {
        controller.createHabit(
          title: title,
          description: description,
          frequencyType: _frequencyType,
          frequencyValue: _frequencyValue(),
          targetValue: targetVal,
          unit: unit,
          color: habitColorToHex(_color),
          icon: _iconKey,
        );
      }
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = Theme.of(context).textTheme.labelMedium;
    return AdaptiveFormDialog(
      title: Text(_isEdit ? 'Редактировать привычку' : 'Новая привычка'),
      content: SizedBox(
        width: formDialogWidth,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  key: const ValueKey('habit_title'),
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: 'Название привычки *',
                    hintText: 'Зарядка, Пить воду, Чтение...',
                    border: OutlineInputBorder(),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Введите название привычки';
                    }
                    return null;
                  },
                  autofocus: !_isEdit,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Заметки / Описание',
                    hintText: 'Почему это важно, детали...',
                    border: OutlineInputBorder(),
                  ),
                  minLines: 2,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        key: const ValueKey('habit_target'),
                        controller: _targetValueController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Цель в день *',
                          border: OutlineInputBorder(),
                        ),
                        validator: (val) {
                          if (val == null || int.tryParse(val) == null) {
                            return 'Число';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: _unitController,
                        decoration: const InputDecoration(
                          labelText: 'Ед. изм.',
                          hintText: 'раз, мин, мл',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<HabitFrequencyType>(
                  initialValue: _frequencyType,
                  decoration: const InputDecoration(
                    labelText: 'Регулярность',
                    border: OutlineInputBorder(),
                  ),
                  items: HabitFrequencyType.values.map((f) {
                    return DropdownMenuItem(value: f, child: Text(f.label));
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _frequencyType = val);
                  },
                ),
                if (_frequencyType == HabitFrequencyType.weekly) ...[
                  const SizedBox(height: 12),
                  FormField<Set<int>>(
                    validator: (_) =>
                        _weekdays.isEmpty ? 'Выберите хотя бы один день' : null,
                    builder: (field) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final e in habitWeekdayLabels.entries)
                              FilterChip(
                                key: ValueKey('habit_weekday_${e.key}'),
                                label: Text(e.value),
                                selected: _weekdays.contains(e.key),
                                onSelected: (on) => setState(() {
                                  if (on) {
                                    _weekdays.add(e.key);
                                  } else {
                                    _weekdays.remove(e.key);
                                  }
                                  field.didChange(_weekdays);
                                }),
                              ),
                          ],
                        ),
                        if (field.errorText != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              field.errorText!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                if (_frequencyType == HabitFrequencyType.interval) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const ValueKey('habit_interval'),
                    controller: _intervalController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Каждые N дней *',
                      border: OutlineInputBorder(),
                    ),
                    validator: (val) {
                      final n = int.tryParse(val?.trim() ?? '');
                      if (n == null || n < 1) return 'Число от 1';
                      return null;
                    },
                  ),
                ],
                const SizedBox(height: 16),
                Text('Иконка', style: label),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final e in habitIcons.entries)
                      ChoiceTile(
                        key: ValueKey('habit_icon_${e.key}'),
                        selected: e.key == _iconKey,
                        color: _color,
                        onTap: () => setState(() => _iconKey = e.key),
                        child: Icon(e.value, size: 20),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text('Цвет', style: label),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (var i = 0; i < habitColorPalette.length; i++)
                      ChoiceTile(
                        key: ValueKey('habit_color_$i'),
                        selected: habitColorPalette[i] == _color,
                        color: habitColorPalette[i],
                        onTap: () =>
                            setState(() => _color = habitColorPalette[i]),
                        child: CircleAvatar(
                          radius: 10,
                          backgroundColor: habitColorPalette[i],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          key: const ValueKey('habit_submit'),
          onPressed: _submit,
          child: Text(_isEdit ? 'Сохранить' : 'Создать'),
        ),
      ],
    );
  }
}
