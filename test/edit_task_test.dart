import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_organizer/core/database/app_database.dart';
import 'package:home_organizer/core/database/database_provider.dart';
import 'package:home_organizer/core/theme/app_theme.dart';
import 'package:home_organizer/features/overview/presentation/providers/dashboard_tasks_provider.dart';
import 'package:home_organizer/features/overview/presentation/providers/life_score_provider.dart';
import 'package:home_organizer/features/overview/presentation/screens/overview_screen.dart';
import 'package:home_organizer/features/tasks/data/repositories/tasks_repository.dart';
import 'package:home_organizer/features/tasks/domain/task_category.dart';
import 'package:home_organizer/features/tasks/domain/task_priority.dart';
import 'package:home_organizer/features/tasks/domain/task_status.dart';

void main() {
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

  test('updateTask меняет поля, не трогает статус и обновляет updatedAt',
      () async {
    final repo = container.read(tasksRepositoryProvider);
    await repo.createTask(title: 'Old', priority: TaskPriority.low);
    final before = (await repo.getTasks()).single;
    await repo.updateTask(
      id: before.id,
      title: 'New',
      description: 'Desc',
      dueDate: DateTime(2030, 1, 2),
      priority: TaskPriority.urgent,
      category: TaskCategory.finance,
    );

    final after = (await repo.getTasks()).single;
    expect(after.title, 'New');
    expect(after.description, 'Desc');
    expect(after.dueDate, DateTime(2030, 1, 2));
    expect(after.priority, TaskPriority.urgent.value);
    expect(after.categoryId, TaskCategory.finance.id);
    expect(after.status, TaskStatus.todo.value);
    expect(after.createdAt, before.createdAt);
    expect(after.updatedAt.isBefore(before.updatedAt), isFalse);
  });

  test('updateTask реактивно обновляет todayTasksStream и dashboard', () async {
    final repo = container.read(tasksRepositoryProvider);
    await repo.createTask(title: 'Task', priority: TaskPriority.low);
    final task = (await repo.getTasks()).single;

    final sub = container.listen(dashboardTasksProvider, (_, _) {});
    addTearDown(sub.close);
    await container.read(todayTasksStreamProvider.future);

    await repo.updateTask(
      id: task.id,
      title: 'Renamed',
      priority: TaskPriority.high,
      category: TaskCategory.other,
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final today = container.read(todayTasksStreamProvider).requireValue;
    expect(today.single.title, 'Renamed');
    expect(today.single.priority, TaskPriority.high.value);
    final dashboard = container.read(dashboardTasksProvider).requireValue;
    expect(dashboard.single.title, 'Renamed');
  });

  testWidgets('форма редактирования открывается с дашборда и сохраняет',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repo = container.read(tasksRepositoryProvider);
    await tester.runAsync(() async {
      await repo.createTask(
        title: 'Buy milk',
        description: 'Two liters',
        priority: TaskPriority.high,
      );
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

    Future<void> settle() async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));
    }

    try {
      await settle();
      final task = (await tester.runAsync(repo.getTasks))!.single;

      await tester.tap(find.byKey(ValueKey('dashboard-task-edit-${task.id}')));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Редактировать задачу'), findsOneWidget);
      expect(find.text('Buy milk'), findsWidgets);
      expect(find.text('Two liters'), findsOneWidget);
      expect(find.text('Сохранить изменения'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Buy milk'),
        'Buy bread',
      );
      await tester.tap(find.text('Сохранить изменения'));
      await tester.pump(const Duration(milliseconds: 400));
      await settle();

      final updated = (await tester.runAsync(repo.getTasks))!.single;
      expect(updated.title, 'Buy bread');
      expect(updated.description, 'Two liters');
      expect(updated.priority, TaskPriority.high.value);
      expect(find.text('Buy bread'), findsOneWidget);
      expect(container.read(lifeScoreProvider).hasValue, isTrue);

      // Тап по тексту тоже открывает форму.
      await tester.tap(
        find.byKey(ValueKey('dashboard-task-edit-area-${task.id}')),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Редактировать задачу'), findsOneWidget);
      await tester.tap(find.text('Отмена'));
      await tester.pump(const Duration(milliseconds: 400));
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 50));
    }
  });
}
