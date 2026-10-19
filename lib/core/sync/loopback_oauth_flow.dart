import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:googleapis_auth/auth_io.dart' as gauth;
import 'package:http/http.dart' as http;

/// OAuth 2.0 (PKCE) через loopback-сервер для десктопа.
///
/// Заменяет `clientViaUserConsent`, который слушает `'localhost'` и отдаёт
/// `redirect_uri=http://localhost:port`. На Windows `localhost` может
/// резолвиться в `::1`, а браузер — идти на `127.0.0.1` (или наоборот), из-за
/// чего после согласия в Google появляется `ERR_CONNECTION_REFUSED`.
///
/// Здесь сервер привязан строго к [InternetAddress.loopbackIPv4], а
/// `redirect_uri` содержит тот же адрес `127.0.0.1`. Сервер остаётся открытым
/// до прихода настоящего callback-а (запросы вроде `/favicon.ico` получают
/// 404), но не дольше [timeout].
Future<gauth.AccessCredentials> obtainCredentialsViaLoopback({
  required gauth.ClientId clientId,
  required List<String> scopes,
  required http.Client client,
  required void Function(String url) userPrompt,
  Duration timeout = const Duration(minutes: 5),
  gauth.AuthEndpoints authEndpoints = const gauth.GoogleAuthEndpoints(),
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  try {
    final redirectUri = 'http://${InternetAddress.loopbackIPv4.address}:'
        '${server.port}';
    final state = _randomState();
    final codeVerifier = _createCodeVerifier();

    final authUri = authEndpoints.authorizationEndpoint.replace(
      queryParameters: {
        'client_id': clientId.identifier,
        'response_type': 'code',
        'redirect_uri': redirectUri,
        'scope': scopes.join(' '),
        'code_challenge': codeChallengeFor(codeVerifier),
        'code_challenge_method': 'S256',
        'state': state,
      },
    );

    // Сервер уже слушает порт, поэтому открывать браузер можно безопасно.
    userPrompt(authUri.toString());

    final request = await _nextCallback(server).timeout(
      timeout,
      onTimeout: () => throw TimeoutException(
        'Время ожидания входа через Google истекло',
        timeout,
      ),
    );

    try {
      final params = request.uri.queryParameters;
      if (params['state'] != state) {
        throw const gauth.AuthorizationCallbackException(
          'Invalid response from server (state did not match).',
        );
      }
      final error = params['error'];
      if (error != null) {
        throw gauth.UserConsentException(
          'Error occurred while obtaining access credentials: $error',
        );
      }
      final code = params['code'];
      if (code == null || code.isEmpty) {
        throw const gauth.AuthorizationCallbackException(
          'Invalid response from server (no auth code transmitted).',
        );
      }

      final credentials = await gauth.obtainAccessCredentialsViaCodeExchange(
        client,
        clientId,
        code,
        redirectUrl: redirectUri,
        codeVerifier: codeVerifier,
        authEndpoints: authEndpoints,
      );

      await _respond(request, 200, _successPage);
      return credentials;
    } catch (_) {
      await _respond(request, 400, _failurePage).catchError((_) {});
      rethrow;
    }
  } finally {
    await server.close(force: true);
  }
}

/// S256 code challenge для [codeVerifier] (RFC 7636, без `=`-паддинга).
String codeChallengeFor(String codeVerifier) {
  final digest = sha256.convert(ascii.encode(codeVerifier)).bytes;
  return base64UrlEncode(digest).replaceAll('=', '');
}

/// Ждёт первый GET с `code` или `error`; остальные запросы отклоняет 404.
Future<HttpRequest> _nextCallback(HttpServer server) async {
  await for (final request in server) {
    final params = request.uri.queryParameters;
    final isCallback = request.method == 'GET' &&
        (params.containsKey('code') || params.containsKey('error'));
    if (isCallback) return request;
    await _respond(request, 404, '').catchError((_) {});
  }
  throw StateError('Loopback-сервер закрыт до получения ответа от Google');
}

Future<void> _respond(HttpRequest request, int status, String body) async {
  request.response
    ..statusCode = status
    ..headers.set('content-type', 'text/html; charset=UTF-8')
    ..write(body);
  await request.response.close();
}

const String _charset = '0123456789-._~'
    'abcdefghijklmnopqrstuvwxyz'
    'ABCDEFGHIJKLMNOPQRSTUVWXYZ';

String _createCodeVerifier() {
  final rnd = Random.secure();
  return List.generate(128, (_) => _charset[rnd.nextInt(_charset.length)])
      .join();
}

String _randomState() {
  final rnd = Random.secure();
  final bytes = List<int>.generate(24, (_) => rnd.nextInt(256));
  return base64UrlEncode(bytes).replaceAll('=', '');
}

const String _successPage = '''
<!DOCTYPE html>
<html>
  <head><meta charset="utf-8"><title>Вход выполнен</title></head>
  <body>
    <h2 style="text-align: center">Вход в Google выполнен</h2>
    <p style="text-align: center">Это окно можно закрыть и вернуться в приложение.</p>
  </body>
</html>''';

const String _failurePage = '''
<!DOCTYPE html>
<html>
  <head><meta charset="utf-8"><title>Ошибка входа</title></head>
  <body>
    <h2 style="text-align: center">Не удалось войти в Google</h2>
    <p style="text-align: center">Закройте окно и попробуйте ещё раз в приложении.</p>
  </body>
</html>''';
