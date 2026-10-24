import 'package:flutter/material.dart';

import '../../domain/task_recurrence.dart';

/// Блок повторения в форме задачи: частота и, для еженедельного
/// повторения, дни недели.
class RecurrenceField extends StatelessWidget {
  final TaskRecurrence? value;

  /// Срок задачи — из него берётся день недели по умолчанию.
  final DateTime? dueDate;
  final ValueChanged<TaskRecurrence?> onChanged;

  const RecurrenceField({
    super.key,
    required this.value,
    required this.dueDate,
    required this.onChanged,
  });

  void _setFrequency(RecurrenceFrequency? frequency) {
    if (frequency == null) {
      onChanged(null);
      return;
    }
    final defaultDay = (dueDate ?? DateTime.now()).weekday;
    onChanged(TaskRecurrence(frequency, weekdays: {defaultDay}));
  }

  void _toggleDay(int day) {
    final days = {...value!.weekdays};
    if (!days.remove(day)) days.add(day);
    // Хотя бы один день должен остаться выбранным.
    if (days.isEmpty) return;
    onChanged(TaskRecurrence(RecurrenceFrequency.weekly, weekdays: days));
  }

  @override
  Widget build(BuildContext context) {
    final recurrence = value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<RecurrenceFrequency?>(
          key: const ValueKey('task-recurrence-field'),
          initialValue: recurrence?.frequency,
          decoration: const InputDecoration(
            labelText: 'Повторение',
            prefixIcon: Icon(Icons.repeat_rounded),
            border: OutlineInputBorder(),
          ),
          items: [
            const DropdownMenuItem(value: null, child: Text('Не повторять')),
            for (final frequency in RecurrenceFrequency.values)
              DropdownMenuItem(value: frequency, child: Text(frequency.label)),
          ],
          onChanged: _setFrequency,
        ),
        if (recurrence?.frequency == RecurrenceFrequency.weekly) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (var day = 1; day <= 7; day++)
                FilterChip(
                  key: ValueKey('task-recurrence-day-$day'),
                  label: Text(weekdayShortNames[day - 1]),
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                  selected: recurrence!.weekdays.contains(day),
                  onSelected: (_) => _toggleDay(day),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
