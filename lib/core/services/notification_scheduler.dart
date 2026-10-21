import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:intl/intl.dart';

import '../../features/finance/domain/finance_calculations.dart';
import '../../features/finance/presentation/providers/finance_provider.dart';
import '../../features/habits/domain/habit_with_status.dart';
import '../../features/habits/presentation/providers/habits_provider.dart';
import '../../features/overview/presentation/providers/life_score_provider.dart';
import '../../features/settings/data/repositories/settings_repository.dart';
import '../../features/settings/domain/app_module.dart';
import '../../features/tasks/data/repositories/tasks_repository.dart';
import '../../features/tasks/domain/task_reminder.dart';
import '../../features/tasks/domain/task_status.dart';
import '../../features/tasks/presentation/providers/tasks_provider.dart';
import '../database/app_database.dart';
import 'notification_service.dart';
import 'update_service.dart';

/// Содержимое одного напоминания.
class NotificationMessage {
  final String title;
  final String body;

  const NotificationMessage(this.title, this.body);
}

/// Час, начиная с которого напоминаем о невыполненных привычках.
const int habitsReminderHour = 20;

String _names(Iterable<String> names, {int limit = 3}) {
  final list = names.toList();
  final shown = list.take(limit).join(', ');
  return list.length > limit ? '$shown и ещё ${list.length - limit}' : shown;
}

/// Напоминание о невыполненных задачах со сроком на сегодня или просроченных.
NotificationMessage? buildTasksReminder(
  List<TaskEntity> tasks,
  DateTime now,
) {
  final startOfToday = DateTime(now.year, now.month, now.day);
  final startOfTomorrow = DateTime(now.year, now.month, now.day + 1);
  final due = tasks
      .where((t) =>
          t.status != TaskStatus.completed.value &&
          t.status != TaskStatus.cancelled.value &&
          t.dueDate != null &&
          t.dueDate!.toLocal().isBefore(startOfTomorrow))
      .toList();
  if (due.isEmpty) return null;

  final overdue =
      due.where((t) => t.dueDate!.toLocal().isBefore(startOfToday)).length;
  final suffix = overdue > 0 ? ' (просрочено: $overdue)' : '';
  return NotificationMessage(
    'LifeOS — Задачи на сегодня',
    'Невыполненных задач: ${due.length}$suffix. '
        '${_names(due.map((t) => t.title))}',
  );
}

/// Персональное напоминание о задаче (поле `reminderAt`).
NotificationMessage buildTaskReminder(TaskEntity task) {
  final due = task.dueDate;
  final body = due == null
      ? task.title
      : '${task.title}\nСрок: ${DateFormat('dd.MM.yyyy').format(due.toLocal())}';
  return NotificationMessage('Напоминание о задаче', body);
}

/// Вечернее напоминание о невыполненных сегодня привычках.
NotificationMessage? buildHabitsReminder(
  List<HabitWithStatus> habits,
  DateTime now,
) {
  if (now.hour < habitsReminderHour) return null;
  final pending = habits.where((h) => !h.isCompletedToday).toList();
  if (pending.isEmpty) return null;
  return NotificationMessage(
    'LifeOS — Привычки',
    'Сегодня ещё не выполнено: ${pending.length}. '
        '${_names(pending.map((h) => h.habit.title))}',
  );
}

/// Напоминание о неоплаченных обязательных платежах, срок которых близко.
NotificationMessage? buildPaymentsReminder(List<ObligationStatus> statuses) {
  final pending =
      statuses.where((s) => !s.isPaid && s.needsAttention).toList();
  if (pending.isEmpty) return null;
  final overdue =
      pending.where((s) => s.urgency == ObligationUrgency.overdue).length;
  final suffix = overdue > 0 ? ' (просрочено: $overdue)' : '';
  return NotificationMessage(
    'LifeOS — Обязательные платежи',
    'Требуют оплаты: ${pending.length}$suffix. '
        '${_names(pending.map((s) => s.obligation.name))}',
  );
}

/// Периодически проверяет данные включённых разделов и отправляет
/// напоминания. Каждый тип — не чаще раза в день (метка хранится в настройках).
class NotificationScheduler {
  static const Duration checkInterval = Duration(minutes: 15);
  static const Duration taskRemindersInterval = Duration(seconds: 30);
  static const Duration _debounce = Duration(seconds: 3);
  static const String _sentKeyPrefix = 'notification_sent_';

  final Ref _ref;
  final List<ProviderSubscription<Object?>> _subscriptions = [];
  Timer? _periodic;
  Timer? _remindersPeriodic;
  Timer? _pending;
  bool _running = false;
  bool _remindersRunning = false;
  bool _started = false;

  NotificationScheduler(this._ref);

  NotificationService get _service => _ref.read(notificationServiceProvider);
  SettingsRepository get _settings => _ref.read(settingsRepositoryProvider);

