import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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

/// Прежнее место refresh-токена — `app_settings` (не синхронизируется).
/// Теперь только источник миграции и запасной вариант для
/// [SecureRefreshTokenStore].
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

/// refresh-токен в защищённом хранилище ОС: Windows Credential Manager,
/// связка ключей macOS, libsecret на Linux. Токен, сохранённый прежними
/// версиями в `app_settings`, при первом чтении переносится сюда и
/// удаляется из базы. Если хранилище ОС недоступно — работает через базу,
/// чтобы вход не ломался.
class SecureRefreshTokenStore implements RefreshTokenStore {
  static const String key = DbRefreshTokenStore.key;

  final FlutterSecureStorage _storage;
  final DbRefreshTokenStore _legacy;

  SecureRefreshTokenStore(this._legacy, {FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              // Связка ключей без data protection: не требует подписи
              // с keychain-access-groups (сборки CI не подписаны).
              mOptions: MacOsOptions(usesDataProtectionKeychain: false),
            );

  @override
  Future<String?> read() async {
    try {
      final token = await _storage.read(key: key);
      if (token != null) return token;
      final legacy = await _legacy.read();
      if (legacy != null) {
        await _storage.write(key: key, value: legacy);
        await _legacy.write(null);
      }
      return legacy;
    } catch (e) {
      debugPrint('SecureRefreshTokenStore: хранилище ОС недоступно: $e');
      return _legacy.read();
    }
  }

  @override
  Future<void> write(String? token) async {
    try {
      if (token == null) {
        await _storage.delete(key: key);
      } else {
        await _storage.write(key: key, value: token);
      }
    } catch (e) {
      debugPrint('SecureRefreshTokenStore: хранилище ОС недоступно: $e');
      await _legacy.write(token);
      return;
    }
    // Выход или новый токен: копии в базе больше быть не должно.
    await _legacy.write(null);
  }
}

final syncAuthProvider = Provider<SyncAuth>((ref) {
  if (GoogleSyncConfig.usesNativeSignIn) return MobileGoogleSignInAuth();
  return DesktopLoopbackAuth(
    SecureRefreshTokenStore(
      DbRefreshTokenStore(ref.watch(appDatabaseProvider)),
    ),
  );
});

/// Фабрика удалённого хранилища по авторизованному HTTP-клиенту.
final syncRemoteStoreFactoryProvider =
    Provider<SyncRemoteStore Function(http.Client client)>((ref) {
  return (client) => DriveAppDataStore(drive.DriveApi(client));
});
