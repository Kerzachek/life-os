import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_organizer/core/backup/local_backup_service.dart';
import 'package:home_organizer/core/backup/local_backup_store.dart';
import 'package:home_organizer/core/backup/local_file_gateway.dart';
import 'package:home_organizer/core/database/app_database.dart';
import 'package:home_organizer/core/database/database_provider.dart';
import 'package:home_organizer/features/settings/presentation/widgets/backup_settings_card.dart';

class _FakeGateway implements LocalFileGateway {
  String? savedName;
  Uint8List? savedBytes;
  Uint8List? toPick;

  @override
  Future<String?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String extension,
    String? dialogTitle,
  }) async {
    savedName = fileName;
    savedBytes = bytes;
    return 'C:/backups/$fileName';
  }

  @override
  Future<Uint8List?> pickFile({
    required String extension,
    String? dialogTitle,
  }) async => toPick;
}

void main() {
  late AppDatabase db;
  late _FakeGateway gateway;
  late Directory backupDir;
  late LocalBackupStore store;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    gateway = _FakeGateway();
    backupDir = Directory.systemTemp.createTempSync('lifeos_backup_card');
    store = LocalBackupStore(() async => backupDir);
  });

  tearDown(() async {
    await db.close();
    if (backupDir.existsSync()) backupDir.deleteSync(recursive: true);
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          localFileGatewayProvider.overrideWithValue(gateway),
          localBackupStoreProvider.overrideWithValue(store),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: BackupSettingsCard(now: () => DateTime(2026, 10, 24, 18, 5)),
          ),
        ),
      ),
    );
  }

  /// Даёт завершиться реальным запросам к SQLite и файлам и перерисовывает
  /// экран. Каждый шаг файлового ввода-вывода продолжается только после
  /// перерисовки, поэтому циклов несколько.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
    }
  }

  testWidgets('создание копии сохраняет JSON с именем по умолчанию', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(find.byKey(const ValueKey('backup_export')));
    await settle(tester);

    expect(gateway.savedName, 'LifeOS_Backup_2026-10-24_1805.json');
    expect(gateway.savedBytes, isNotNull);
    expect(
      find.text(
        'Резервная копия сохранена в папке приложения и в выбранный файл',
      ),
      findsOneWidget,
    );
    // Та же копия лежит в папке приложения.
    final local = await tester.runAsync(() => store.list());
    expect(local!.single.fileName, 'LifeOS_Backup_2026-10-24.json');
    expect(
      await tester.runAsync(() => store.read(local.single)),
      gateway.savedBytes,
    );
    expect(
      find.text('Локальных копий: 1, последняя — 24.10.2026'),
      findsOneWidget,
    );
  });

  testWidgets('восстановление из локальной копии через список', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await db
          .into(db.tasks)
          .insert(
            TasksCompanion.insert(
              id: 'task-1',
              createdAt: DateTime.utc(2026),
              updatedAt: DateTime.utc(2026),
              title: 'Из локальной копии',
            ),
          );
      final container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
      );
      final bytes = await container
          .read(localBackupServiceProvider)
          .createBackup();
      container.dispose();
      await store.save(bytes, DateTime(2026, 10, 23));
      await db.delete(db.tasks).go();
    });
    await pump(tester);
    await settle(tester);

    await tester.tap(find.byKey(const ValueKey('backup_import')));
    await settle(tester);
    expect(find.text('Выберите резервную копию'), findsOneWidget);
    expect(find.byKey(const ValueKey('backup_pick_external')), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('backup_local_LifeOS_Backup_2026-10-23.json')),
    );
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Восстановить'));
    await settle(tester);

    final tasks = await tester.runAsync(() => db.select(db.tasks).get());
    expect(tasks!.single.title, 'Из локальной копии');
  });

  testWidgets('восстановление спрашивает подтверждение и сливает копию', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await db
          .into(db.tasks)
          .insert(
            TasksCompanion.insert(
              id: 'task-1',
              createdAt: DateTime.utc(2026),
              updatedAt: DateTime.utc(2026),
              title: 'Из копии',
            ),
          );
      final container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
      );
      gateway.toPick = await container
          .read(localBackupServiceProvider)
          .createBackup();
      container.dispose();
      await db.delete(db.tasks).go();
    });
    await pump(tester);

    await tester.tap(find.byKey(const ValueKey('backup_import')));
    await settle(tester);
    expect(find.text('Восстановить из копии?'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Восстановить'));
    await settle(tester);

    final tasks = await tester.runAsync(() => db.select(db.tasks).get());
    expect(tasks!.single.title, 'Из копии');
    expect(find.textContaining('Восстановлено: добавлено'), findsOneWidget);
  });

  testWidgets('битый файл — сообщение об ошибке, без диалога', (tester) async {
    gateway.toPick = Uint8List.fromList('oops'.codeUnits);
    await pump(tester);

    await tester.tap(find.byKey(const ValueKey('backup_import')));
    await settle(tester);

    expect(find.text('Восстановить из копии?'), findsNothing);
    expect(find.textContaining('повреждён'), findsOneWidget);
  });
}
