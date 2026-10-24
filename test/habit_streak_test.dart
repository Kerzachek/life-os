import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_organizer/core/database/app_database.dart';
import 'package:home_organizer/core/database/database_provider.dart';
import 'package:home_organizer/core/theme/app_theme.dart';
import 'package:home_organizer/features/habits/data/repositories/habits_repository.dart';
import 'package:home_organizer/features/habits/domain/habit_frequency.dart';
import 'package:home_organizer/features/habits/presentation/providers/habits_provider.dart';
import 'package:home_organizer/features/habits/presentation/widgets/add_habit_dialog.dart';

void main() {
  /// Среда, 2026-10-21.
  final wednesday = DateTime(2026, 10, 21);
  DateTime daysAgo(int n) =>
      DateTime(wednesday.year, wednesday.month, wednesday.day - n);

  Map<DateTime, int> done(Iterable<int> ago, {int value = 1}) => {
    for (final n in ago) daysAgo(n): value,
  };

  int streak(
    HabitSchedule schedule,
    Map<DateTime, int> totals, {
    int target = 1,
    DateTime? today,
  }) {
    return calculateHabitStreak(
      schedule: schedule,
      dailyTotals: totals,
      targetValue: target,
      today: today ?? wednesday,
    );
  }

  group('HabitSchedule', () {
    test('frequencyValue разбирается и кодируется', () {
      final weekly = HabitSchedule.parse(1, '[5,1,3]');
      expect(weekly.type, HabitFrequencyType.weekly);
      expect(weekly.weekdays, {1, 3, 5});
      expect(weekly.encode(), '[1,3,5]');

      final interval = HabitSchedule.parse(2, '3');
      expect(interval.intervalDays, 3);
      expect(interval.encode(), '3');

      expect(HabitSchedule.parse(0, '[1]').encode(), isNull);
    });

    test('без параметров или с битым JSON — безопасные значения', () {
      expect(HabitSchedule.parse(1, null).weekdays, isEmpty);
      expect(
        HabitSchedule.parse(1, 'oops').isScheduledWeekday(wednesday),
        isTrue,
      );
      expect(HabitSchedule.parse(2, null).intervalDays, 1);
      expect(HabitSchedule.parse(2, '0').intervalDays, 1);
      expect(HabitSchedule.parse(1, '[0, 9, 2]').weekdays, {2});
    });
  });

  group('ежедневно', () {
    const daily = HabitSchedule.daily();

    test('считает подряд идущие дни, включая сегодня', () {
      expect(streak(daily, done([0, 1, 2])), 3);
    });

    test('невыполненный сегодня день серию не обрывает', () {
      expect(streak(daily, done([1, 2])), 2);
    });

    test('пропуск обрывает серию', () {
      expect(streak(daily, done([0, 2, 3])), 1);
      expect(streak(daily, done([2, 3])), 0);
    });

    test('день засчитывается, только если цель достигнута', () {
      final totals = {
        daysAgo(0): 8,
        daysAgo(1): 5, // цель 8 не достигнута
        daysAgo(2): 10,
      };
      expect(streak(daily, totals, target: 8), 1);
      expect(streak(daily, {}, target: 8), 0);
      expect(streak(daily, {daysAgo(0): 3}, target: 8), 0);
    });
  });

  group('по дням недели', () {
    final monWedFri = HabitSchedule.weekly({1, 3, 5});

    test('незапланированные дни серию не обрывают', () {
      // Ср(0), Пн(2), Пт(5), Ср(7): вт, чт, сб, вс пропущены законно.
      expect(streak(monWedFri, done([0, 2, 5, 7])), 4);
    });

    test('пропуск запланированного дня обрывает серию', () {
      // Пн (2 дня назад) пропущен.
      expect(streak(monWedFri, done([0, 5, 7])), 1);
    });

    test('сегодня запланировано, но ещё не выполнено', () {
      expect(streak(monWedFri, done([2, 5])), 2);
    });

    test('выполнение в незапланированный день тоже засчитывается', () {
      // Вт (1 день назад) — бонус, Пн(2) — по плану.
      expect(streak(monWedFri, done([0, 1, 2])), 3);
    });
  });

  group('интервал', () {
    final everyThird = HabitSchedule.interval(3);

    test('пропуски короче интервала серию не обрывают', () {
      expect(streak(everyThird, done([0, 3, 6, 8])), 4);
    });

    test('интервал истёк без выполнения — серия обрывается', () {
      // Между 3 и 7 — три пропущенных дня подряд (4, 5, 6).
      expect(streak(everyThird, done([0, 3, 7])), 2);
    });

    test('срок ещё не вышел: серия сохраняется', () {
      expect(streak(everyThird, done([2, 5])), 2);
      // Выполнено 3 дня назад — сегодня срок, день ещё не закончился.
      expect(streak(everyThird, done([3, 6])), 2);
      // 4 дня назад — интервал уже пропущен.
      expect(streak(everyThird, done([4, 7])), 0);
    });

    test('интервал 1 работает как «ежедневно»', () {
      expect(streak(HabitSchedule.interval(1), done([0, 1, 3])), 2);
    });
  });

  test('календарная арифметика не сбивается на переходе времени и месяцев', () {
    // 29.03.2026 и 25.10.2026 — переводы часов в Европе; 1 марта — смена
    // месяца в невисокосном году.
    for (final today in [
      DateTime(2026, 3, 30),
      DateTime(2026, 10, 26),
      DateTime(2026, 3, 2),
    ]) {
      final totals = {
        for (var i = 0; i < 5; i++)
          DateTime(today.year, today.month, today.day - i, 23, 30): 1,
      };
      expect(
        streak(const HabitSchedule.daily(), totals, today: today),
        5,
        reason: '$today',
      );
    }
    expect(previousDay(DateTime(2026, 3, 1)), DateTime(2026, 2, 28));
    expect(previousDay(DateTime(2026, 10, 26)), DateTime(2026, 10, 25));
  });

  group('провайдер и форма', () {
    late AppDatabase db;
    late ProviderContainer container;
    late HabitsRepository repo;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
      );
      repo = container.read(habitsRepositoryProvider);
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    test('серия провайдера учитывает расписание и цель', () async {
      final today = DateTime.now();
      final todayDay = DateTime(today.year, today.month, today.day);
      // Сегодня и позавчера — по плану, вчера — выходной.
      final scheduled = {
        todayDay.weekday,
        DateTime(today.year, today.month, today.day - 2).weekday,
      };
      await repo.createHabit(
        title: 'Бег',
        frequencyType: HabitFrequencyType.weekly,
        frequencyValue: HabitSchedule.weekly(scheduled).encode(),
        targetValue: 2,
      );
      final habit = (await db.select(db.habits).get()).single;
      for (final ago in [0, 2]) {
        await repo.toggleHabitCheckIn(
          habitId: habit.id,
          date: DateTime(today.year, today.month, today.day - ago, 12),
          targetValue: 2,
        );
      }

      final sub = container.listen(habitsWithStatusProvider, (_, _) {});
      addTearDown(sub.close);
      await container.read(rawHabitsStreamProvider.future);
      await container.read(rawHabitLogsStreamProvider.future);
      final status = sub.read().value!.single;
      expect(status.isCompletedToday, isTrue);
      expect(status.streakCount, 2);
    });

    testWidgets('форма сохраняет выбранные дни недели', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.darkLauncherTheme,
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => const AddHabitDialog(),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('habit_title')), 'Йога');
      await tester.tap(find.text(HabitFrequencyType.daily.label));
      await tester.pumpAndSettle();
      await tester.tap(find.text(HabitFrequencyType.weekly.label).last);
      await tester.pumpAndSettle();

      // По умолчанию отмечены все дни: оставляем Пн, Ср, Пт.
      for (final day in [2, 4, 6, 7]) {
        await tester.tap(find.byKey(ValueKey('habit_weekday_$day')));
        await tester.pump();
      }
      await tester.tap(find.byKey(const ValueKey('habit_submit')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pumpAndSettle();

      final habit = (await tester.runAsync(
        () => db.select(db.habits).getSingle(),
      ))!;
      expect(habit.frequencyType, HabitFrequencyType.weekly.value);
      expect(habit.frequencyValue, '[1,3,5]');
    });
  });
}
