import 'dart:convert';

enum HabitFrequencyType {
  daily(0, 'Ежедневно'),
  weekly(1, 'По дням недели'),
  interval(2, 'Интервал');

  final int value;
  final String label;

  const HabitFrequencyType(this.value, this.label);

  static HabitFrequencyType fromValue(int value) {
    return HabitFrequencyType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => HabitFrequencyType.daily,
    );
  }
}

/// Названия дней недели по [DateTime.weekday] (1 — понедельник).
const Map<int, String> habitWeekdayLabels = {
  DateTime.monday: 'Пн',
  DateTime.tuesday: 'Вт',
  DateTime.wednesday: 'Ср',
  DateTime.thursday: 'Чт',
  DateTime.friday: 'Пт',
  DateTime.saturday: 'Сб',
  DateTime.sunday: 'Вс',
};

/// Расписание привычки: тип регулярности и его параметры из
/// `habits.frequency_value` (JSON):
/// * «По дням недели» — список дней [DateTime.weekday], например `[1,3,5]`;
/// * «Интервал» — число дней между выполнениями, например `2`.
///
/// Без параметров (или при битом JSON) «По дням недели» означает все дни,
/// а интервал — 1 день.
class HabitSchedule {
  const HabitSchedule.daily()
    : type = HabitFrequencyType.daily,
      weekdays = const {},
      intervalDays = 1;

  HabitSchedule.weekly(Set<int> days)
    : type = HabitFrequencyType.weekly,
      weekdays = Set.unmodifiable(days.where(habitWeekdayLabels.containsKey)),
      intervalDays = 1;

  HabitSchedule.interval(int days)
    : type = HabitFrequencyType.interval,
      weekdays = const {},
      intervalDays = days < 1 ? 1 : days;

  factory HabitSchedule.parse(int frequencyType, String? frequencyValue) {
    final type = HabitFrequencyType.fromValue(frequencyType);
    Object? raw;
    try {
      raw = frequencyValue == null ? null : jsonDecode(frequencyValue);
    } on FormatException {
      raw = null;
    }
    switch (type) {
      case HabitFrequencyType.daily:
        return const HabitSchedule.daily();
      case HabitFrequencyType.weekly:
        return HabitSchedule.weekly({
          if (raw is List)
            for (final d in raw)
              if (d is num) d.toInt(),
        });
      case HabitFrequencyType.interval:
        return HabitSchedule.interval(raw is num ? raw.toInt() : 1);
    }
  }

  final HabitFrequencyType type;

  /// Дни недели для [HabitFrequencyType.weekly]; пустое множество — все дни.
  final Set<int> weekdays;

  /// Число дней между выполнениями для [HabitFrequencyType.interval].
  final int intervalDays;

  /// Значение для `habits.frequency_value` (`null` у ежедневной привычки).
  String? encode() {
    switch (type) {
      case HabitFrequencyType.daily:
        return null;
      case HabitFrequencyType.weekly:
        return jsonEncode(weekdays.toList()..sort());
      case HabitFrequencyType.interval:
        return jsonEncode(intervalDays);
    }
  }

  /// Запланирован ли день [date] для привычки «По дням недели».
  /// Ежедневная и интервальная привычки доступны в любой день.
  bool isScheduledWeekday(DateTime date) =>
      type != HabitFrequencyType.weekly ||
      weekdays.isEmpty ||
      weekdays.contains(date.weekday);
}

/// Предыдущий календарный день (локальная полночь). Календарная арифметика
/// вместо `subtract(Duration(days: 1))`: при переводе часов сутки длятся
/// 23 или 25 часов, и вычитание 24 часов попадает не в тот день.
DateTime previousDay(DateTime date) =>
    DateTime(date.year, date.month, date.day - 1);

/// Календарная дата (локальная полночь) момента [moment].
DateTime habitDay(DateTime moment) {
  final local = moment.toLocal();
  return DateTime(local.year, local.month, local.day);
}

/// Серия выполнений привычки на день [today].
///
/// [dailyTotals] — сумма отмеченных значений по календарным дням
/// ([habitDay]). День засчитывается, только если цель [targetValue]
/// достигнута. Пропуск обрывает серию лишь в запланированный день:
/// * ежедневно — любой невыполненный день;
/// * по дням недели — невыполненный день из расписания (прочие дни не
///   рвут серию, а выполнение в них засчитывается);
/// * интервал N — N невыполненных дней подряд.
///
/// Сегодняшний день ещё не закончился и серию не обрывает.
int calculateHabitStreak({
  required HabitSchedule schedule,
  required Map<DateTime, int> dailyTotals,
  required int targetValue,
  required DateTime today,
}) {
  final target = targetValue < 1 ? 1 : targetValue;
  final completed = {
    for (final e in dailyTotals.entries)
      if (e.value >= target) habitDay(e.key),
  };
  if (completed.isEmpty) return 0;
  final earliest = completed.reduce((a, b) => a.isBefore(b) ? a : b);

  final start = habitDay(today);
  var streak = 0;
  var missedInRow = 0;
  for (var day = start; !day.isBefore(earliest); day = previousDay(day)) {
    if (completed.contains(day)) {
      streak++;
      missedInRow = 0;
      continue;
    }
    if (day == start) continue;
    switch (schedule.type) {
      case HabitFrequencyType.daily:
        return streak;
      case HabitFrequencyType.weekly:
        if (schedule.isScheduledWeekday(day)) return streak;
      case HabitFrequencyType.interval:
        missedInRow++;
        if (missedInRow >= schedule.intervalDays) return streak;
    }
  }
  return streak;
}
