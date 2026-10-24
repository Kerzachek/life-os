import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_provider.dart';
import '../../domain/task_category.dart';
import '../../domain/task_priority.dart';
import '../../domain/task_recurrence.dart';
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
  /// только если были завершены сегодня. Подзадачи не входят — их прогресс
  /// виден в карточке родителя.
  Stream<List<TaskEntity>> watchTodayTasks() {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    // Через календарные поля — устойчиво к переходу на летнее время.
    final startOfTomorrow = DateTime(now.year, now.month, now.day + 1);

    return (_db.select(_db.tasks)
          ..where(
            (t) =>
                t.deletedAt.isNull() &
                t.parentId.isNull() &
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
    DateTime? reminderAt,
    TaskPriority priority = TaskPriority.medium,
    TaskCategory category = TaskCategory.defaultCategory,
    TaskRecurrence? recurrence,
    String? parentId,
  }) async {
    final now = DateTime.now().toUtc();
    final companion = TasksCompanion.insert(
      id: _uuid.v4(),
      createdAt: now,
      updatedAt: now,
      title: title,
      description: Value(description),
      dueDate: Value(dueDate),
      reminderAt: Value(reminderAt),
      priority: Value(priority.value),
      status: Value(TaskStatus.todo.value),
      categoryId: Value(category.id),
      recurrenceRule: Value(recurrence?.encode()),
      parentId: Value(parentId),
    );
    await _db.into(_db.tasks).insert(companion);
  }

  /// Быстрое добавление подзадачи: наследует категорию и приоритет родителя.
  Future<void> addSubtask(String parentId, String title) async {
    final parent = await (_db.select(_db.tasks)
          ..where((t) => t.id.equals(parentId)))
        .getSingleOrNull();
    if (parent == null) return;
    await createTask(
      title: title,
      priority: TaskPriority.fromValue(parent.priority),
      category: TaskCategory.fromId(parent.categoryId),
      parentId: parentId,
    );
  }

  /// Неудалённые подзадачи задачи в порядке добавления.
  Future<List<TaskEntity>> getSubtasks(String parentId) {
    return (_db.select(_db.tasks)
          ..where((t) => t.parentId.equals(parentId) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm(expression: t.createdAt)]))
        .get();
  }

  /// Обновление полей существующей задачи (статус не меняется).
  ///
  /// Обновляет `updatedAt`, поэтому все Drift-стримы (`watchTasks`,
  /// `watchTodayTasks`) автоматически эмитят новые данные.
  /// Изменённое время напоминания снова «взводит» его (`isReminderSent`).
  Future<void> updateTask({
    required String id,
    required String title,
    String? description,
    DateTime? dueDate,
    DateTime? reminderAt,
    required TaskPriority priority,
    required TaskCategory category,
    TaskRecurrence? recurrence,
  }) async {
    final now = DateTime.now().toUtc();
    await _db.transaction(() async {
      final current = await (_db.select(_db.tasks)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      final reminderChanged = current == null ||
          !_sameMoment(current.reminderAt, reminderAt);
      await (_db.update(_db.tasks)..where((t) => t.id.equals(id))).write(
        TasksCompanion(
          title: Value(title),
          description: Value(description),
          dueDate: Value(dueDate),
          reminderAt: Value(reminderAt),
          isReminderSent:
              reminderChanged ? const Value(false) : const Value.absent(),
          priority: Value(priority.value),
          categoryId: Value(category.id),
          recurrenceRule: Value(recurrence?.encode()),
          updatedAt: Value(now),
        ),
      );
    });
  }

  static bool _sameMoment(DateTime? a, DateTime? b) {
    if (a == null || b == null) return a == b;
    return a.isAtSameMomentAs(b);
  }

  /// Подписка на задачи с ещё не отправленным напоминанием.
  Stream<List<TaskEntity>> watchPendingReminders() {
    return (_db.select(_db.tasks)
          ..where(
            (t) =>
                t.deletedAt.isNull() &
                t.reminderAt.isNotNull() &
                t.isReminderSent.equals(false),
          ))
        .watch();
  }

  /// Отмечает напоминание задачи отправленным.
  Future<void> markReminderSent(String id) async {
    final now = DateTime.now().toUtc();
    await (_db.update(_db.tasks)..where((t) => t.id.equals(id))).write(
      TasksCompanion(
        isReminderSent: const Value(true),
        updatedAt: Value(now),
      ),
    );
  }

  /// Переключение статуса задачи (выполнено / к выполнению).
  ///
  /// Завершение повторяющейся задачи создаёт её следующий экземпляр.
  Future<void> toggleTaskStatus(TaskEntity task, {DateTime? now}) async {
    final completing = task.status != TaskStatus.completed.value;
    await _db.transaction(() async {
      await (_db.update(_db.tasks)..where((t) => t.id.equals(task.id))).write(
        TasksCompanion(
          status: Value(completing
              ? TaskStatus.completed.value
              : TaskStatus.todo.value),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );
      if (completing) {
        await _spawnNextOccurrence(task, now ?? DateTime.now());
      }
    });
  }

  /// Создаёт следующий экземпляр повторяющейся задачи со сдвинутым сроком
  /// и напоминанием; подзадачи копируются невыполненными. Если экземпляр
  /// уже есть (задачу снимали и снова отмечали), второй не создаётся.
  Future<void> _spawnNextOccurrence(TaskEntity task, DateTime now) async {
    final recurrence = TaskRecurrence.parse(task.recurrenceRule);
    if (recurrence == null || task.parentId != null) return;

    final due = task.dueDate?.toLocal();
    final nextDue = recurrence.nextDueDate(due, now);
    final existing = await (_db.select(_db.tasks)
          ..where((t) =>
              t.deletedAt.isNull() &
              t.parentId.isNull() &
              t.id.equals(task.id).not() &
              t.title.equals(task.title) &
              t.recurrenceRule.equals(task.recurrenceRule!) &
              t.dueDate.equals(nextDue)))
        .get();
    if (existing.isNotEmpty) return;

    final reminder = task.reminderAt;
    final nextReminder = reminder != null && due != null
        ? nextDue.add(reminder.difference(due))
        : null;

    final stamp = DateTime.now().toUtc();
    final nextId = _uuid.v4();
    await _db.into(_db.tasks).insert(TasksCompanion.insert(
          id: nextId,
          createdAt: stamp,
          updatedAt: stamp,
          title: task.title,
          description: Value(task.description),
          dueDate: Value(nextDue),
          reminderAt: Value(nextReminder),
          priority: Value(task.priority),
          status: Value(TaskStatus.todo.value),
          categoryId: Value(task.categoryId),
          recurrenceRule: Value(task.recurrenceRule),
        ));

    for (final subtask in await getSubtasks(task.id)) {
      await _db.into(_db.tasks).insert(TasksCompanion.insert(
            id: _uuid.v4(),
            createdAt: stamp,
            updatedAt: stamp,
            title: subtask.title,
            description: Value(subtask.description),
            priority: Value(subtask.priority),
            status: Value(TaskStatus.todo.value),
            categoryId: Value(subtask.categoryId),
            parentId: Value(nextId),
          ));
    }
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

  /// Мягкое удаление задачи (soft delete для LWW-синхронизации).
  /// Подзадачи без родителя смысла не имеют и удаляются вместе с ним.
  Future<void> deleteTask(String id) async {
    final now = DateTime.now().toUtc();
    await (_db.update(_db.tasks)
          ..where((t) =>
              (t.id.equals(id) | t.parentId.equals(id)) &
              t.deletedAt.isNull()))
        .write(
      TasksCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  }
}
