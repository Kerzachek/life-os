import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_provider.dart';
import '../../domain/task_category.dart';
import '../../domain/task_priority.dart';
import '../../domain/task_status.dart';

final tasksRepositoryProvider = Provider<TasksRepository>((ref) {
  return TasksRepository(ref.watch(appDatabaseProvider));
});

class TasksRepository {
  final AppDatabase _db;
  final _uuid = const Uuid();

  TasksRepository(this._db);

  /// Подписка на поток всех не удаленных задач
  Stream<List<TaskEntity>> watchTasks() {
    return (_db.select(_db.tasks)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([
            (t) => OrderingTerm(expression: t.status, mode: OrderingMode.asc),
            (t) => OrderingTerm(expression: t.priority, mode: OrderingMode.desc),
            (t) => OrderingTerm(expression: t.dueDate, mode: OrderingMode.asc),
          ]))
        .watch();
  }

  /// Подписка на задачи, относящиеся к сегодняшнему дню (для Life Score).
  ///
  /// Входят неотменённые задачи без срока или со сроком не позже конца
  /// сегодняшнего дня (включая просроченные). Выполненные задачи учитываются
  /// только если были завершены сегодня.
  Stream<List<TaskEntity>> watchTodayTasks() {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    // Через календарные поля — устойчиво к переходу на летнее время.
    final startOfTomorrow = DateTime(now.year, now.month, now.day + 1);

    return (_db.select(_db.tasks)
          ..where(
            (t) =>
                t.deletedAt.isNull() &
                t.status.equals(TaskStatus.cancelled.value).not() &
                (t.dueDate.isNull() |
                    t.dueDate.isSmallerThanValue(startOfTomorrow)) &
                (t.status.equals(TaskStatus.completed.value).not() |
                    t.updatedAt.isBiggerOrEqualValue(startOfToday)),
          ))
        .watch();
  }

  /// Получение списка не удаленных задач
  Future<List<TaskEntity>> getTasks() async {
    return (_db.select(_db.tasks)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([
            (t) => OrderingTerm(expression: t.status, mode: OrderingMode.asc),
            (t) => OrderingTerm(expression: t.priority, mode: OrderingMode.desc),
            (t) => OrderingTerm(expression: t.dueDate, mode: OrderingMode.asc),
          ]))
        .get();
  }

  /// Создание новой задачи
  Future<void> createTask({
    required String title,
    String? description,
    DateTime? dueDate,
    TaskPriority priority = TaskPriority.medium,
    TaskCategory category = TaskCategory.defaultCategory,
  }) async {
    final now = DateTime.now().toUtc();
    final companion = TasksCompanion.insert(
      id: _uuid.v4(),
      createdAt: now,
      updatedAt: now,
      title: title,
      description: Value(description),
      dueDate: Value(dueDate),
      priority: Value(priority.value),
      status: Value(TaskStatus.todo.value),
      categoryId: Value(category.id),
    );
    await _db.into(_db.tasks).insert(companion);
  }

  /// Обновление полей существующей задачи (статус не меняется).
  ///
  /// Обновляет `updatedAt`, поэтому все Drift-стримы (`watchTasks`,
  /// `watchTodayTasks`) автоматически эмитят новые данные.
  Future<void> updateTask({
    required String id,
    required String title,
    String? description,
    DateTime? dueDate,
    required TaskPriority priority,
    required TaskCategory category,
  }) async {
    final now = DateTime.now().toUtc();
    await (_db.update(_db.tasks)..where((t) => t.id.equals(id))).write(
      TasksCompanion(
        title: Value(title),
        description: Value(description),
        dueDate: Value(dueDate),
        priority: Value(priority.value),
        categoryId: Value(category.id),
        updatedAt: Value(now),
      ),
    );
  }

  /// Переключение статуса задачи (выполнено / к выполнению)
  Future<void> toggleTaskStatus(TaskEntity task) async {
    final now = DateTime.now().toUtc();
    final nextStatus = task.status == TaskStatus.completed.value
        ? TaskStatus.todo.value
        : TaskStatus.completed.value;

    await (_db.update(_db.tasks)..where((t) => t.id.equals(task.id))).write(
      TasksCompanion(
        status: Value(nextStatus),
        updatedAt: Value(now),
      ),
    );
  }

  /// Обновление статуса задачи
  Future<void> updateTaskStatus(String id, TaskStatus status) async {
    final now = DateTime.now().toUtc();
    await (_db.update(_db.tasks)..where((t) => t.id.equals(id))).write(
      TasksCompanion(
        status: Value(status.value),
        updatedAt: Value(now),
      ),
    );
  }

  /// Мягкое удаление задачи (soft delete для LWW-синхронизации)
  Future<void> deleteTask(String id) async {
    final now = DateTime.now().toUtc();
    await (_db.update(_db.tasks)..where((t) => t.id.equals(id))).write(
      TasksCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  }
}
