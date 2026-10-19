import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_organizer/core/database/app_database.dart';
import 'package:home_organizer/core/database/database_provider.dart';
import 'package:home_organizer/features/habits/presentation/providers/habits_provider.dart';
import 'package:home_organizer/features/overview/domain/life_score.dart';
import 'package:home_organizer/features/overview/presentation/providers/life_score_provider.dart';
import 'package:home_organizer/features/settings/domain/app_module.dart';
import 'package:home_organizer/features/settings/presentation/providers/settings_provider.dart';
import 'package:home_organizer/features/tasks/data/repositories/tasks_repository.dart';
import 'package:home_organizer/features/tasks/presentation/providers/tasks_provider.dart';

void main() {
  group('LifeScore.calculate', () {
    test('полная формула 60/30/10', () {
      final s = LifeScore.calculate(
        taskRatio: 1.0,
        habitRatio: 0.5,
        streakRatio: 0.0,
      );
      // 0.6 + 0.15 + 0 = 0.75
      expect(s.score, 75);
    });

    test('только задачи — веса нормируются', () {
      final s = LifeScore.calculate(taskRatio: 0.5);
      expect(s.score, 50);
    });

    test('только привычки и стрики — 30/10 нормируются до 75/25', () {
      final s = LifeScore.calculate(habitRatio: 1.0, streakRatio: 0.0);
      expect(s.score, 75);
    });

    test('нет данных — балл 0 и hasData == false', () {
      final s = LifeScore.calculate();
      expect(s.score, 0);
      expect(s.hasData, isFalse);
    });

    test('значения ограничиваются диапазоном 0..100', () {
      final s = LifeScore.calculate(
        taskRatio: 5,
        habitRatio: 5,
        streakRatio: 5,
      );
      expect(s.score, 100);
    });
  });

  group('lifeScoreProvider', () {
    late AppDatabase db;
    late ProviderContainer container;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
      );
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    /// Держит провайдер живым и ждёт, пока он выйдет из загрузки.
    Future<LifeScore> readScore() async {
      final sub = container.listen(lifeScoreProvider, (_, _) {});
      addTearDown(sub.close);
      for (var i = 0; i < 50; i++) {
        final value = container.read(lifeScoreProvider);
        if (value.hasValue) return value.requireValue;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      fail('lifeScoreProvider не вышел из загрузки');
    }

    test('считает долю выполненных задач и привычек за сегодня', () async {
      final tasks = container.read(tasksControllerProvider);
      await tasks.createTask(title: 'A');
      await tasks.createTask(title: 'B');
      final all = await container.read(tasksRepositoryProvider).getTasks();
      await tasks.toggleTaskStatus(all.first);

      final habits = container.read(habitsControllerProvider);
      await habits.createHabit(title: 'H1');
      await habits.createHabit(title: 'H2');
      final habitList = await db.select(db.habits).get();
      await habits.toggleHabitToday(habitList.first);

      final score = await _waitFor(
        readScore,
        (s) => s.taskRatio == 0.5 && s.habitRatio == 0.5,
      );

      expect(score.taskRatio, 0.5);
      expect(score.habitRatio, 0.5);
      expect(score.streakRatio, isNotNull);
      expect(score.score, inInclusiveRange(1, 99));
    });

    test('отключённый модуль задач исключается из формулы', () async {
      await container.read(tasksControllerProvider).createTask(title: 'A');
      await container
          .read(settingsControllerProvider)
          .setModuleEnabled(AppModule.tasks, false);

      final habits = container.read(habitsControllerProvider);
      await habits.createHabit(title: 'H1');
      final habitList = await db.select(db.habits).get();
      await habits.toggleHabitToday(habitList.first);

      final score = await _waitFor(
        readScore,
        (s) => s.taskRatio == null && s.habitRatio == 1.0,
      );

      expect(score.taskRatio, isNull);
      expect(score.habitRatio, 1.0);
    });

    test('отключённый модуль привычек исключается из формулы', () async {
      final tasks = container.read(tasksControllerProvider);
      await tasks.createTask(title: 'A');
      await container
          .read(settingsControllerProvider)
          .setModuleEnabled(AppModule.habits, false);

      final score = await _waitFor(
        readScore,
        (s) => s.habitRatio == null && s.taskRatio == 0.0,
      );

      expect(score.habitRatio, isNull);
      expect(score.streakRatio, isNull);
      expect(score.score, 0);
    });
  });
}

Future<LifeScore> _waitFor(
  Future<LifeScore> Function() read,
  bool Function(LifeScore) predicate,
) async {
  late LifeScore last;
  for (var i = 0; i < 50; i++) {
    last = await read();
    if (predicate(last)) return last;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail('Не дождались ожидаемого значения, последнее: ${last.score}');
}
