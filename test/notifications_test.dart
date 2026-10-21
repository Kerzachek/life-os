import 'package:flutter_test/flutter_test.dart';
import 'package:home_organizer/core/database/app_database.dart';
import 'package:home_organizer/core/services/notification_scheduler.dart';
import 'package:home_organizer/features/finance/domain/finance_calculations.dart';
import 'package:home_organizer/features/habits/domain/habit_with_status.dart';
import 'package:home_organizer/features/overview/domain/productivity.dart';
import 'package:home_organizer/features/tasks/domain/task_status.dart';

final _created = DateTime.utc(2026, 1, 1);

TaskEntity _task(String title, {DateTime? due, int status = 0}) => TaskEntity(
      id: title,
      createdAt: _created,
      updatedAt: _created,
      title: title,
      dueDate: due,
      priority: 1,
      status: status,
      isReminderSent: false,
    );

HabitWithStatus _habit(String title, {bool done = false}) => HabitWithStatus(
      habit: HabitEntity(
        id: title,
        createdAt: _created,
        updatedAt: _created,
        title: title,
        frequencyType: 0,
        targetValue: 1,
        isArchived: false,
      ),
      isCompletedToday: done,
      todayLoggedValue: done ? 1 : 0,
      streakCount: 0,
      recentLogs: const [],
    );

ObligationStatus _payment(String name, ObligationUrgency urgency,
        {bool paid = false}) =>
    ObligationStatus(
      obligation: ObligationEntity(
        id: name,
        createdAt: _created,
        updatedAt: _created,
        name: name,
        amount: 100,
        dueDay: 1,
      ),
      isPaid: paid,
      urgency: urgency,
    );

void main() {
  group('overallProductivity', () {
    test('учитывает только активные разделы', () {
      expect(overallProductivity([0.5, null]), 0.5);
      expect(overallProductivity([1.0, 0.5]), 0.75);
      expect(overallProductivity([null, null]), isNull);
      expect(overallProductivity([]), isNull);
    });
  });

  group('напоминания', () {
    final now = DateTime(2026, 10, 21, 21);

    test('задачи: только невыполненные со сроком сегодня или ранее', () {
      final message = buildTasksReminder([
        _task('Сегодня', due: DateTime(2026, 10, 21, 18)),
        _task('Вчера', due: DateTime(2026, 10, 20)),
        _task('Завтра', due: DateTime(2026, 10, 22)),
        _task('Без срока'),
        _task('Готово',
            due: DateTime(2026, 10, 21), status: TaskStatus.completed.value),
      ], now);
      expect(message, isNotNull);
      expect(message!.body, contains('Невыполненных задач: 2 (просрочено: 1)'));
      expect(message.body, isNot(contains('Завтра')));

      expect(buildTasksReminder([_task('Без срока')], now), isNull);
    });

    test('привычки: только вечером и только невыполненные', () {
      final habits = [_habit('Спорт'), _habit('Чтение', done: true)];
      expect(buildHabitsReminder(habits, DateTime(2026, 10, 21, 12)), isNull);
      final message = buildHabitsReminder(habits, now);
      expect(message!.body, 'Сегодня ещё не выполнено: 1. Спорт');
      expect(buildHabitsReminder([_habit('Чтение', done: true)], now), isNull);
    });

    test('платежи: неоплаченные, срок которых близко или прошёл', () {
      final message = buildPaymentsReminder([
        _payment('Аренда', ObligationUrgency.overdue),
        _payment('ЖКХ', ObligationUrgency.upcoming),
        _payment('Связь', ObligationUrgency.dueToday, paid: true),
        _payment('Кредит', ObligationUrgency.scheduled),
      ]);
      expect(message!.body, 'Требуют оплаты: 2 (просрочено: 1). Аренда, ЖКХ');
      expect(
        buildPaymentsReminder(
            [_payment('Кредит', ObligationUrgency.scheduled)]),
        isNull,
      );
    });
  });
}
