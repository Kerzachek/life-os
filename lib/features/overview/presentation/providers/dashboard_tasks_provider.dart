import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../tasks/domain/task_status.dart';
import 'life_score_provider.dart';

/// Максимум задач, показываемых в карточке «Задачи на сегодня».
const int dashboardTasksLimit = 5;

/// Сортировка задач для дашборда.
///
/// Активные задачи идут выше выполненных; внутри группы — по убыванию
/// приоритета, затем по возрастанию срока (задачи без срока — в конце),
/// затем по дате создания для стабильного порядка.
List<TaskEntity> sortTasksForDashboard(Iterable<TaskEntity> tasks) {
  final sorted = tasks.toList();
  sorted.sort((a, b) {
    final aDone = a.status == TaskStatus.completed.value;
    final bDone = b.status == TaskStatus.completed.value;
    if (aDone != bDone) return aDone ? 1 : -1;

    final byPriority = b.priority.compareTo(a.priority);
    if (byPriority != 0) return byPriority;

    final aDue = a.dueDate;
    final bDue = b.dueDate;
    if (aDue != bDue) {
      if (aDue == null) return 1;
      if (bDue == null) return -1;
      final byDue = aDue.compareTo(bDue);
      if (byDue != 0) return byDue;
    }

    return a.createdAt.compareTo(b.createdAt);
  });
  return sorted;
}

/// Задачи для карточки дашборда: тот же набор, что учитывается в Life Score
/// ([todayTasksStreamProvider]), отсортированный по приоритету.
final dashboardTasksProvider = Provider<AsyncValue<List<TaskEntity>>>((ref) {
  return ref
      .watch(todayTasksStreamProvider)
      .whenData(sortTasksForDashboard);
});
