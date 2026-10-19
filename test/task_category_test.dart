import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_organizer/core/database/app_database.dart';
import 'package:home_organizer/core/database/database_provider.dart';
import 'package:home_organizer/features/tasks/data/repositories/tasks_repository.dart';
import 'package:home_organizer/features/tasks/domain/task_category.dart';
import 'package:home_organizer/features/tasks/domain/task_priority.dart';
import 'package:home_organizer/features/tasks/presentation/providers/tasks_provider.dart';

void main() {
  group('TaskCategory', () {
    test('id уникальны, у каждой категории есть название, иконка и цвет', () {
      expect(
        TaskCategory.values.map((c) => c.id).toSet().length,
        TaskCategory.values.length,
      );
      expect(
        TaskCategory.values.map((c) => c.label),
        ['Работа', 'Личное', 'Дом / Быт', 'Здоровье', 'Финансы', 'Прочее'],
      );
      for (final c in TaskCategory.values) {
        expect(c.icon, isA<IconData>());
        expect(c.color, isA<Color>());
        expect(TaskCategory.fromId(c.id), c);
      }
    });

    test('fromId: null и неизвестный id → «Прочее»', () {
      expect(TaskCategory.fromId(null), TaskCategory.other);
      expect(TaskCategory.fromId('nope'), TaskCategory.other);
    });
  });

  group('репозиторий', () {
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

    test('таблица categories заполняется предустановленными категориями',
        () async {
      final rows = await db.select(db.categories).get();
      expect(
        rows.map((r) => r.id).toSet(),
        TaskCategory.values.map((c) => c.id).toSet(),
      );
    });

    test('createTask сохраняет категорию; по умолчанию — «Прочее»', () async {
      final repo = container.read(tasksRepositoryProvider);
      await repo.createTask(title: 'default');
      await repo.createTask(title: 'work', category: TaskCategory.work);

      final tasks = await repo.getTasks();
      final byTitle = {for (final t in tasks) t.title: t};
      expect(byTitle['default']!.categoryId, TaskCategory.other.id);
      expect(byTitle['work']!.categoryId, TaskCategory.work.id);
    });

    test('updateTask меняет категорию', () async {
      final repo = container.read(tasksRepositoryProvider);
      await repo.createTask(title: 'T', category: TaskCategory.work);
      final before = (await repo.getTasks()).single;

      await repo.updateTask(
        id: before.id,
        title: 'T',
        priority: TaskPriority.medium,
        category: TaskCategory.health,
      );

      final after = (await repo.getTasks()).single;
      expect(after.categoryId, TaskCategory.health.id);
    });

    test('фильтр по категории в filteredTasksProvider', () async {
      final repo = container.read(tasksRepositoryProvider);
      await repo.createTask(title: 'w', category: TaskCategory.work);
      await repo.createTask(title: 'h', category: TaskCategory.health);

      final sub = container.listen(filteredTasksProvider, (_, _) {});
      addTearDown(sub.close);
      await container.read(rawTasksStreamProvider.future);

      container
          .read(taskCategoryFilterProvider.notifier)
          .setFilter(TaskCategory.health);
      final filtered = container.read(filteredTasksProvider).requireValue;
      expect(filtered.map((t) => t.title), ['h']);
    });
  });

  test('миграция v2 → v3: is_chore → категория «Дом / Быт»', () async {
    final db = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (raw) {
          raw.execute('''
            CREATE TABLE categories (
              id TEXT NOT NULL PRIMARY KEY,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL,
              deleted_at INTEGER NULL,
              name TEXT NOT NULL,
              color TEXT NULL,
              icon TEXT NULL
            )''');
          raw.execute('''
            CREATE TABLE tasks (
              id TEXT NOT NULL PRIMARY KEY,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL,
              deleted_at INTEGER NULL,
              title TEXT NOT NULL,
              description TEXT NULL,
              due_date INTEGER NULL,
              priority INTEGER NOT NULL DEFAULT 1,
              status INTEGER NOT NULL DEFAULT 0,
              is_chore INTEGER NOT NULL DEFAULT 0 CHECK (is_chore IN (0, 1)),
              recurrence_rule TEXT NULL,
              category_id TEXT NULL REFERENCES categories (id),
              parent_id TEXT NULL REFERENCES tasks (id)
            )''');
          raw.execute(
            "INSERT INTO tasks (id, created_at, updated_at, title, is_chore) "
            "VALUES ('chore', 0, 0, 'Chore', 1), ('plain', 0, 0, 'Plain', 0)",
          );
          raw.execute('PRAGMA user_version = 2');
        },
      ),
    );
    addTearDown(db.close);

    final tasks = await db.select(db.tasks).get();
    final byId = {for (final t in tasks) t.id: t};
    expect(byId['chore']!.categoryId, TaskCategory.home.id);
    expect(byId['plain']!.categoryId, isNull);

    final cats = await db.select(db.categories).get();
    expect(cats.length, TaskCategory.values.length);

    final columns = await db.customSelect(
      'SELECT name FROM pragma_table_info(?)',
      variables: [Variable.withString('tasks')],
    ).get();
    expect(
      columns.map((r) => r.read<String>('name')),
      isNot(contains('is_chore')),
    );
  });
}
