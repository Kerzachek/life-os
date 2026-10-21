import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../data/repositories/routine_repository.dart';
import '../../domain/routine_category.dart';
import '../../domain/routine_day.dart';

final routineItemsStreamProvider =
    StreamProvider<List<RoutineItemEntity>>((ref) {
  return ref.watch(routineRepositoryProvider).watchItems();
});

final routineLogsStreamProvider =
    StreamProvider<List<RoutineDailyLogEntity>>((ref) {
  return ref.watch(routineRepositoryProvider).watchLogs();
});

/// Сводка чек-листа за сегодня.
class RoutineTodaySummary {
  final int completed;
  final int total;

  const RoutineTodaySummary({required this.completed, required this.total});

  /// Доля выполнения или `null`, если пунктов нет.
  double? get ratio => total > 0 ? completed / total : null;
}

final routineTodaySummaryProvider =
    Provider<AsyncValue<RoutineTodaySummary>>((ref) {
  return ref.watch(routineItemsStreamProvider).whenData((items) {
    final now = DateTime.now();
    return RoutineTodaySummary(
      completed: items.where((i) => isRoutineDoneToday(i, now)).length,
      total: items.length,
    );
  });
});

final routineControllerProvider = Provider<RoutineController>((ref) {
  return RoutineController(ref.watch(routineRepositoryProvider));
});

class RoutineController {
  final RoutineRepository _repository;

  RoutineController(this._repository);

  Future<void> createItem(String title, RoutineCategory category) {
    return _repository.createItem(title: title.trim(), category: category);
  }

  Future<void> updateItem(
    RoutineItemEntity item,
    String title,
    RoutineCategory category,
  ) {
    return _repository.updateItem(
      id: item.id,
      title: title.trim(),
      category: category,
    );
  }

  /// Переключает отметку «сделано сегодня».
  Future<void> toggle(RoutineItemEntity item) {
    final doneToday = isRoutineDoneToday(item, DateTime.now());
    return _repository.setCompleted(item.id, !doneToday);
  }

  Future<void> deleteItem(String id) => _repository.deleteItem(id);

  Future<void> reorder(List<String> orderedIds) =>
      _repository.reorder(orderedIds);
}
