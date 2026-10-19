import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_organizer/core/database/app_database.dart';
import 'package:home_organizer/core/database/database_provider.dart';
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
}



