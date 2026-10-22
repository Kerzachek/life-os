import 'dart:io';

import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart' as gauth;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'loopback_oauth_flow.dart';

/// OAuth-идентификаторы, передаются при сборке через `--dart-define`:
///
/// ```
/// flutter run -d windows \
///   --dart-define=GOOGLE_DESKTOP_CLIENT_ID=xxx.apps.googleusercontent.com \
///   --dart-define=GOOGLE_DESKTOP_CLIENT_SECRET=yyy
/// flutter run -d android \
///   --dart-define=GOOGLE_SERVER_CLIENT_ID=zzz.apps.googleusercontent.com
/// ```
class GoogleSyncConfig {
  static const String desktopClientId =
      String.fromEnvironment('GOOGLE_DESKTOP_CLIENT_ID');
  static const String desktopClientSecret =
      String.fromEnvironment('GOOGLE_DESKTOP_CLIENT_SECRET');
  static const String serverClientId =
      String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  static const List<String> scopes = [drive.DriveApi.driveAppdataScope];

  /// Нативный Google Sign-In — только iOS. Android входит через браузер
  /// (loopback + PKCE, десктопный клиент): Credential Manager отвечал 28444
  /// при верно настроенном Android-клиенте.
  static bool get usesNativeSignIn => Platform.isIOS;

  static bool get isConfigured => usesNativeSignIn
      ? serverClientId.isNotEmpty
      : desktopClientId.isNotEmpty;
}

/// Хранилище refresh-токена между запусками (вход через браузер).
abstract class RefreshTokenStore {
  Future<String?> read();
  Future<void> write(String? token);
}

/// Авторизация пользователя в Google с доступом к `appDataFolder`.
abstract class SyncAuth {
  /// Подпись аккаунта для UI (e-mail), если известна.
  String? get accountLabel;

  /// Пытается восстановить предыдущую сессию без UI.
  Future<bool> restore();

  /// Интерактивный вход.
  Future<bool> signIn();

  /// Выполняет [action] с авторизованным HTTP-клиентом.
  Future<T> withClient<T>(Future<T> Function(http.Client client) action);

  Future<void> signOut();
}

/// Windows / macOS / Linux / Android: OAuth 2.0 loopback + PKCE через браузер.
class DesktopLoopbackAuth implements SyncAuth {
  final RefreshTokenStore tokenStore;
  final gauth.ClientId _clientId = gauth.ClientId(
    GoogleSyncConfig.desktopClientId,
    GoogleSyncConfig.desktopClientSecret.isEmpty
        ? null
        : GoogleSyncConfig.desktopClientSecret,
  );

  gauth.AutoRefreshingAuthClient? _client;
  http.Client? _baseClient;

  DesktopLoopbackAuth(this.tokenStore);

  @override
  String? get accountLabel => null;

  @override
  Future<bool> restore() async {
    final token = await tokenStore.read();
    if (token == null) return false;
    try {
      _client = await gauth.clientViaRefreshToken(
        _clientId,
        token,
        GoogleSyncConfig.scopes,
      );
      return true;
    } on gauth.ServerRequestFailedException catch (e) {
      // Токен отозван / недействителен — нужен повторный вход.
      if (e.statusCode == 400 || e.statusCode == 401) {
        await tokenStore.write(null);
        return false;
      }
      rethrow;
    }
  }

  @override
  Future<bool> signIn() async {
    final base = http.Client();
    final gauth.AutoRefreshingAuthClient client;
    try {
      // Loopback-сервер на 127.0.0.1 (а не 'localhost'): иначе на Windows
      // браузер получает ERR_CONNECTION_REFUSED.
      final credentials = await obtainCredentialsViaLoopback(
        clientId: _clientId,
        scopes: GoogleSyncConfig.scopes,
        client: base,
        userPrompt: (url) => launchUrl(
          Uri.parse(url),
          mode: LaunchMode.externalApplication,
        ),
      );
      client = gauth.autoRefreshingClient(_clientId, credentials, base);
    } catch (_) {
      base.close();
      rethrow;
    }
    _closeClient();
    _client = client;
    _baseClient = base;
    await tokenStore.write(client.credentials.refreshToken);
    return true;
  }

