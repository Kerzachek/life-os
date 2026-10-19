import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_organizer/core/database/app_database.dart';
import 'package:home_organizer/core/database/database_provider.dart';
import 'package:home_organizer/core/sync/google_drive_sync_service.dart';
import 'package:home_organizer/core/sync/sync_providers.dart';
import 'package:home_organizer/core/sync/sync_state.dart';
import 'package:home_organizer/features/tasks/data/repositories/tasks_repository.dart';
import 'package:http/http.dart' as http;

import 'helpers/fake_sync_cloud.dart';

void main() {
  late AppDatabase db;
  late FakeRemoteStore cloud;
  late FakeSyncAuth auth;
  late ProviderContainer container;

  ProviderContainer makeContainer({bool configured = true}) {
    return ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        syncConfiguredProvider.overrideWithValue(configured),
        syncAuthProvider.overrideWithValue(auth),
        syncRemoteStoreFactoryProvider
            .overrideWithValue((http.Client _) => cloud),
      ],
    );
  }

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase.forTesting(NativeDatabase.memory());
    cloud = FakeRemoteStore();
    auth = FakeSyncAuth();
    container = makeContainer();
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  GoogleDriveSyncService service() =>
      container.read(googleDriveSyncServiceProvider.notifier);
  SyncState state() => container.read(googleDriveSyncServiceProvider);

  test('до входа статус «Не подключено», синхронизация ничего не делает',
      () async {
    expect(state().label, 'Не подключено');
    await service().syncNow();
    expect(cloud.downloads, 0);
  });

  test('signIn → синхронизация → «Синхронизировано (время)»', () async {
    await service().signIn();

    expect(auth.signInCalls, 1);
    expect(state().signedIn, isTrue);
    expect(state().label, startsWith('Синхронизировано ('));
    expect(cloud.uploads, 1);
  });

  test('signOut возвращает «Не подключено»', () async {
    await service().signIn();
    await service().signOut();

    expect(auth.signOutCalls, 1);
    expect(state().signedIn, isFalse);
    expect(state().label, 'Не подключено');
  });

  test('start() восстанавливает сессию и синхронизирует', () async {
    auth.hasSession = true;
    await service().start();

    expect(state().signedIn, isTrue);
    expect(cloud.uploads, 1);
  });

  test('start() без сохранённой сессии ничего не делает', () async {
    await service().start();

    expect(state().signedIn, isFalse);
    expect(cloud.downloads, 0);
  });

  test('сетевая ошибка → «Ошибка (офлайн)», потом восстановление', () async {
    await service().signIn();
    cloud.failWith = http.ClientException('нет сети');

    await service().syncNow();
    expect(state().label, 'Ошибка (офлайн)');
    expect(state().offline, isTrue);

    cloud.failWith = null;
    await service().syncNow();
    expect(state().label, startsWith('Синхронизировано ('));
  });

  test('без OAuth Client ID вход заблокирован', () async {
    container.dispose();
    container = makeContainer(configured: false);

    await service().signIn();

    expect(auth.signInCalls, 0);
    expect(state().configured, isFalse);
  });

  test('локальное изменение запускает синхронизацию после дебаунса',
      () async {
    await service().signIn();
    final before = cloud.uploads;

    await container.read(tasksRepositoryProvider).createTask(title: 'Новая');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(cloud.uploads, before, reason: 'до дебаунса выгрузки нет');

    await Future<void>.delayed(
      GoogleDriveSyncService.debounce + const Duration(seconds: 1),
    );
    expect(cloud.uploads, before + 1);
  });
}
