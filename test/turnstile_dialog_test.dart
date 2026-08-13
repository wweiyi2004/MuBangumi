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
    // Official /p1/turnstile only allows prefix-whitelisted URIs.
    // `bangumi://` is the generic prefix other clients also use.
    expect(Uri.parse(turnstileCallbackUri).scheme, 'bangumi');
    expect(turnstileCallbackUri.startsWith('bangumi://'), isTrue);
  });

  test('extracts a token from the official custom-scheme callback', () {
    expect(
      parseTurnstileCallbackToken(
        'bangumi://mubangumi/turnstile?token=verified%2Btoken',
      ),
      'verified+token',
    );
  });

  test('extracts a token from a JS-bridge payload', () {
    expect(
      parseTurnstileCallbackToken(
        '{"url":"bangumi://mubangumi/turnstile?token=bridge-token"}',
      ),
      'bridge-token',
    );
  });

  test('extracts a token posted from the Turnstile hidden input', () {
    expect(
      parseTurnstileCallbackToken('{"token":"dom-hidden-token"}'),
      'dom-hidden-token',
    );
  });

  test('rejects obviously incomplete tokens before they hit the API', () {
    expect(isPlausibleTurnstileToken(''), isFalse);
    expect(isPlausibleTurnstileToken('true'), isFalse);
    expect(isPlausibleTurnstileToken('null'), isFalse);
    expect(isPlausibleTurnstileToken('0.${'a' * 80}'), isTrue);
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
    expect(
      parseTurnstileCallbackToken('https://evil.example/phish?token=stolen'),
      isNull,
    );
    expect(
      parseTurnstileCallbackToken('https://next.bgm.tv/p1/turnstile'),
      isNull,
    );
  });
}
