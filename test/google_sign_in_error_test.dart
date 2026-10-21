import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:home_organizer/core/sync/sync_auth.dart';

void main() {
  test('28444 — подсказка про настройку Google Cloud', () {
    final failure = describeGoogleSignInError(const GoogleSignInException(
      code: GoogleSignInExceptionCode.unknownError,
      description: '[28444] Developer console is not set up correctly.',
    ));
    expect(failure.message, contains('SHA-1'));
    expect(failure.message, contains('28444'));
  });

  test('прочие ошибки — исходное описание', () {
    final failure = describeGoogleSignInError(const GoogleSignInException(
      code: GoogleSignInExceptionCode.interrupted,
      description: 'network',
    ));
    expect(failure.message, 'Не удалось войти в Google: network');
  });
}
