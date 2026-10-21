import 'package:intl/intl.dart';

import '../../../core/database/app_database.dart';

final DateFormat _dayFormat = DateFormat('yyyy-MM-dd');

/// Локальная дата в формате `YYYY-MM-DD`.
String routineDayKey(DateTime moment) => _dayFormat.format(moment.toLocal());

/// Начало локальных суток для [moment].
DateTime startOfLocalDay(DateTime moment) {
  final local = moment.toLocal();
  return DateTime(local.year, local.month, local.day);
}

/// Отмечен ли пункт сегодня. Отметки прошлых дней (ещё не сброшенные или
/// пришедшие синхронизацией с другого устройства) не считаются.
bool isRoutineDoneToday(RoutineItemEntity item, DateTime now) {
  final completedAt = item.completedAt;
  if (!item.isCompleted || completedAt == null) return false;
  return !completedAt.toLocal().isBefore(startOfLocalDay(now));
}

/// Выполнение рутины за один день (сохранённое или текущее).
class RoutineDayStat {
  final DateTime day;
  final int completed;
  final int total;

  const RoutineDayStat({
    required this.day,
    required this.completed,
    required this.total,
  });

  bool get hasData => total > 0;

  double get rate => total > 0 ? (completed / total).clamp(0.0, 1.0) : 0.0;
}

/// Ряд из [days] последних дней (включая сегодня) для диаграммы.
///
/// Прошлые дни берутся из [logs], сегодняшний — из текущего чек-листа.
/// Дни без записи (приложение не запускалось) получают `total == 0`.
List<RoutineDayStat> buildRoutineHistory({
  required List<RoutineDailyLogEntity> logs,
  required int todayCompleted,
  required int todayTotal,
  required DateTime now,
  required int days,
}) {
  final byDate = {for (final log in logs) log.date: log};
  final today = startOfLocalDay(now);
  final result = <RoutineDayStat>[];
  for (var i = days - 1; i >= 0; i--) {
    final day = DateTime(today.year, today.month, today.day - i);
    if (i == 0) {
      result.add(RoutineDayStat(
        day: day,
        completed: todayCompleted,
        total: todayTotal,
      ));
      continue;
    }
    final log = byDate[routineDayKey(day)];
    result.add(RoutineDayStat(
      day: day,
      completed: log?.completedCount ?? 0,
      total: log?.totalCount ?? 0,
    ));
  }
  return result;
}
