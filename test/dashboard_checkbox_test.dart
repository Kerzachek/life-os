import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_organizer/core/database/app_database.dart';
import 'package:home_organizer/core/database/database_provider.dart';
import 'package:home_organizer/core/theme/app_theme.dart';
import 'package:home_organizer/features/overview/presentation/providers/life_score_provider.dart';
import 'package:home_organizer/features/overview/presentation/screens/overview_screen.dart';
import 'package:home_organizer/features/tasks/data/repositories/tasks_repository.dart';
import 'package:home_organizer/features/tasks/domain/task_priority.dart';
import 'package:home_organizer/features/tasks/domain/task_status.dart';
import 'package:home_organizer/features/tasks/presentation/widgets/priority_badge.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
  });

  // Выполняется всегда (в том числе при упавшем expect) и вне fake-async
  // зоны теста, поэтому db.close() реально завершается.
  tearDown(() async {
    container.dispose();
    await db.close();
  });

  testWidgets(
      'чекбокс на дашборде меняет статус в БД и пересчитывает Life Score',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repo = container.read(tasksRepositoryProvider);

    await tester.runAsync(() async {
      await repo.createTask(title: 'Low task', priority: TaskPriority.low);
      await repo.createTask(title: 'High task', priority: TaskPriority.high);
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.darkLauncherTheme,
          home: const OverviewScreen(),
        ),
      ),
    );

    // Даём Drift-стримам отдать данные и дорисовать анимации.
    // Без pumpAndSettle: ограниченное число pump() вместо ожидания «тишины».
    Future<void> settle() async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));
    }

    try {
      await _runScenario(tester, container, repo, settle);
    } finally {
      // Размонтируем дерево до dispose контейнера и закрытия БД.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 50));
    }
  });
}

Future<void> _runScenario(
  WidgetTester tester,
  ProviderContainer container,
  TasksRepository repo,
  Future<void> Function() settle,
) async {
  await settle();

  // Задача с высоким приоритетом отображается выше, бейджи на месте.
  expect(
    tester.getTopLeft(find.text('High task')).dy,
    lessThan(tester.getTopLeft(find.text('Low task')).dy),
  );
  expect(find.byType(PriorityBadge), findsNWidgets(2));
  expect(container.read(lifeScoreProvider).requireValue.taskRatio, 0.0);

  // Отмечаем верхнюю задачу (High task).
  expect(find.byType(Checkbox), findsNWidgets(2));
  await tester.tap(find.byType(Checkbox).first);
  await settle();

  final all = (await tester.runAsync(repo.getTasks))!;
  final high = all.firstWhere((t) => t.title == 'High task');
  final low = all.firstWhere((t) => t.title == 'Low task');
  expect(high.status, TaskStatus.completed.value);
  expect(low.status, TaskStatus.todo.value);

  final score = container.read(lifeScoreProvider).requireValue;
  expect(score.taskRatio, 0.5);
  expect(score.score, 50);
  expect(find.textContaining('50 / 100'), findsOneWidget);

  // Выполненная задача уходит вниз списка.
  expect(
    tester.getTopLeft(find.text('Low task')).dy,
    lessThan(tester.getTopLeft(find.text('High task')).dy),
  );

  // Повторный клик возвращает статус «активна» и обнуляет балл.
  await tester.tap(
    find.byKey(ValueKey('dashboard-task-checkbox-${high.id}')),
  );
  await settle();
  expect(container.read(lifeScoreProvider).requireValue.score, 0);
}
