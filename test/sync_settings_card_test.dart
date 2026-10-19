import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_organizer/core/database/app_database.dart';
import 'package:home_organizer/core/database/database_provider.dart';
import 'package:home_organizer/core/sync/sync_providers.dart';
import 'package:home_organizer/core/theme/app_theme.dart';
import 'package:home_organizer/features/settings/presentation/widgets/sync_settings_card.dart';
import 'package:http/http.dart' as http;

import 'helpers/fake_sync_cloud.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required AppDatabase db,
    required FakeSyncAuth auth,
    required FakeRemoteStore cloud,
    bool configured = true,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          syncConfiguredProvider.overrideWithValue(configured),
          syncAuthProvider.overrideWithValue(auth),
          syncRemoteStoreFactoryProvider
              .overrideWithValue((http.Client _) => cloud),
        ],
        child: MaterialApp(
          theme: AppTheme.darkLauncherTheme,
          home: const Scaffold(body: SyncSettingsCard()),
        ),
      ),
    );
    await tester.pump();
  }

  String statusText(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const ValueKey('sync_status_label')))
      .data!;

  testWidgets('вход, синхронизация и выход меняют статус и кнопки',
      (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final cloud = FakeRemoteStore();
    final auth = FakeSyncAuth();

    await pump(tester, db: db, auth: auth, cloud: cloud);

    expect(statusText(tester), 'Не подключено');
    expect(find.text('Войти через Google'), findsOneWidget);
    expect(find.text('Выйти'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('sync_sign_in')));
    await tester.pumpAndSettle();

    expect(statusText(tester), startsWith('Синхронизировано ('));
    expect(find.text('user@example.com'), findsOneWidget);
    expect(find.text('Синхронизировать сейчас'), findsOneWidget);
    expect(find.text('Войти через Google'), findsNothing);
    expect(cloud.uploads, 1);

    await tester.tap(find.byKey(const ValueKey('sync_now')));
    await tester.pumpAndSettle();
    expect(cloud.downloads, 2);

    await tester.tap(find.byKey(const ValueKey('sync_sign_out')));
    await tester.pumpAndSettle();
    expect(statusText(tester), 'Не подключено');

    // Размонтируем дерево и даём Drift закрыть потоки (иначе остаётся таймер).
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('без OAuth Client ID кнопка входа отключена', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await pump(
      tester,
      db: db,
      auth: FakeSyncAuth(),
      cloud: FakeRemoteStore(),
      configured: false,
    );

    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('sync_sign_in')),
    );
    expect(button.onPressed, isNull);
    expect(find.text(SyncSettingsCard.notConfiguredHint), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });
}
