import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../data/repositories/tasks_repository.dart';
import '../../domain/task_category.dart';
import '../../domain/task_priority.dart';
import '../../domain/task_status.dart';

enum TaskStatusFilter {
  active('Активные'),
  completed('Завершенные'),
  all('Все');

  final String label;
  const TaskStatusFilter(this.label);
}

/// Фильтр по категории; `null` — все категории.
class TaskCategoryFilterNotifier extends Notifier<TaskCategory?> {
  @override
  TaskCategory? build() => null;

  void setFilter(TaskCategory? category) => state = category;
}

final taskCategoryFilterProvider =
    NotifierProvider<TaskCategoryFilterNotifier, TaskCategory?>(
  TaskCategoryFilterNotifier.new,
);

class TaskStatusFilterNotifier extends Notifier<TaskStatusFilter> {
  @override
  TaskStatusFilter build() => TaskStatusFilter.active;

  void setFilter(TaskStatusFilter filter) => state = filter;
}

final taskStatusFilterProvider =
    NotifierProvider<TaskStatusFilterNotifier, TaskStatusFilter>(
  TaskStatusFilterNotifier.new,
);

class TaskSearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void setQuery(String query) => state = query;
}

final taskSearchQueryProvider =
    NotifierProvider<TaskSearchQueryNotifier, String>(
  TaskSearchQueryNotifier.new,
);

final rawTasksStreamProvider = StreamProvider<List<TaskEntity>>((ref) {
  final repository = ref.watch(tasksRepositoryProvider);
  return repository.watchTasks();
});

final filteredTasksProvider = Provider<AsyncValue<List<TaskEntity>>>((ref) {
  final tasksAsync = ref.watch(rawTasksStreamProvider);
  final categoryFilter = ref.watch(taskCategoryFilterProvider);
  final statusFilter = ref.watch(taskStatusFilterProvider);
  final searchQuery = ref.watch(taskSearchQueryProvider).trim().toLowerCase();

  return tasksAsync.whenData((tasks) {
    return tasks.where((task) {
      // Фильтр по категории
      if (categoryFilter != null &&
          TaskCategory.fromId(task.categoryId) != categoryFilter) {
        return false;
      }

      // Фильтр по статусу
      if (statusFilter == TaskStatusFilter.active && task.status == TaskStatus.completed.value) {
        return false;
      }
      if (statusFilter == TaskStatusFilter.completed && task.status != TaskStatus.completed.value) {
        return false;
      }

      // Поиск по названию или описанию
      if (searchQuery.isNotEmpty) {
        final titleMatches = task.title.toLowerCase().contains(searchQuery);
        final descMatches = task.description?.toLowerCase().contains(searchQuery) ?? false;
        if (!titleMatches && !descMatches) {
          return false;
        }
      }

      return true;
    }).toList();
  });
});

final tasksControllerProvider = Provider<TasksController>((ref) {
  return TasksController(ref.watch(tasksRepositoryProvider));
});

class TasksController {
  final TasksRepository _repository;

  TasksController(this._repository);

  Future<void> createTask({
    required String title,
    String? description,
    DateTime? dueDate,
    TaskPriority priority = TaskPriority.medium,
    TaskCategory category = TaskCategory.defaultCategory,
  }) async {
    await _repository.createTask(
      title: title,
      description: description,
      dueDate: dueDate,
      priority: priority,
      category: category,
    );
  }

  Future<void> updateTask({
    required String id,
    required String title,
    String? description,
    DateTime? dueDate,
    required TaskPriority priority,
    required TaskCategory category,
  }) async {
    await _repository.updateTask(
      id: id,
      title: title,
      description: description,
      dueDate: dueDate,
      priority: priority,
      category: category,
    );
  }

  Future<void> toggleTaskStatus(TaskEntity task) async {
    await _repository.toggleTaskStatus(task);
  }

  Future<void> updateTaskStatus(String id, TaskStatus status) async {
    await _repository.updateTaskStatus(id, status);
  }

  Future<void> deleteTask(String id) async {
    await _repository.deleteTask(id);
  }
}
