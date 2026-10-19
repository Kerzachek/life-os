import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_organizer/core/database/app_database.dart';
import 'package:home_organizer/core/database/database_provider.dart';
import 'package:home_organizer/core/theme/app_theme.dart';
import 'package:home_organizer/features/overview/presentation/widgets/dashboard_task_tile.dart';
import 'package:home_organizer/features/tasks/data/repositories/tasks_repository.dart';
import 'package:home_organizer/features/tasks/domain/task_category.dart';
import 'package:home_organizer/features/tasks/presentation/screens/tasks_screen.dart';
import 'package:home_organizer/features/tasks/presentation/widgets/add_task_dialog.dart';
import 'package:home_organizer/features/tasks/presentation/widgets/task_item_widget.dart';

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

  Widget app(Widget home) => UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.darkLauncherTheme,
          home: Scaffold(body: home),
        ),
      );

  Future<void> pickCategory(WidgetTester tester, String label) async {
    await tester.tap(find.byKey(const ValueKey('task-category-dropdown')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text(label).last);
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> waitForDb(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
  }

  testWidgets('форма создания: выбор категории сохраняется', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = container.read(tasksRepositoryProvider);

    await tester.pumpWidget(app(const AddTaskDialog()));
    await tester.pump(const Duration(milliseconds: 300));

    // Чекбокса «Бытовое дело» больше нет.
    expect(find.byType(SwitchListTile), findsNothing);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Название *'),
      'Pay bills',
    );
    await pickCategory(tester, 'Финансы');

    await tester.tap(find.text('Создать'));
    await waitForDb(tester);

    final saved = (await tester.runAsync(repo.getTasks))!.single;
    expect(saved.title, 'Pay bills');
    expect(saved.categoryId, TaskCategory.finance.id);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('форма редактирования предзаполняет категорию и меняет её',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = container.read(tasksRepositoryProvider);
    await tester.runAsync(
      () => repo.createTask(title: 'Run', category: TaskCategory.health),
    );
    final task = (await tester.runAsync(repo.getTasks))!.single;

    await tester.pumpWidget(app(AddTaskDialog(taskToEdit: task)));
    await tester.pump(const Duration(milliseconds: 300));

    final dropdown = tester.widget<DropdownButtonFormField<TaskCategory>>(
      find.byKey(const ValueKey('task-category-dropdown')),
    );
    expect(dropdown.initialValue, TaskCategory.health);
    expect(find.text('Здоровье'), findsOneWidget);

    await pickCategory(tester, 'Работа');
    await tester.tap(find.text('Сохранить изменения'));
    await waitForDb(tester);

    final updated = (await tester.runAsync(repo.getTasks))!.single;
    expect(updated.categoryId, TaskCategory.work.id);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('TaskItemWidget и DashboardTaskTile показывают категорию',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = container.read(tasksRepositoryProvider);
    await tester.runAsync(
      () => repo.createTask(title: 'Clean', category: TaskCategory.home),
    );
    final task = (await tester.runAsync(repo.getTasks))!.single;

    await tester.pumpWidget(
      app(Column(children: [
        TaskItemWidget(task: task),
        DashboardTaskTile(task: task),
      ])),
    );
    await tester.pump();

    expect(find.byKey(ValueKey('task-category-${task.id}')), findsOneWidget);
    expect(find.text('Дом / Быт'), findsOneWidget);
    expect(
      find.byKey(ValueKey('dashboard-task-category-${task.id}')),
      findsOneWidget,
    );
    expect(find.byIcon(TaskCategory.home.icon), findsNWidgets(2));
  });

  testWidgets('фильтры категорий на экране задач — только иконки',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = container.read(tasksRepositoryProvider);
    await tester.runAsync(() async {
      await repo.createTask(title: 'Job', category: TaskCategory.work);
      await repo.createTask(title: 'Pill', category: TaskCategory.health);
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.darkLauncherTheme,
          home: const TasksScreen(),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pump();

    // Названий категорий в панели фильтров нет, есть иконки.
    for (final c in TaskCategory.values) {
      expect(
        find.byKey(ValueKey('task-category-filter-${c.id}')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(ValueKey('task-category-filter-${c.id}')),
          matching: find.text(c.label),
        ),
        findsNothing,
      );
    }
    // Название доступно как подсказка.
    expect(find.byTooltip('Здоровье'), findsOneWidget);
    expect(find.text('Job'), findsOneWidget);
    expect(find.text('Pill'), findsOneWidget);

    await tester.tap(
      find.byKey(ValueKey('task-category-filter-${TaskCategory.health.id}')),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Job'), findsNothing);
    expect(find.text('Pill'), findsOneWidget);

    // Повторный тап снимает фильтр.
    await tester.tap(
      find.byKey(ValueKey('task-category-filter-${TaskCategory.health.id}')),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Job'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('задача без категории (categoryId == null) — без бейджа',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = container.read(tasksRepositoryProvider);
    await tester.runAsync(() => repo.createTask(title: 'Legacy'));
    final created = (await tester.runAsync(repo.getTasks))!.single;
    // Имитируем старую задачу без категории.
    final task = created.copyWith(categoryId: const Value(null));

    await tester.pumpWidget(
      app(Column(children: [
        TaskItemWidget(task: task),
        DashboardTaskTile(task: task),
      ])),
    );
    await tester.pump();

    expect(find.byKey(ValueKey('task-category-${task.id}')), findsNothing);
    expect(
      find.byKey(ValueKey('dashboard-task-category-${task.id}')),
      findsNothing,
    );
    expect(find.text('Прочее'), findsNothing);
  });
}
