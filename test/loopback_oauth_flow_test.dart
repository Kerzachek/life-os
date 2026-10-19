import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis_auth/auth_io.dart' as gauth;
import 'package:home_organizer/core/sync/loopback_oauth_flow.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final clientId = gauth.ClientId('test-id.apps.googleusercontent.com', 'sec');

  MockClient tokenClient({void Function(Map<String, String> body)? onBody}) {
    return MockClient((request) async {
      onBody?.call(request.bodyFields);
      return http.Response(
        jsonEncode({
          'access_token': 'at',
          'token_type': 'Bearer',
          'expires_in': 3600,
          'refresh_token': 'rt',
          'scope': 'scope-a',
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
  }

  test('сервер слушает 127.0.0.1, redirect_uri тоже, favicon не закрывает сервер',
      () async {
    Map<String, String>? exchange;
    late Uri authUri;

    final future = obtainCredentialsViaLoopback(
      clientId: clientId,
      scopes: const ['scope-a'],
      client: tokenClient(onBody: (b) => exchange = b),
      userPrompt: (url) {
        authUri = Uri.parse(url);
        // Имитируем браузер: сначала «лишний» запрос, затем настоящий callback.
        final redirect = Uri.parse(authUri.queryParameters['redirect_uri']!);
        final state = authUri.queryParameters['state']!;
        unawaited(() async {
          final http.Client browser = http.Client();
          try {
            final favicon = await browser.get(redirect.replace(path: '/favicon.ico'));
            expect(favicon.statusCode, 404);
            final ok = await browser.get(
              redirect.replace(queryParameters: {'code': 'abc', 'state': state}),
            );
            expect(ok.statusCode, 200);
          } finally {
            browser.close();
          }
        }());
      },
    );

    final credentials = await future.timeout(const Duration(seconds: 10));

    final redirect = Uri.parse(authUri.queryParameters['redirect_uri']!);
    expect(redirect.host, InternetAddress.loopbackIPv4.address);
    expect(redirect.port, greaterThan(0));
    expect(authUri.queryParameters['code_challenge_method'], 'S256');
    expect(credentials.refreshToken, 'rt');
    expect(exchange!['code'], 'abc');
    expect(exchange!['redirect_uri'], authUri.queryParameters['redirect_uri']);
    expect(
      codeChallengeFor(exchange!['code_verifier']!),
      authUri.queryParameters['code_challenge'],
    );
  });

  test('неверный state → ошибка, сервер закрывается', () async {
    late Uri redirect;
    final future = obtainCredentialsViaLoopback(
      clientId: clientId,
      scopes: const ['scope-a'],
      client: tokenClient(),
      userPrompt: (url) {
        redirect = Uri.parse(Uri.parse(url).queryParameters['redirect_uri']!);
        unawaited(http.get(
          redirect.replace(queryParameters: {'code': 'abc', 'state': 'bad'}),
        ));
      },
    );

    await expectLater(
      future,
      throwsA(isA<gauth.AuthorizationCallbackException>()),
    );
    await expectLater(
      Socket.connect(redirect.host, redirect.port),
      throwsA(isA<SocketException>()),
    );
  });

  test('таймаут ожидания входа', () async {
    await expectLater(
      obtainCredentialsViaLoopback(
        clientId: clientId,
        scopes: const ['scope-a'],
        client: tokenClient(),
        userPrompt: (_) {},
        timeout: const Duration(milliseconds: 200),
      ),
      throwsA(isA<TimeoutException>()),
    );
  });
}
