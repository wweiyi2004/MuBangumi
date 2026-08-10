import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/widgets/turnstile_dialog.dart';

void main() {
  test('builds the official Turnstile verification URL', () {
    expect(turnstileVerificationUri.scheme, 'https');
    expect(turnstileVerificationUri.host, 'next.bgm.tv');
    expect(turnstileVerificationUri.path, '/p1/turnstile');
    expect(turnstileVerificationUri.queryParameters['theme'], 'auto');
    expect(
      turnstileVerificationUri.queryParameters['redirect_uri'],
      turnstileCallbackUri,
    );
  });

  test('extracts a token from the expected callback', () {
    expect(
      parseTurnstileCallbackToken(
        'bangumi://mubangumi/turnstile?token=verified%2Btoken',
      ),
      'verified+token',
    );
  });

  test('rejects unrelated and incomplete callbacks', () {
    expect(
      parseTurnstileCallbackToken(
        'bangumi://another-client/turnstile?token=verified-token',
      ),
      isNull,
    );
    expect(
      parseTurnstileCallbackToken('bangumi://mubangumi/turnstile'),
      isNull,
    );
  });
}
