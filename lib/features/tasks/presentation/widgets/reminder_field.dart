import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/task_reminder.dart';

final _reminderFormat = DateFormat('dd.MM.yyyy HH:mm');

/// Блок «Напоминание» формы задачи. При заданном сроке предлагает быстрые
/// пресеты, без срока — сразу выбор произвольной даты и времени.
class ReminderField extends StatelessWidget {
  final DateTime? dueDate;
  final DateTime? reminderAt;
  final ValueChanged<DateTime?> onChanged;

  const ReminderField({
    super.key,
    required this.dueDate,
    required this.reminderAt,
    required this.onChanged,
  });

  Future<void> _pickCustom(BuildContext context) async {
    final now = DateTime.now();
    final due = dueDate;
    final initial = reminderAt?.toLocal() ??
        (due != null
            ? ReminderPreset.dayOf.resolve(due)!
            : now.add(const Duration(hours: 1)));

    var firstDate = DateTime(now.year, now.month, now.day);
    var lastDate = now.add(const Duration(days: 365 * 5));
    if (initial.isBefore(firstDate)) firstDate = initial;
    if (initial.isAfter(lastDate)) lastDate = initial;

    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstDate,
      lastDate: lastDate,
      helpText: 'Дата напоминания',
    );
    if (date == null || !context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      helpText: 'Время напоминания',
    );
    if (time == null) return;
    onChanged(
      DateTime(date.year, date.month, date.day, time.hour, time.minute),
    );
  }

  void _select(BuildContext context, ReminderPreset preset) {
    switch (preset) {
      case ReminderPreset.none:
        onChanged(null);
      case ReminderPreset.custom:
        _pickCustom(context);
      case ReminderPreset.dayOf:
      case ReminderPreset.dayBefore:
      case ReminderPreset.twoHoursBefore:
        onChanged(preset.resolve(dueDate!));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reminder = reminderAt;
    final isPast = reminder != null && reminder.isBefore(DateTime.now());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (dueDate == null)
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey('task-reminder-button'),
                  icon: const Icon(Icons.notifications_outlined, size: 18),
                  label: Text(
                    reminder == null
                        ? 'Напоминание'
                        : _reminderFormat.format(reminder.toLocal()),
                  ),
                  onPressed: () => _pickCustom(context),
                ),
              ),
              if (reminder != null)
                IconButton(
                  tooltip: 'Без напоминания',
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () => onChanged(null),
                ),
            ],
          )
        else ...[
          Row(
            children: [
              Icon(
                Icons.notifications_outlined,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text('Напоминание', style: theme.textTheme.titleSmall),
              if (reminder != null) ...[
                const Spacer(),
                Text(
                  _reminderFormat.format(reminder.toLocal()),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final preset in ReminderPreset.values)
                ChoiceChip(
                  key: ValueKey('reminder-preset-${preset.name}'),
                  label: Text(preset.label),
                  selected:
                      ReminderPreset.detect(reminder, dueDate) == preset,
                  onSelected: (_) => _select(context, preset),
                ),
            ],
          ),
        ],
        if (isPast) ...[
          const SizedBox(height: 4),
          Text(
            'Время уже прошло — уведомление придёт сразу после сохранения',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }
}
