import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/finance/domain/finance_calculations.dart';
import '../../features/finance/presentation/providers/finance_provider.dart';
import '../../features/finance/presentation/widgets/finance_format.dart';
import '../../features/overview/presentation/providers/dashboard_tasks_provider.dart';
import '../../features/routine/presentation/providers/routine_provider.dart';
import '../../features/settings/domain/app_module.dart';
import '../../features/settings/presentation/providers/settings_provider.dart';
import '../../features/tasks/domain/task_status.dart';
import '../database/app_database.dart';

/// Содержимое виджета на домашнем экране Android: готовые строки, чтобы
/// нативной стороне не нужно было ничего форматировать.
@immutable
class HomeWidgetData {
  const HomeWidgetData({
    required this.safeLabel,
    required this.safeValue,
    required this.safeIsNegative,
    required this.tasks,
    required this.tasksEmptyText,
    required this.routineText,
  });

  final String safeLabel;
  final String safeValue;

  /// Лимит дня превышен — сумма показывается красным.
  final bool safeIsNegative;

  /// До [maxTasks] невыполненных задач на сегодня.
  final List<String> tasks;

  /// Подпись вместо пустого списка задач.
  final String tasksEmptyText;

  /// «Рутина: 3 / 7» или пустая строка (раздел выключен / пунктов нет).
  final String routineText;

  static const int maxTasks = 2;

  Map<String, Object> toMap() => {
    'safeLabel': safeLabel,
    'safeValue': safeValue,
    'safeIsNegative': safeIsNegative,
    'task1': tasks.isNotEmpty ? tasks[0] : '',
    'task2': tasks.length > 1 ? tasks[1] : '',
    'tasksEmpty': tasksEmptyText,
    'routine': routineText,
  };

  @override
  bool operator ==(Object other) =>
      other is HomeWidgetData && mapEquals(other.toMap(), toMap());

  @override
  int get hashCode => Object.hashAll(toMap().values);
}

/// Собирает данные виджета. `null` у раздела — данные ещё загружаются.
HomeWidgetData buildHomeWidgetData({
  required Set<AppModule> enabledModules,
  required DailySafeBudgetState? budget,
  required List<TaskEntity>? todayTasks,
  required RoutineTodaySummary? routine,
}) {
  final financeOn = enabledModules.contains(AppModule.finance);
  final tasksOn = enabledModules.contains(AppModule.tasks);
  final routineOn = enabledModules.contains(AppModule.routine);

  final String safeValue;
  if (!financeOn) {
    safeValue = 'Финансы отключены';
  } else if (budget == null) {
    safeValue = '…';
  } else {
    safeValue = formatMoney(budget.remainingToday);
  }

  final active = !tasksOn || todayTasks == null
      ? const <TaskEntity>[]
      : todayTasks.where(
          (t) =>
              t.status != TaskStatus.completed.value &&
              t.status != TaskStatus.cancelled.value,
        );

  final String tasksEmpty;
  if (!tasksOn) {
    tasksEmpty = 'Задачи отключены';
  } else if (todayTasks == null) {
    tasksEmpty = '…';
  } else {
    tasksEmpty = 'На сегодня всё сделано';
  }

  return HomeWidgetData(
    safeLabel: 'Доступно сегодня',
    safeValue: safeValue,
    safeIsNegative: financeOn && (budget?.remainingToday ?? 0) < 0,
    tasks: [
      for (final t in active.take(HomeWidgetData.maxTasks)) t.title.trim(),
    ],
    tasksEmptyText: tasksEmpty,
    routineText: routineOn && routine != null && routine.total > 0
        ? 'Рутина: ${routine.completed} / ${routine.total}'
        : '',
  );
}

/// Мост к нативному виджету (`LifeOsGlanceWidget` в Android-проекте).
///
/// Канал `lifeos/home_widget`, метод `update` с картой
/// [HomeWidgetData.toMap]: данные сохраняются в SharedPreferences и все
/// экземпляры виджета перерисовываются.
class HomeWidgetChannel {
  static const MethodChannel defaultChannel = MethodChannel(
    'lifeos/home_widget',
  );

  final MethodChannel _channel;

  const HomeWidgetChannel([this._channel = defaultChannel]);

  Future<void> update(HomeWidgetData data) =>
      _channel.invokeMethod<void>('update', data.toMap());
}

/// Виджет есть только на Android.
final homeWidgetSupportedProvider = Provider<bool>(
  (ref) => !kIsWeb && Platform.isAndroid,
);

final homeWidgetChannelProvider = Provider<HomeWidgetChannel>(
  (ref) => const HomeWidgetChannel(),
);

/// Пауза перед отправкой: серия изменений (операция + пересчёт бюджета)
/// уходит в виджет одним обновлением.
const Duration homeWidgetDebounce = Duration(milliseconds: 800);

/// Следит за задачами, рутиной и финансами и обновляет виджет при
/// изменении того, что он показывает. Держится активным из главного экрана.
final homeWidgetSyncProvider = Provider<void>((ref) {
  if (!ref.watch(homeWidgetSupportedProvider)) return;
  final channel = ref.watch(homeWidgetChannelProvider);

  HomeWidgetData? sent;
  Timer? debounce;
  ref.onDispose(() => debounce?.cancel());

  void schedule() {
    debounce?.cancel();
    debounce = Timer(homeWidgetDebounce, () async {
      final data = buildHomeWidgetData(
        enabledModules: ref.read(enabledModulesProvider),
        budget: ref.read(dailySafeBudgetProvider).value,
        todayTasks: ref.read(dashboardTasksProvider).value,
        routine: ref.read(routineTodaySummaryProvider).value,
      );
      if (data == sent) return;
      try {
        await channel.update(data);
        sent = data;
      } catch (e) {
        debugPrint('HomeWidget: обновление не удалось: $e');
      }
    });
  }

  ref.listen(enabledModulesProvider, (_, _) => schedule());
  ref.listen(dailySafeBudgetProvider, (_, _) => schedule());
  ref.listen(dashboardTasksProvider, (_, _) => schedule());
  ref.listen(routineTodaySummaryProvider, (_, _) => schedule());
  schedule();
});
