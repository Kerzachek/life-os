import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_organizer/core/database/app_database.dart';
import 'package:home_organizer/core/database/database_provider.dart';
import 'package:home_organizer/features/overview/presentation/widgets/dashboard_empty_state.dart';
import 'package:home_organizer/features/settings/data/repositories/settings_repository.dart';
import 'package:home_organizer/features/settings/domain/app_module.dart';
import 'package:home_organizer/features/settings/presentation/providers/settings_provider.dart';
import 'package:home_organizer/features/settings/presentation/widgets/module_toggle_tile.dart';
import 'package:home_organizer/main.dart';

void main() {
  test('можно отключить все разделы и выключить уведомления', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
    });

    final controller = container.read(settingsControllerProvider);
    final repo = container.read(settingsRepositoryProvider);

    expect(resolveNotificationsEnabled(await repo.readAll()), isTrue);

    for (final module in AppModule.values) {
      await controller.setModuleEnabled(module, false);
    }
    await controller.setNotificationsEnabled(false);

    final settings = await repo.readAll();
    expect(resolveEnabledModules(settings), isEmpty);
    expect(resolveNotificationsEnabled(settings), isFalse);
  });

  testWidgets(
      'отключение разделов скрывает пункты меню, быстрые действия, '
      'прогресс и показывает пустое состояние', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const HomeOrganizerApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('+ Задача'), findsOneWidget);
    expect(find.text('+ Привычка'), findsOneWidget);
    expect(find.text('+ Операция'), findsOneWidget);
    expect(find.text('Прогресс и Продуктивность'), findsOneWidget);

    Future<void> toggle(int index) async {
      await tester.tap(find.text('Настройки'));
      await tester.pumpAndSettle();
      final switches = find.descendant(
        of: find.byType(ModuleToggleTile),
        matching: find.byType(Switch),
      );
      expect(switches, findsNWidgets(3));
      await tester.tap(switches.at(index));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Дашборд'));
      await tester.pumpAndSettle();
    }

    // Задачи выключены: нет пункта меню, кнопки и бара задач.
    await toggle(0);
    expect(find.text('Задачи'), findsNothing);
    expect(find.text('+ Задача'), findsNothing);
    expect(find.text('Выполнение задач'), findsNothing);
    expect(find.text('Привычки за сегодня'), findsOneWidget);

    // Привычки тоже выключены: блок прогресса скрыт целиком.
    await toggle(1);
    expect(find.text('+ Привычка'), findsNothing);
    expect(find.text('+ Челлендж'), findsNothing);
    expect(find.text('Привычки и Стрики'), findsNothing);
    expect(find.text('Прогресс и Продуктивность'), findsNothing);
    expect(find.text('+ Операция'), findsOneWidget);

    // Все разделы выключены: пустое состояние с переходом в Настройки.
    await toggle(2);
    expect(find.text(DashboardEmptyState.title), findsOneWidget);
    expect(find.text('Быстрые действия'), findsNothing);

    await tester.tap(find.text('Открыть Настройки'));
    await tester.pumpAndSettle();
    expect(find.byType(ModuleToggleTile), findsNWidgets(3));

    // Размонтируем дерево и даём Drift закрыть потоки (иначе остаётся таймер).
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });
}