  /// Запускает проверки. Без доступных уведомлений (не Windows, тесты) — no-op.
  void start() {
    if (_started || !NotificationService.isAvailable) return;
    _started = true;

    // Подписки держат потоки данных активными и запускают проверку,
    // когда данные загрузились или изменились.
    void watch<T>(ProviderListenable<T> provider) {
      _subscriptions.add(
        _ref.listen<T>(provider, (_, _) => _schedule()),
      );
    }

    watch(todayTasksStreamProvider);
    watch(habitsWithStatusProvider);
    watch(obligationStatusesProvider);
    _subscriptions.add(_ref.listen(
      pendingRemindersStreamProvider,
      (_, _) => unawaited(_checkTaskReminders()),
    ));

    _periodic = Timer.periodic(checkInterval, (_) => _schedule());
    // Таймер срабатывает и сразу после выхода системы из сна.
    _remindersPeriodic = Timer.periodic(
      taskRemindersInterval,
      (_) => unawaited(_checkTaskReminders()),
    );
    _schedule();
    unawaited(_checkTaskReminders());
    unawaited(_checkUpdate());
  }

  /// Отправляет наступившие персональные напоминания о задачах. Каждое —
  /// один раз: после показа задача помечается `isReminderSent`.
  Future<void> _checkTaskReminders() async {
    if (_remindersRunning) return;
    _remindersRunning = true;
    try {
      final tasks = _ref.read(pendingRemindersStreamProvider).value;
      if (tasks == null) return;
      final due = dueTaskReminders(tasks, DateTime.now());
      if (due.isEmpty) return;
      // Раздел или уведомления выключены — напоминания ждут включения.
      if (!await _service.canNotify(AppModule.tasks)) return;

      final repository = _ref.read(tasksRepositoryProvider);
      for (final task in due) {
        final message = buildTaskReminder(task);
        final sent = await _service.show(
          title: message.title,
          body: message.body,
          module: AppModule.tasks,
        );
        if (sent) await repository.markReminderSent(task.id);
      }
    } catch (e) {
      debugPrint('NotificationScheduler: ошибка напоминаний задач: $e');
    } finally {
      _remindersRunning = false;
    }
  }

  void _schedule() {
    _pending?.cancel();
    _pending = Timer(_debounce, () => unawaited(_evaluate()));
  }

  Future<void> _evaluate() async {
    if (_running) return;
    _running = true;
    try {
      final now = DateTime.now();
      final tasks = _ref.read(todayTasksStreamProvider).value;
      final habits = _ref.read(habitsWithStatusProvider).value;
      final payments = _ref.read(obligationStatusesProvider).value;

      if (tasks != null) {
        await _sendDaily(
            AppModule.tasks, buildTasksReminder(tasks, now), now);
      }
      if (habits != null) {
        await _sendDaily(
            AppModule.habits, buildHabitsReminder(habits, now), now);
      }
      if (payments != null) {
        await _sendDaily(
            AppModule.finance, buildPaymentsReminder(payments), now);
      }
    } catch (e) {
      debugPrint('NotificationScheduler: ошибка проверки: $e');
    } finally {
      _running = false;
    }
  }

  Future<void> _sendDaily(
    AppModule module,
    NotificationMessage? message,
    DateTime now,
  ) async {
    if (message == null) return;
    final key = '$_sentKeyPrefix${module.name}';
    final today = DateFormat('yyyy-MM-dd').format(now);
    final settings = await _settings.readAll();
    if (settings[key] == today) return;

    final sent = await _service.show(
      title: message.title,
      body: message.body,
      module: module,
    );
    if (sent) await _settings.setValue(key, today);
  }

  /// Уведомление о новой версии — один раз на каждый релиз.
  Future<void> _checkUpdate() async {
    const key = '${_sentKeyPrefix}update';
    try {
      final release = await _ref.read(updateServiceProvider).checkForUpdates();
      if (release == null) return;
      final settings = await _settings.readAll();
      if (settings[key] == release.tagName) return;

      final sent = await _service.show(
        title: 'LifeOS — Доступно обновление',
        body: 'Вышла версия ${release.tagName}. '
            'Установить её можно в разделе «Настройки».',
      );
      if (sent) await _settings.setValue(key, release.tagName);
    } catch (e) {
      debugPrint('NotificationScheduler: проверка обновлений не удалась: $e');
    }
  }

  void dispose() {
    _periodic?.cancel();
    _remindersPeriodic?.cancel();
    _pending?.cancel();
    for (final s in _subscriptions) {
      s.close();
    }
    _subscriptions.clear();
  }
}

final notificationSchedulerProvider = Provider<NotificationScheduler>((ref) {
  final scheduler = NotificationScheduler(ref);
  ref.onDispose(scheduler.dispose);
  return scheduler;
});
