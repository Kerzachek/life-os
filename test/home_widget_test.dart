import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_organizer/core/database/app_database.dart';
import 'package:home_organizer/core/database/database_provider.dart';
import 'package:home_organizer/core/services/home_widget_service.dart';
import 'package:home_organizer/features/finance/domain/finance_calculations.dart';
import 'package:home_organizer/features/routine/presentation/providers/routine_provider.dart';
import 'package:home_organizer/features/settings/domain/app_module.dart';
import 'package:home_organizer/features/tasks/data/repositories/tasks_repository.dart';
import 'package:home_organizer/features/tasks/domain/task_priority.dart';
import 'package:home_organizer/features/tasks/domain/task_status.dart';

TaskEntity _task(String title, {TaskStatus status = TaskStatus.todo}) {
  final t = DateTime.utc(2026, 10, 25);
  return TaskEntity(
    id: title,
    createdAt: t,
    updatedAt: t,
    title: title,
    priority: 1,
    status: status.value,
    isReminderSent: false,
  );
}

const _budget = DailySafeBudgetState(
  liquidBalance: 31000,
  unpaidObligations: 1000,
  spentToday: 0,
  daysRemaining: 10,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final all = AppModule.values.toSet();

  group('buildHomeWidgetData', () {
    test('Safe-to-Spend, две активные задачи и рутина', () {
      final data = buildHomeWidgetData(
        enabledModules: all,
        budget: _budget,
        todayTasks: [
          _task('Готово', status: TaskStatus.completed),
          _task('Первая'),
          _task('  Вторая  '),
          _task('Третья'),
        ],
        routine: const RoutineTodaySummary(completed: 3, total: 7),
      );

      expect(data.safeLabel, 'Доступно сегодня');
      expect(data.safeValue, '3 000 ₽');
      expect(data.safeIsNegative, isFalse);
      expect(data.tasks, ['Первая', 'Вторая']);
      expect(data.routineText, 'Рутина: 3 / 7');
      expect(data.toMap(), containsPair('task2', 'Вторая'));
    });

    test('перерасход дня помечается', () {
      final data = buildHomeWidgetData(
        enabledModules: all,
        budget: const DailySafeBudgetState(
          liquidBalance: 9000,
          unpaidObligations: 0,
          spentToday: 2000,
          daysRemaining: 10,
        ),
        todayTasks: const [],
        routine: null,
      );
      expect(data.safeValue, startsWith('−'));
      expect(data.safeIsNegative, isTrue);
      expect(data.tasks, isEmpty);
      expect(data.tasksEmptyText, 'На сегодня всё сделано');
      expect(data.routineText, isEmpty);
    });

    test('отключённые разделы и загрузка', () {
      final off = buildHomeWidgetData(
        enabledModules: const {},
        budget: _budget,
        todayTasks: [_task('Скрытая')],
        routine: const RoutineTodaySummary(completed: 1, total: 2),
      );
      expect(off.safeValue, 'Финансы отключены');
      expect(off.safeIsNegative, isFalse);
      expect(off.tasks, isEmpty);
      expect(off.tasksEmptyText, 'Задачи отключены');
      expect(off.routineText, isEmpty);

      final loading = buildHomeWidgetData(
        enabledModules: all,
        budget: null,
        todayTasks: null,
        routine: null,
      );
      expect(loading.safeValue, '…');
      expect(loading.tasksEmptyText, '…');
    });

    test('равенство по содержимому', () {
      HomeWidgetData make() => buildHomeWidgetData(
        enabledModules: all,
        budget: _budget,
        todayTasks: [_task('A')],
        routine: null,
      );
      expect(make(), make());
      expect(make().hashCode, make().hashCode);
    });
  });

  group('homeWidgetSyncProvider', () {
    const channel = MethodChannel('test/home_widget');
    late List<Map<Object?, Object?>> updates;
    late AppDatabase db;

    setUp(() {
      updates = [];
      db = AppDatabase.forTesting(NativeDatabase.memory());
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'update') {
              updates.add(call.arguments as Map<Object?, Object?>);
            }
            return null;
          });
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      await db.close();
    });

    ProviderContainer container({required bool supported}) {
      final c = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          homeWidgetSupportedProvider.overrideWithValue(supported),
          homeWidgetChannelProvider.overrideWithValue(
            const HomeWidgetChannel(channel),
          ),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    Future<void> waitDebounce() => Future<void>.delayed(
      homeWidgetDebounce + const Duration(milliseconds: 300),
    );

    test('отправляет данные и обновляет виджет при новой задаче', () async {
      final c = container(supported: true);
      c.listen(homeWidgetSyncProvider, (_, _) {});
      await waitDebounce();

      expect(updates, isNotEmpty);
      expect(updates.last['task1'], '');
      expect(updates.last['safeLabel'], 'Доступно сегодня');
      final before = updates.length;

      await c
          .read(tasksRepositoryProvider)
          .createTask(title: 'Вынести мусор', priority: TaskPriority.high);
      await waitDebounce();

      expect(updates.length, before + 1);
      expect(updates.last['task1'], 'Вынести мусор');
    });

    test('без изменений повторно не отправляет', () async {
      final c = container(supported: true);
      c.listen(homeWidgetSyncProvider, (_, _) {});
      await waitDebounce();
      final sent = updates.length;

      // Изменение, не влияющее на виджет (задача на будущее).
      await c
          .read(tasksRepositoryProvider)
          .createTask(
            title: 'Потом',
            dueDate: DateTime.now().add(const Duration(days: 5)),
          );
      await waitDebounce();
      expect(updates.length, sent);
    });

    test('не на Android канал не вызывается', () async {
      final c = container(supported: false);
      c.listen(homeWidgetSyncProvider, (_, _) {});
      await waitDebounce();
      expect(updates, isEmpty);
    });
  });
}
