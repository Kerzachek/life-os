import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_organizer/core/database/app_database.dart';
import 'package:home_organizer/core/sync/sync_providers.dart';

void main() {
  late AppDatabase db;
  late DbRefreshTokenStore legacy;
  const storage = FlutterSecureStorage();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    legacy = DbRefreshTokenStore(db);
  });

  tearDown(() => db.close());

  test('токен пишется в хранилище ОС, а не в базу', () async {
    final store = SecureRefreshTokenStore(legacy, storage: storage);
    await store.write('refresh-1');

    expect(await storage.read(key: SecureRefreshTokenStore.key), 'refresh-1');
    expect(await legacy.read(), isNull);
    expect(await store.read(), 'refresh-1');
  });

  test('токен из базы прежних версий переносится и удаляется', () async {
    await legacy.write('old-token');
    final store = SecureRefreshTokenStore(legacy, storage: storage);

    expect(await store.read(), 'old-token');
    expect(await storage.read(key: SecureRefreshTokenStore.key), 'old-token');
    expect(await legacy.read(), isNull);
  });

  test('выход удаляет токен везде', () async {
    await legacy.write('old-token');
    final store = SecureRefreshTokenStore(legacy, storage: storage);
    await store.write('refresh-1');
    await store.write(null);

    expect(await store.read(), isNull);
    expect(await legacy.read(), isNull);
  });
}
