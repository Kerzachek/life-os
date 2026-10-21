import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_organizer/core/database/app_database.dart';
import 'package:home_organizer/core/database/database_provider.dart';
import 'package:home_organizer/core/theme/app_theme.dart';
import 'package:home_organizer/features/overview/presentation/providers/dashboard_tasks_provider.dart';
import 'package:home_organizer/features/tasks/data/repositories/tasks_repository.dart';
import 'package:home_organizer/features/tasks/domain/task_priority.dart';
import 'package:home_organizer/features/tasks/domain/task_status.dart';

TaskEntity _task(
  String id, {
  int priority = 1,
  int status = 0,
  DateTime? dueDate,
  int createdMinute = 0,
}) {
  final created = DateTime.utc(2026, 1, 1, 0, createdMinute);
  return TaskEntity(
    id: id,
    createdAt: created,
    updatedAt: created,
    title: id,
    dueDate: dueDate,
    priority: priority,
    status: status,
    isReminderSent: false,
  );
}

void main() {
  group('TaskPriority', () {
    test('у каждого приоритета есть иконка и обратное преобразование', () {
      for (final p in TaskPriority.values) {
        expect(TaskPriority.fromValue(p.value), p);
        expect(p.icon, isA<IconData>());
      }
      expect(TaskPriority.fromValue(42), TaskPriority.medium);
    });

    test('высокий приоритет — тёплый акцент, низкий — приглушённый', () {
      expect(TaskPriority.low.color, const Color(0xFF8B949E));
      expect(TaskPriority.medium.color, AppTheme.primaryAccent);
      expect(TaskPriority.high.color, const Color(0xFFFF9F43));
      expect(TaskPriority.urgent.color, const Color(0xFFFF4757));
    });
  });

  group('sortTasksForDashboard', () {
    test('высокий приоритет выше остальных', () {
      final sorted = sortTasksForDashboard([
        _task('low', priority: 0),
        _task('high', priority: 2),
        _task('urgent', priority: 3),
        _task('medium', priority: 1),
      ]);
      expect(sorted.map((t) => t.id), ['urgent', 'high', 'medium', 'low']);
    });

    test('выполненные задачи уходят вниз независимо от приоритета', () {
      final sorted = sortTasksForDashboard([
        _task('done-urgent', priority: 3, status: TaskStatus.completed.value),
        _task('active-low', priority: 0),
      ]);
      expect(sorted.map((t) => t.id), ['active-low', 'done-urgent']);
    });

    test('при равном приоритете — по сроку, задачи без срока в конце', () {
      final sorted = sortTasksForDashboard([
        _task('no-due', createdMinute: 1),
        _task('later', dueDate: DateTime(2026, 1, 5), createdMinute: 2),
        _task('sooner', dueDate: DateTime(2026, 1, 2), createdMinute: 3),
      ]);
      expect(sorted.map((t) => t.id), ['sooner', 'later', 'no-due']);
    });
  });

  test('dashboardTasksProvider отдаёт задачи, отсортированные по приоритету',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
    });

    final repo = container.read(tasksRepositoryProvider);
    await repo.createTask(title: 'low', priority: TaskPriority.low);
    await repo.createTask(title: 'urgent', priority: TaskPriority.urgent);
    await repo.createTask(title: 'high', priority: TaskPriority.high);

    final sub = container.listen(dashboardTasksProvider, (_, _) {});
    addTearDown(sub.close);

    List<TaskEntity>? tasks;
    for (var i = 0; i < 50 && tasks == null; i++) {
      tasks = container.read(dashboardTasksProvider).value;
      if (tasks == null) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }

    expect(tasks, isNotNull);
    expect(tasks!.map((t) => t.title), ['urgent', 'high', 'low']);
  });
}
