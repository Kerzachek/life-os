import '../../../core/database/app_database.dart';
import 'task_status.dart';

/// Час напоминаний «в день задачи» и «за сутки».
const int taskReminderHour = 9;

/// Момент, к которому задача должна быть выполнена. Срок без времени
/// (полночь) означает «в течение дня» — дедлайн в конце этого дня.
DateTime taskDeadline(DateTime dueDate) {
  final local = dueDate.toLocal();
  final isDateOnly = local.hour == 0 &&
      local.minute == 0 &&
      local.second == 0 &&
      local.millisecond == 0;
  return isDateOnly
      ? DateTime(local.year, local.month, local.day + 1)
      : local;
}

/// Быстрые варианты напоминания в форме задачи.
enum ReminderPreset {
  none('Без напоминания'),
  dayOf('В день задачи (09:00)'),
  dayBefore('За сутки (09:00)'),
  twoHoursBefore('За 2 часа'),
  custom('Выбрать дату и время...');

  final String label;
  const ReminderPreset(this.label);

  /// Пресет вычисляется от срока задачи.
  bool get isRelative =>
      this == dayOf || this == dayBefore || this == twoHoursBefore;

  /// Время напоминания для относительного пресета; иначе `null`.
  DateTime? resolve(DateTime dueDate) {
    final due = dueDate.toLocal();
    switch (this) {
      case dayOf:
        return DateTime(due.year, due.month, due.day, taskReminderHour);
      case dayBefore:
        return DateTime(due.year, due.month, due.day - 1, taskReminderHour);
      case twoHoursBefore:
        return taskDeadline(due).subtract(const Duration(hours: 2));
      case none:
      case custom:
        return null;
    }
  }

  /// Пресет, которому соответствует сохранённое время напоминания.
  static ReminderPreset detect(DateTime? reminderAt, DateTime? dueDate) {
    if (reminderAt == null) return none;
    if (dueDate != null) {
      for (final preset in values.where((p) => p.isRelative)) {
        if (preset.resolve(dueDate)!.isAtSameMomentAs(reminderAt)) {
          return preset;
        }
      }
    }
    return custom;
  }
}

/// Напоминание ещё «ждёт»: задано, не отправлено и задача не завершена.
bool isReminderPending(TaskEntity task) =>
    task.reminderAt != null &&
    !task.isReminderSent &&
    task.status != TaskStatus.completed.value &&
    task.status != TaskStatus.cancelled.value;

/// Задачи, напоминание которых пора отправить.
List<TaskEntity> dueTaskReminders(List<TaskEntity> tasks, DateTime now) {
  return tasks
      .where((t) =>
          t.deletedAt == null &&
          isReminderPending(t) &&
          !t.reminderAt!.isAfter(now))
      .toList();
}
