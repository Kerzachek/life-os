import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_organizer/core/database/app_database.dart';
import 'package:home_organizer/core/database/database_provider.dart';
import 'package:home_organizer/core/theme/app_theme.dart';
import 'package:home_organizer/features/tasks/data/repositories/tasks_repository.dart';
import 'package:home_organizer/features/tasks/domain/task_recurrence.dart';
import 'package:home_organizer/features/tasks/domain/task_status.dart';
import 'package:home_organizer/features/tasks/presentation/providers/tasks_provider.dart';
import 'package:home_organizer/features/tasks/presentation/widgets/add_task_dialog.dart';
import 'package:home_organizer/features/tasks/presentation/widgets/task_item_widget.dart';

void main() {
  group('правило повторения', () {
    test('кодируется и разбирается', () {
      final weekly = TaskRecurrence(
        RecurrenceFrequency.weekly,
        weekdays: {5, 1, 3},
      );
      expect(weekly.encode(), 'weekly:1,3,5');
      expect(TaskRecurrence.parse('weekly:1,3,5'), weekly);
      expect(
        TaskRecurrence.parse('daily')!.frequency,
        RecurrenceFrequency.daily,
      );
      expect(TaskRecurrence.parse(null), isNull);
      expect(TaskRecurrence.parse(''), isNull);
      expect(TaskRecurrence.parse('hourly'), isNull);
      // Дни недели имеют смысл только для еженедельного правила.
      expect(
        TaskRecurrence(RecurrenceFrequency.daily, weekdays: {1}).encode(),
        'daily',
      );
      expect(weekly.label, 'Каждую неделю (пн, ср, пт)');
    });

    test('ежедневное и ежегодное сохраняют время суток', () {
      final daily = TaskRecurrence(RecurrenceFrequency.daily);
      expect(
        daily.nextAfter(DateTime(2026, 12, 31, 18, 30)),
        DateTime(2027, 1, 1, 18, 30),
      );
      final yearly = TaskRecurrence(RecurrenceFrequency.yearly);
      expect(yearly.nextAfter(DateTime(2026, 3, 8)), DateTime(2027, 3, 8));
      // 29 февраля в невисокосный год — 28-е.
      expect(yearly.nextAfter(DateTime(2028, 2, 29)), DateTime(2029, 2, 28));
    });

    test('еженедельное — ближайший выбранный день', () {
      // 2026-10-26 — понедельник.
      final rule = TaskRecurrence(
        RecurrenceFrequency.weekly,
        weekdays: {DateTime.monday, DateTime.thursday},
      );
      expect(rule.nextAfter(DateTime(2026, 10, 26)), DateTime(2026, 10, 29));
      expect(rule.nextAfter(DateTime(2026, 10, 29)), DateTime(2026, 11, 2));
      // Без дней — через неделю.
      expect(
        TaskRecurrence(RecurrenceFrequency.weekly)
            .nextAfter(DateTime(2026, 10, 26)),
        DateTime(2026, 11, 2),
      );
    });

    test('ежемесячное ограничивается концом месяца', () {
      final rule = TaskRecurrence(RecurrenceFrequency.monthly);
      expect(rule.nextAfter(DateTime(2026, 1, 31)), DateTime(2026, 2, 28));
      expect(rule.nextAfter(DateTime(2026, 12, 15)), DateTime(2027, 1, 15));
    });

    test('просроченная задача не порождает прошлые экземпляры', () {
      final rule = TaskRecurrence(RecurrenceFrequency.daily);
      final now = DateTime(2026, 10, 24, 15);
      expect(
        rule.nextDueDate(DateTime(2026, 10, 20), now),
        DateTime(2026, 10, 24),
      );
      expect(
        rule.nextDueDate(DateTime(2026, 10, 24), now),
        DateTime(2026, 10, 25),
      );
      // Без срока — от сегодняшнего дня.
      expect(rule.nextDueDate(null, now), DateTime(2026, 10, 25));
    });
  });

  group('хранение', () {
    late AppDatabase db;
    late TasksRepository repo;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = TasksRepository(db);
    });
    tearDown(() => db.close());

    Future<List<TaskEntity>> all() => db.select(db.tasks).get();
    Future<TaskEntity> byTitle(String title) async =>
        (await repo.getTasks()).firstWhere((t) => t.title == title);

    test(
      'завершение повторяющейся задачи создаёт следующий экземпляр',
      () async {
        final now = DateTime(2026, 10, 24, 12);
        await repo.createTask(
          title: 'Полить цветы',
          dueDate: DateTime(2026, 10, 24),
          reminderAt: DateTime(2026, 10, 23, 9),
          recurrence: TaskRecurrence(
            RecurrenceFrequency.weekly,
            weekdays: {DateTime.saturday, DateTime.wednesday},
          ),
        );
        final task = await byTitle('Полить цветы');
        await repo.addSubtask(task.id, 'Кухня');
        final subtask = (await repo.getSubtasks(task.id)).single;
        await repo.toggleTaskStatus(subtask);

        await repo.toggleTaskStatus(task, now: now);

        final tasks = await repo.getTasks();
        final done = tasks.singleWhere((t) => t.id == task.id);
        expect(done.status, TaskStatus.completed.value);

        final next = tasks.singleWhere(
          (t) => t.parentId == null && t.id != task.id,
        );
        expect(next.status, TaskStatus.todo.value);
        expect(next.recurrenceRule, 'weekly:3,6');
        // 24.10 — суббота, ближайшая среда — 28.10.
        expect(next.dueDate, DateTime(2026, 10, 28));
        // Напоминание сдвигается вместе со сроком и снова взведено.
        expect(next.reminderAt, DateTime(2026, 10, 27, 9));
        expect(next.isReminderSent, isFalse);

        // Подзадачи копируются невыполненными.
        final copied = (await repo.getSubtasks(next.id)).single;
        expect(copied.title, 'Кухня');
        expect(copied.status, TaskStatus.todo.value);
        expect(
          (await repo.getSubtasks(task.id)).single.status,
          TaskStatus.completed.value,
        );
      },
    );

    test('повторное завершение не дублирует следующий экземпляр', () async {
      final now = DateTime(2026, 10, 24, 12);
      await repo.createTask(
        title: 'Зарядка',
        dueDate: DateTime(2026, 10, 24),
        recurrence: TaskRecurrence(RecurrenceFrequency.daily),
      );
      var task = await byTitle('Зарядка');
      await repo.toggleTaskStatus(task, now: now);
      task = (await all()).singleWhere((t) => t.id == task.id);
      await repo.toggleTaskStatus(task, now: now); // снять отметку
      task = (await all()).singleWhere((t) => t.id == task.id);
      expect(task.status, TaskStatus.todo.value);
      await repo.toggleTaskStatus(task, now: now);

      final tasks = await repo.getTasks();
      expect(tasks, hasLength(2));
      expect(
        tasks.where((t) => t.dueDate == DateTime(2026, 10, 25)),
        hasLength(1),
      );
    });

    test('обычная задача и подзадача не повторяются', () async {
      await repo.createTask(title: 'Разовая', dueDate: DateTime(2026, 10, 24));
      await repo.toggleTaskStatus(await byTitle('Разовая'));
      expect(await repo.getTasks(), hasLength(1));
    });

    test('updateTask меняет и снимает правило повторения', () async {
      await repo.createTask(title: 'T');
      final task = await byTitle('T');
      Future<void> update(TaskRecurrence? recurrence) => repo.updateTask(
        id: task.id,
        title: 'T',
        priority: .medium,
        category: .other,
        recurrence: recurrence,
      );
      await update(TaskRecurrence(RecurrenceFrequency.monthly));
      expect((await byTitle('T')).recurrenceRule, 'monthly');
      await update(null);
      expect((await byTitle('T')).recurrenceRule, isNull);
    });

    test('подзадача наследует категорию и приоритет родителя', () async {
      await repo.createTask(
        title: 'Ремонт',
        priority: .urgent,
        category: .home,
      );
      final parent = await byTitle('Ремонт');
      await repo.addSubtask(parent.id, 'Купить краску');
      final sub = (await repo.getSubtasks(parent.id)).single;
      expect(sub.parentId, parent.id);
      expect(sub.priority, parent.priority);
      expect(sub.categoryId, parent.categoryId);
      // Подзадача к несуществующей задаче не создаётся.
      await repo.addSubtask('missing', 'X');
      expect(await all(), hasLength(2));
    });

    test('удаление родителя каскадно удаляет подзадачи', () async {
      await repo.createTask(title: 'Родитель');
      await repo.createTask(title: 'Другая');
      final parent = await byTitle('Родитель');
      final other = await byTitle('Другая');
      await repo.addSubtask(parent.id, 'A');
      await repo.addSubtask(parent.id, 'B');
      await repo.addSubtask(other.id, 'C');

      await repo.deleteTask(parent.id);

      final rows = await all();
      final deleted = rows.where((t) => t.deletedAt != null).toList();
      expect(
        deleted.map((t) => t.title),
        unorderedEquals(['Родитель', 'A', 'B']),
      );
      // Удаление — мягкое: строки остаются для синхронизации.
      expect(rows, hasLength(5));
      expect(await repo.getSubtasks(parent.id), isEmpty);
      expect((await repo.getSubtasks(other.id)).single.title, 'C');
    });

    test('удаление подзадачи не трогает родителя', () async {
      await repo.createTask(title: 'Родитель');
      final parent = await byTitle('Родитель');
      await repo.addSubtask(parent.id, 'A');
      await repo.deleteTask((await repo.getSubtasks(parent.id)).single.id);
      expect((await byTitle('Родитель')).deletedAt, isNull);
    });

    test('подзадачи не попадают в задачи на сегодня', () async {
      await repo.createTask(title: 'Родитель');
      await repo.addSubtask((await byTitle('Родитель')).id, 'A');
      final today = await repo.watchTodayTasks().first;
      expect(today.map((t) => t.title), ['Родитель']);
    });
  });

  group('провайдеры и UI', () {
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

    Future<void> waitForDb(WidgetTester tester) async {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }

    test(
      'список задач скрывает подзадачи, subtasksProvider их отдаёт',
      () async {
        final repo = container.read(tasksRepositoryProvider);
        await repo.createTask(title: 'Родитель');
        final parent = (await repo.getTasks()).single;
        await repo.addSubtask(parent.id, 'A');
        await repo.addSubtask(parent.id, 'B');

        final sub = container.listen(filteredTasksProvider, (_, _) {});
        addTearDown(sub.close);
        await container.read(rawTasksStreamProvider.future);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(
          container.read(filteredTasksProvider).requireValue.single.id,
          parent.id,
        );
        expect(
          container.read(subtasksProvider(parent.id)).map((t) => t.title),
          ['A', 'B'],
        );
      },
    );

    testWidgets('форма создания сохраняет еженедельное правило', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repo = container.read(tasksRepositoryProvider);

      await tester.pumpWidget(app(const AddTaskDialog()));
      await tester.pump(const Duration(milliseconds: 300));

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Название *'),
        'Йога',
      );
      await tester.tap(find.byKey(const ValueKey('task-recurrence-field')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Каждую неделю').last);
      await tester.pump(const Duration(milliseconds: 400));

      // По умолчанию выбран сегодняшний день недели; добавим ещё один.
      final today = DateTime.now().weekday;
      final extra = today == 7 ? 1 : today + 1;
      await tester.tap(find.byKey(ValueKey('task-recurrence-day-$extra')));
      await tester.pump();

      await tester.tap(find.text('Создать'));
      await waitForDb(tester);

      final saved = (await tester.runAsync(repo.getTasks))!.single;
      expect(
        TaskRecurrence.parse(saved.recurrenceRule),
        TaskRecurrence(RecurrenceFrequency.weekly, weekdays: {today, extra}),
      );

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('карточка: бейдж повтора, прогресс подзадач, добавление и '
        'предложение закрыть родителя', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repo = container.read(tasksRepositoryProvider);
      await tester.runAsync(() async {
        await repo.createTask(
          title: 'Уборка',
          recurrence: TaskRecurrence(RecurrenceFrequency.daily),
        );
        final parent = (await repo.getTasks()).single;
        await repo.addSubtask(parent.id, 'Пол');
        await repo.addSubtask(parent.id, 'Окна');
        await repo.toggleTaskStatus((await repo.getSubtasks(parent.id)).first);
      });
      final parent = (await tester.runAsync(repo.getTasks))!
          .firstWhere((t) => t.parentId == null);

      await tester.pumpWidget(
        app(
          Consumer(
            builder: (context, ref, _) {
              final task = ref
                  .watch(rawTasksStreamProvider)
                  .value
                  ?.firstWhere((t) => t.id == parent.id);
              return task == null
                  ? const SizedBox()
                  : TaskItemWidget(task: task);
            },
          ),
        ),
      );
      await waitForDb(tester);

      expect(
        find.byKey(ValueKey('task-recurring-${parent.id}')),
        findsOneWidget,
      );
      expect(find.text('Подзадачи: 1/2'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('Окна'), findsNothing);

      await tester.tap(find.byKey(ValueKey('task-expand-${parent.id}')));
      await tester.pump();
      expect(find.text('Окна'), findsOneWidget);

      await tester.enterText(
        find.byKey(ValueKey('subtask-add-${parent.id}')),
        'Посуда',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await waitForDb(tester);
      expect(find.text('Подзадачи: 1/3'), findsOneWidget);

      // Отмечаем оставшиеся подзадачи — после последней предлагается
      // закрыть родителя.
      Future<void> check(String title) async {
        final row = find
            .ancestor(of: find.text(title), matching: find.byType(Row))
            .first;
        await tester.tap(
          find.descendant(of: row, matching: find.byType(Checkbox)),
        );
        await waitForDb(tester);
      }

      await check('Окна');
      expect(find.text('Все подзадачи выполнены'), findsNothing);
      await check('Посуда');
      expect(find.text('Все подзадачи выполнены'), findsOneWidget);
      await tester.tap(find.text('Завершить'));
      await waitForDb(tester);

      final tasks = (await tester.runAsync(repo.getTasks))!;
      expect(
        tasks.singleWhere((t) => t.id == parent.id).status,
        TaskStatus.completed.value,
      );
      // Родитель повторяющийся — появился следующий экземпляр.
      expect(
        tasks.where((t) => t.parentId == null && t.id != parent.id),
        hasLength(1),
      );

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
