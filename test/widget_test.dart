import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_organizer/core/database/app_database.dart';
import 'package:home_organizer/core/database/database_provider.dart';
import 'package:home_organizer/core/widgets/app_sidebar.dart';
import 'package:home_organizer/main.dart';

void main() {
  testWidgets('App loads smoke test', (WidgetTester tester) async {
    final testDb = AppDatabase.forTesting(NativeDatabase.memory());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(testDb),
        ],
        child: const HomeOrganizerApp(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('LIFE OS'), findsOneWidget);
    expect(find.text('Добро пожаловать в Life OS'), findsOneWidget);

    await testDb.close();
  });

  testWidgets('на узком экране — нижняя навигация вместо бокового меню',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final testDb = AppDatabase.forTesting(NativeDatabase.memory());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(testDb),
        ],
        child: const HomeOrganizerApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AppSidebar), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);

    await tester.tap(find.descendant(
      of: find.byType(NavigationBar),
      matching: find.byIcon(Icons.settings_rounded),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Персонализация приложения'), findsOneWidget);

    // Сначала размонтировать приложение (отписка от стримов drift),
    // затем закрыть базу — иначе close() ждёт незавершённый запрос.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await testDb.close();
  });
}
