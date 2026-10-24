/// Частота повторения задачи.
enum RecurrenceFrequency {
  daily('daily', 'Каждый день'),
  weekly('weekly', 'Каждую неделю'),
  monthly('monthly', 'Каждый месяц'),
  yearly('yearly', 'Каждый год');

  final String code;
  final String label;
  const RecurrenceFrequency(this.code, this.label);
}

/// Правило повторения, хранимое в `tasks.recurrence_rule`.
///
/// Формат: `daily`, `weekly:1,3,5` (дни недели по [DateTime.weekday]),
/// `monthly`, `yearly`. Еженедельное правило без дней повторяется в тот же
/// день недели, что и срок задачи.
class TaskRecurrence {
  final RecurrenceFrequency frequency;

  /// Дни недели (1 = пн … 7 = вс), только для [RecurrenceFrequency.weekly].
  final Set<int> weekdays;

  TaskRecurrence(this.frequency, {Set<int> weekdays = const {}})
    : weekdays = frequency == RecurrenceFrequency.weekly
          ? weekdays.where((d) => d >= 1 && d <= 7).toSet()
          : const {};

  /// Разбор сохранённого правила; пустое или неизвестное — `null`.
  static TaskRecurrence? parse(String? rule) {
    if (rule == null || rule.trim().isEmpty) return null;
    final parts = rule.trim().split(':');
    for (final frequency in RecurrenceFrequency.values) {
      if (frequency.code != parts.first) continue;
      final days = parts.length > 1
          ? parts[1]
                .split(',')
                .map((d) => int.tryParse(d.trim()))
                .whereType<int>()
                .toSet()
          : <int>{};
      return TaskRecurrence(frequency, weekdays: days);
    }
    return null;
  }

  String encode() {
    if (frequency == RecurrenceFrequency.weekly && weekdays.isNotEmpty) {
      return '${frequency.code}:${(weekdays.toList()..sort()).join(',')}';
    }
    return frequency.code;
  }

  /// Подпись для интерфейса: «Каждую неделю (пн, ср)».
  String get label {
    if (frequency != RecurrenceFrequency.weekly || weekdays.isEmpty) {
      return frequency.label;
    }
    final days = (weekdays.toList()..sort()).map(
      (d) => weekdayShortNames[d - 1],
    );
    return '${frequency.label} (${days.join(', ')})';
  }

  /// Ближайшая дата повторения строго после [from]; время суток сохраняется.
  DateTime nextAfter(DateTime from) {
    switch (frequency) {
      case RecurrenceFrequency.daily:
        return _withDay(from, from.year, from.month, from.day + 1);
      case RecurrenceFrequency.weekly:
        if (weekdays.isEmpty) {
          return _withDay(from, from.year, from.month, from.day + 7);
        }
        for (var offset = 1; offset <= 7; offset++) {
          final candidate = _withDay(
            from,
            from.year,
            from.month,
            from.day + offset,
          );
          if (weekdays.contains(candidate.weekday)) return candidate;
        }
        return _withDay(from, from.year, from.month, from.day + 7);
      case RecurrenceFrequency.monthly:
        return _clamped(from, from.year, from.month + 1);
      case RecurrenceFrequency.yearly:
        return _clamped(from, from.year + 1, from.month);
    }
  }

  /// Срок следующего экземпляра: первое повторение после [due], не раньше
  /// сегодняшнего дня (просроченная задача не порождает «прошлые» копии).
  /// Задача без срока повторяется от [now].
  DateTime nextDueDate(DateTime? due, DateTime now) {
    final startOfToday = DateTime(now.year, now.month, now.day);
    var next = nextAfter(due ?? startOfToday);
    while (next.isBefore(startOfToday)) {
      next = nextAfter(next);
    }
    return next;
  }

  static DateTime _withDay(DateTime base, int year, int month, int day) =>
      DateTime(year, month, day, base.hour, base.minute, base.second);

  /// Тот же день месяца; 31-е в коротком месяце — последний день месяца.
  static DateTime _clamped(DateTime base, int year, int month) {
    final lastDay = DateTime(year, month + 1, 0).day;
    final day = base.day > lastDay ? lastDay : base.day;
    return _withDay(base, year, month, day);
  }

  @override
  bool operator ==(Object other) =>
      other is TaskRecurrence && other.encode() == encode();

  @override
  int get hashCode => encode().hashCode;
}

const weekdayShortNames = ['пн', 'вт', 'ср', 'чт', 'пт', 'сб', 'вс'];
