import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

import '../database/app_database.dart';
import '../database/database_provider.dart';
import 'sync_auth.dart';
import 'sync_engine.dart';
import 'sync_remote_store.dart';

final syncEngineProvider = Provider<SyncEngine>((ref) {
  return SyncEngine(ref.watch(appDatabaseProvider));
});

/// Настроены ли OAuth Client ID в сборке. Переопределяется в тестах.
final syncConfiguredProvider =
    Provider<bool>((ref) => GoogleSyncConfig.isConfigured);

/// refresh-токен десктопа хранится в `app_settings` (не синхронизируется).
class DbRefreshTokenStore implements RefreshTokenStore {
  static const String key = 'sync_google_refresh_token';

  final AppDatabase _db;

  DbRefreshTokenStore(this._db);

  @override
  Future<String?> read() async {
    final row = await (_db.select(_db.appSettings)
          ..where((s) => s.settingKey.equals(key)))
        .getSingleOrNull();
    return row?.settingValue;
  }

  @override
  Future<void> write(String? token) async {
    if (token == null) {
      await (_db.delete(_db.appSettings)
            ..where((s) => s.settingKey.equals(key)))
          .go();
      return;
    }
    await _db.into(_db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion.insert(settingKey: key, settingValue: token),
        );
  }
}

final syncAuthProvider = Provider<SyncAuth>((ref) {
  if (GoogleSyncConfig.isMobile) return MobileGoogleSignInAuth();
  return DesktopLoopbackAuth(
    DbRefreshTokenStore(ref.watch(appDatabaseProvider)),
  );
});

/// Фабрика удалённого хранилища по авторизованному HTTP-клиенту.
final syncRemoteStoreFactoryProvider =
    Provider<SyncRemoteStore Function(http.Client client)>((ref) {
  return (client) => DriveAppDataStore(drive.DriveApi(client));
});
