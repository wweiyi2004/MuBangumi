import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/auth/bangumi_oauth.dart';

void main() {
  group('OAuth callback validation', () {
    test('returns the authorization code for a matching state', () {
      final callback = Uri.parse(
        '${OAuthConfig.redirectUri}?code=one-time-code&state=expected',
      );

      expect(
        parseOAuthAuthorizationCallback(callback, expectedState: 'expected'),
        'one-time-code',
      );
    });

    test('rejects a callback with a mismatched state', () {
      final callback = Uri.parse(
        '${OAuthConfig.redirectUri}?code=one-time-code&state=unexpected',
      );

      expect(
        () => parseOAuthAuthorizationCallback(
          callback,
          expectedState: 'expected',
        ),
        throwsA(
          isA<BangumiOAuthException>().having(
            (error) => error.message,
            'message',
            contains('状态校验失败'),
          ),
        ),
      );
    });

    test('surfaces the provider error description', () {
      final callback = Uri.parse(
        '${OAuthConfig.redirectUri}?error=access_denied&'
        'error_description=${Uri.encodeQueryComponent('用户取消授权')}&state=expected',
      );

      expect(
        () => parseOAuthAuthorizationCallback(
          callback,
          expectedState: 'expected',
        ),
        throwsA(
          isA<BangumiOAuthException>()
              .having((error) => error.message, 'message', '用户取消授权')
              .having((error) => error.isCancelled, 'isCancelled', isTrue),
        ),
      );
    });
  });

  test('Android OAuth return URI matches the manifest route', () {
    expect(oauthAppReturnUri, 'mubangumi://oauth/complete');
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    expect(manifest, contains('android:scheme="mubangumi"'));
    expect(manifest, contains('android:host="oauth"'));
    expect(manifest, contains('android:path="/complete"'));
    expect(manifest, contains('CustomTabsService'));
  });

  test('closes the in-app browser after the local callback arrives', () async {
    var closed = 0;
    final oauth = BangumiOAuth(
      closeInAppBrowser: () async {
        closed += 1;
      },
      closeInAppBrowserOnCallback: true,
    );
    final authorize = oauth.authorize(
      const OAuthConfig(clientId: 'client', clientSecret: 'secret'),
      launchAuthorization: (uri, callback) async {
        final state = uri.queryParameters['state']!;
        final client = HttpClient();
        try {
          final request = await client.getUrl(
            Uri.parse('${OAuthConfig.redirectUri}?code=test-code&state=$state'),
          );
          final response = await request.close();
          await response.drain<void>();
        } finally {
          client.close(force: true);
        }
        return true;
      },
    );

    await expectLater(authorize, throwsA(isA<BangumiOAuthException>()));
    expect(closed, 1);
  });

  test('cancelAuthorization aborts an in-flight authorize wait', () async {
    final oauth = BangumiOAuth();
    // Bind may fail if port is taken; skip gracefully is not needed in CI
    // because authorize itself throws a clear SocketException message.
    final authorize = oauth.authorize(
      const OAuthConfig(clientId: 'client', clientSecret: 'secret'),
      launchAuthorization: (uri, callback) async {
        // Keep the launcher "open" so authorize is parked on the callback.
        unawaited(
          Future<void>.delayed(const Duration(milliseconds: 30), () {
            oauth.cancelAuthorization();
          }),
        );
        return true;
      },
    );

    await expectLater(
      authorize,
      throwsA(
        isA<BangumiOAuthException>()
            .having((error) => error.isCancelled, 'isCancelled', isTrue)
            .having((error) => error.message, 'message', contains('取消')),
      ),
    );
  });
}
