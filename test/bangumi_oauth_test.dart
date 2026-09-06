import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
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

  test(
    'embedded redirect completes OAuth without loading HTTP in the WebView',
    () async {
      final oauth = BangumiOAuth(
        dio: Dio()..httpClientAdapter = _TokenAdapter(),
      );
      Uri? accepted;
      final tokens = await oauth.authorize(
        const OAuthConfig(clientId: 'client', clientSecret: 'secret'),
        launchAuthorization: (uri, callback) async {
          final state = uri.queryParameters['state']!;
          final valid = Uri.parse(
            '${OAuthConfig.redirectUri}?code=embedded-code&state=$state',
          );
          expect(
            oauth.acceptEmbeddedRedirect(valid.replace(host: 'example.com')),
            isFalse,
          );
          expect(
            oauth.acceptEmbeddedRedirect(valid.replace(path: '/unrelated')),
            isFalse,
          );
          expect(
            oauth.acceptEmbeddedRedirect(
              valid.replace(query: 'code=x&state=old'),
            ),
            isFalse,
          );
          expect(oauth.acceptEmbeddedRedirect(valid), isTrue);
          expect(oauth.acceptEmbeddedRedirect(valid), isFalse);
          expect(await callback, valid);
          accepted = valid;
          return true;
        },
      );
      expect(tokens.accessToken, 'verified-token');
      expect(oauth.acceptEmbeddedRedirect(accepted!), isFalse);
    },
  );

  test('cancelled authorization rejects a late embedded redirect', () async {
    final oauth = BangumiOAuth();
    final result = oauth.authorize(
      const OAuthConfig(clientId: 'client', clientSecret: 'secret'),
      launchAuthorization: (uri, callback) async {
        final state = uri.queryParameters['state']!;
        await oauth.cancelAuthorization();
        expect(
          oauth.acceptEmbeddedRedirect(
            Uri.parse('${OAuthConfig.redirectUri}?code=late&state=$state'),
          ),
          isFalse,
        );
        return true;
      },
    );
    await expectLater(result, throwsA(_cancelled));
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
      dio: Dio()..httpClientAdapter = _TokenAdapter(),
      closeInAppBrowser: () async {
        closed += 1;
      },
      closeInAppBrowserOnCallback: true,
    );
    final authorize = oauth.authorize(
      const OAuthConfig(clientId: 'client', clientSecret: 'secret'),
      launchAuthorization: _sendCallback,
    );

    expect((await authorize).accessToken, 'verified-token');
    expect(closed, 1);
  });

  test('cancelling during server bind releases the callback port', () async {
    final oauth = BangumiOAuth();
    var launched = false;
    final authorize = oauth.authorize(
      const OAuthConfig(clientId: 'client', clientSecret: 'secret'),
      launchAuthorization: (_, _) async {
        launched = true;
        return true;
      },
    );
    final result = expectLater(authorize, throwsA(_cancelled));
    await oauth.cancelAuthorization();
    await result;
    expect(launched, isFalse);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 43927);
    await server.close(force: true);
  });

  test('cancelling token exchange permits a new authorization', () async {
    final adapter = _TokenAdapter(blockFirst: true);
    final oauth = BangumiOAuth(dio: Dio()..httpClientAdapter = adapter);
    const config = OAuthConfig(clientId: 'client', clientSecret: 'secret');
    final authorize = oauth.authorize(
      config,
      launchAuthorization: _sendCallback,
    );
    final result = expectLater(authorize, throwsA(_cancelled));
    await adapter.started.future;
    await oauth.cancelAuthorization();
    await result;
    final tokens = await oauth.authorize(
      config,
      launchAuthorization: _sendCallback,
    );
    expect(tokens.accessToken, 'verified-token');
    expect(adapter.calls, 2);
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

final _cancelled = isA<BangumiOAuthException>().having(
  (error) => error.isCancelled,
  'isCancelled',
  isTrue,
);

Future<bool> _sendCallback(Uri uri, Future<Uri> callback) async {
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
}

class _TokenAdapter implements HttpClientAdapter {
  _TokenAdapter({this.blockFirst = false});
  final bool blockFirst;
  final started = Completer<void>();
  var calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    if (!started.isCompleted) started.complete();
    if (blockFirst && calls == 1) {
      await cancelFuture;
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.cancel,
      );
    }
    return ResponseBody.fromString(
      '{"access_token":"verified-token","refresh_token":"refresh-token","expires_in":3600}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
