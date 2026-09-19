import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart'
    as windows;
import 'package:mubangumi/core/auth/website_session.dart';
import 'package:mubangumi/core/auth/website_cookie_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Android raw cookies preserve equals and encoded bytes through restore',
    () async {
      const channel = MethodChannel('mubangumi/website_cookies');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const raw = 'chii_auth=abc%2Fxyz%3D%3D; chii_sid=a=b==; theme=dark';
      final headers = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'readBgmCookies') return raw;
        if (call.method == 'setBgmCookie') {
          headers.add((call.arguments as Map)['header'] as String);
        }
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final cookies = await WebsiteCookieBridge.captureAndroidCookies();
      expect(cookies[0].value, 'abc%2Fxyz%3D%3D');
      expect(cookies[1].value, 'a=b==');
      await WebsiteCookieBridge.injectAndroidCookies(cookies);
      expect(
        headers[0],
        'chii_auth=abc%2Fxyz%3D%3D; Domain=.bgm.tv; Path=/; Secure',
      );
      expect(headers[1], 'chii_sid=a=b==; Domain=.bgm.tv; Path=/; Secure');
      expect(headers.join(), isNot(contains('%25')));
    },
  );

  test(
    'Android cookie bridge never injects unrelated domains or header separators',
    () async {
      const channel = MethodChannel('mubangumi/website_cookies');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final headers = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        headers.add((call.arguments as Map)['header'] as String);
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await WebsiteCookieBridge.injectAndroidCookies(const [
        WebsiteCookie(name: 'chii_auth', value: 'x', domain: 'notbgm.tv'),
        WebsiteCookie(name: 'chii_auth', value: 'x; Domain=bad'),
        WebsiteCookie(name: 'chii_auth', value: 'x', path: '/; HttpOnly'),
        WebsiteCookie(name: 'chii_auth', value: 'valid==', isHttpOnly: true),
      ]);
      expect(headers, [
        'chii_auth=valid==; Domain=.bgm.tv; Path=/; Secure; HttpOnly',
      ]);
    },
  );

  test('a new login waits for an older Windows cookie cleanup', () async {
    if (!Platform.isWindows) return;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const prefix = 'io.jns.webview.win';
    final cleanupReady = Completer<Map<String, dynamic>>();
    var initializations = 0;
    String? auth = 'old';
    messenger.setMockMethodCallHandler(const MethodChannel(prefix), (
      call,
    ) async {
      if (call.method == 'initialize') {
        initializations++;
        if (initializations == 1) return cleanupReady.future;
        return {'textureId': 2};
      }
      return null;
    });
    for (final id in [1, 2]) {
      messenger.setMockMethodCallHandler(
        MethodChannel('$prefix/$id/events'),
        (_) async => null,
      );
      messenger.setMockMethodCallHandler(MethodChannel('$prefix/$id'), (
        call,
      ) async {
        if (call.method == 'setCookie') {
          auth = (call.arguments as Map)['value'] as String;
        }
        if (call.method == 'deleteCookies') auth = null;
        if (call.method == 'getCookies') {
          return [
            if (auth != null)
              {
                'name': 'chii_auth',
                'value': auth,
                'domain': '.bgm.tv',
                'path': '/',
                'expires': -1.0,
                'isSecure': true,
                'isHttpOnly': true,
                'sameSite': 1,
              },
          ];
        }
        return null;
      });
    }
    addTearDown(() {
      messenger.setMockMethodCallHandler(const MethodChannel(prefix), null);
      for (final id in [1, 2]) {
        messenger.setMockMethodCallHandler(
          MethodChannel('$prefix/$id/events'),
          null,
        );
        messenger.setMockMethodCallHandler(MethodChannel('$prefix/$id'), null);
      }
    });
    await WebsiteCookieBridge.clearBgmCookies();
    await pumpEventQueue();
    final controller = windows.WebviewController();
    await controller.initialize();
    var injected = false;
    final seed = WebsiteCookieBridge.injectWindows(controller, const [
      WebsiteCookie(name: 'chii_auth', value: 'new'),
    ]).then((_) => injected = true);
    await pumpEventQueue();
    final injectedBeforeCleanup = injected;
    cleanupReady.complete({'textureId': 1});
    await pumpEventQueue();
    await seed;
    await controller.dispose();
    expect(injectedBeforeCleanup, isFalse);
    expect(auth, 'new');
  });

  test(
    'Windows cookie-cleanup failure logs a distinctive diagnostic prefix',
    () async {
      // WebView2 cleanup only exists on Windows; on other hosts the branch is
      // never taken and there is nothing to assert.
      if (!Platform.isWindows) return;

      final lines = <String>[];
      final previous = debugPrint;
      debugPrint = (message, {wrapWidth}) => lines.add(message ?? '');
      addTearDown(() => debugPrint = previous);

      await WebsiteCookieBridge.clearBgmCookies();
      await pumpEventQueue();

      expect(lines, anyElement(contains('[BGM-COOKIE-CLEANUP]')));
    },
  );

  test('detached best-effort cleanup does not wait for the task', () async {
    final gate = Completer<void>();
    var finished = false;

    WebsiteCookieBridge.runDetachedBestEffort(() async {
      await gate.future;
      finished = true;
    });

    // The caller has returned while the slow cleanup is still pending.
    expect(finished, isFalse);

    gate.complete();
    await pumpEventQueue();
    expect(finished, isTrue);
  });

  test(
    'detached best-effort cleanup reports failures through the handler',
    () async {
      final failures = <Object>[];

      WebsiteCookieBridge.runDetachedBestEffort(
        () async => throw StateError('boom'),
        onFailure: (error, stack) => failures.add(error),
      );
      await pumpEventQueue();

      expect(failures, hasLength(1));
      expect(failures.single, isA<StateError>());
    },
  );
}
