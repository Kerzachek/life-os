import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_organizer/core/database/app_database.dart';
import 'package:home_organizer/core/database/database_provider.dart';
import 'package:home_organizer/features/settings/domain/app_module.dart';
import 'package:home_organizer/features/settings/presentation/providers/settings_provider.dart';
import 'package:home_organizer/features/settings/presentation/screens/settings_screen.dart';
import 'package:home_organizer/main.dart';

void main() {
  test('нельзя отключить последний активный модуль', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
    });

    final controller = container.read(settingsControllerProvider);

    expect(await controller.setModuleEnabled(AppModule.tasks, false), isTrue);
    expect(await controller.setModuleEnabled(AppModule.habits, false), isTrue);
    expect(await controller.setModuleEnabled(AppModule.finance, false), isFalse);
    expect(await controller.setModuleEnabled(AppModule.finance, true), isTrue);
  });

  testWidgets('отключение раздела скрывает пункт меню, SnackBar для последнего',
      (tester) async {
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

    expect(find.text('Задачи'), findsWidgets);

    await tester.tap(find.text('Настройки'));
    await tester.pumpAndSettle();

    final switches = find.byType(Switch);
    expect(switches, findsNWidgets(3));

    // Отключаем Задачи -> пункт исчезает из сайдбара.
    await tester.tap(switches.at(0));
    await tester.pumpAndSettle();
    expect(find.text('Привычки'), findsOneWidget); // только в сайдбаре
    expect(find.text('Задачи'), findsOneWidget); // только в карточке настроек

    // Отключаем Привычки и затем пытаемся отключить Финансы (последний).
    await tester.tap(switches.at(1));
    await tester.pumpAndSettle();
    await tester.tap(switches.at(2));
    await tester.pump();

    expect(find.text(SettingsScreen.lastModuleMessage), findsOneWidget);
    expect(tester.widget<Switch>(switches.at(2)).value, isTrue);

    // Размонтируем дерево и даём Drift закрыть потоки (иначе остаётся таймер).
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });
}