  void _closeClient() {
    _client?.close();
    _baseClient?.close();
    _client = null;
    _baseClient = null;
  }

  @override
  Future<T> withClient<T>(Future<T> Function(http.Client client) action) {
    final client = _client;
    if (client == null) throw StateError('Нет активной сессии Google');
    return action(client);
  }

  @override
  Future<void> signOut() async {
    _closeClient();
    await tokenStore.write(null);
  }
}

/// Ошибка входа через Google с понятным текстом для баннера синхронизации.
class GoogleSignInFailure implements Exception {
  final String message;

  const GoogleSignInFailure(this.message);

  @override
  String toString() => message;
}

/// Переводит [GoogleSignInException] в подсказку. Код 28444 (Credential
/// Manager) означает, что в Google Cloud нет Android-клиента с этим пакетом
/// и SHA-1 или Server Client ID не является Web-клиентом того же проекта.
GoogleSignInFailure describeGoogleSignInError(GoogleSignInException e) {
  final details = '${e.description ?? ''} ${e.details ?? ''}';
  if (details.contains('28444') ||
      e.code == GoogleSignInExceptionCode.clientConfigurationError ||
      e.code == GoogleSignInExceptionCode.providerConfigurationError) {
    return GoogleSignInFailure(
      'Google Cloud не настроен для Android (${e.description ?? e.code.name}). '
      'Проверьте Android OAuth-клиент (пакет и SHA-1) и что '
      'GOOGLE_SERVER_CLIENT_ID — Web-клиент того же проекта.',
    );
  }
  return GoogleSignInFailure(
      'Не удалось войти в Google: ${e.description ?? e.code.name}');
}

/// Android / iOS: нативный Google Sign-In (`google_sign_in` v7).
class MobileGoogleSignInAuth implements SyncAuth {
  static bool _initialized = false;

  GoogleSignInAccount? _account;

  @override
  String? get accountLabel => _account?.email;

  Future<GoogleSignIn> _instance() async {
    final gs = GoogleSignIn.instance;
    if (!_initialized) {
      await gs.initialize(
        serverClientId: GoogleSyncConfig.serverClientId.isEmpty
            ? null
            : GoogleSyncConfig.serverClientId,
      );
      _initialized = true;
    }
    return gs;
  }

  @override
  Future<bool> restore() async {
    final gs = await _instance();
    final account = await gs.attemptLightweightAuthentication();
    if (account == null) return false;
    final authz = await account.authorizationClient
        .authorizationForScopes(GoogleSyncConfig.scopes);
    if (authz == null) return false;
    _account = account;
    return true;
  }

  @override
  Future<bool> signIn() async {
    final gs = await _instance();
    try {
      final account = await gs.authenticate(scopeHint: GoogleSyncConfig.scopes);
      await account.authorizationClient
          .authorizeScopes(GoogleSyncConfig.scopes);
      _account = account;
      return true;
    } on GoogleSignInException catch (e) {
      // Пользователь закрыл окно входа — не ошибка.
      if (e.code == GoogleSignInExceptionCode.canceled) return false;
      throw describeGoogleSignInError(e);
    }
  }

  @override
  Future<T> withClient<T>(Future<T> Function(http.Client client) action) async {
    final account = _account;
    if (account == null) throw StateError('Нет активной сессии Google');
    // Access-токен живёт ~1 час, поэтому берём свежий перед каждой синхронизацией.
    final authz = await account.authorizationClient
        .authorizationForScopes(GoogleSyncConfig.scopes);
    if (authz == null) throw StateError('Доступ к Google Drive отозван');
    final client = authz.authClient(scopes: GoogleSyncConfig.scopes);
    try {
      return await action(client);
    } finally {
      client.close();
    }
  }

  @override
  Future<void> signOut() async {
    _account = null;
    await (await _instance()).signOut();
  }
}
