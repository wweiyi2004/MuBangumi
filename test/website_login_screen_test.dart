import 'package:mubangumi/navigation/app_destination.dart';
import 'package:mubangumi/navigation/app_router.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:mubangumi/core/auth/website_identity.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/auth/website_session.dart';
import 'package:mubangumi/screens/website_login_screen.dart';
import 'package:mubangumi/screens/community_page.dart';
import 'package:mubangumi/state/session_controller.dart';
import 'package:mubangumi/state/website_session_controller.dart';
import 'support/pm_fixtures.dart';

class _ExpiredSession extends WebsiteSessionController {
  _ExpiredSession() : super(PmTestWebsiteStore());
  @override
  Future<void> reload() async {
    state = const WebsiteSessionState(
      ready: true,
      status: WebsiteAccessStatus.expired,
      message: '网页登录已过期，请补充验证',
    );
  }
}

class _LoginStore extends WebsiteSessionStore {
  WebsiteSessionSnapshot? value;
  int writes = 0;
  @override
  Future<WebsiteSessionSnapshot?> read() async => value;
  @override
  Future<void> write(WebsiteSessionSnapshot snapshot) async {
    value = snapshot;
    writes++;
  }
}

class _LoginProbe extends WebsiteIdentityProbe {
  _LoginProbe({this.failOnce = false});
  final bool failOnce;
  int calls = 0;
  @override
  Future<int> verify(
    WebsiteSessionSnapshot snapshot,
    BangumiUser expected,
  ) async {
    if (calls++ == 0 && failOnce) {
      throw const WebsiteAccessException(
        WebsiteAccessStatus.unavailable,
        'temporary failure',
      );
    }
    return expected.id;
  }
}

class _OfflineProbe extends WebsiteIdentityProbe {
  @override
  Future<int> verify(
    WebsiteSessionSnapshot snapshot,
    BangumiUser expected,
  ) async => throw const WebsiteAccessException(
    WebsiteAccessStatus.unavailable,
    '网络暂不可用，已保留登录',
  );
}

class _RejectingProbe extends WebsiteIdentityProbe {
  int calls = 0;
  @override
  Future<int> verify(
    WebsiteSessionSnapshot snapshot,
    BangumiUser expected,
  ) async {
    calls++;
    throw const WebsiteAccessException(WebsiteAccessStatus.expired, 'expired');
  }
}

class _UnavailableStore extends _LoginStore {
  @override
  Future<WebsiteSessionSnapshot?> read() async =>
      throw StateError('storage temporarily unavailable');
}

void main() {
  testWidgets(
    'expired repair opens immediately even when native initialization stalls',
    (tester) async {
      if (!Platform.isWindows) return;
      const prefix = 'io.jns.webview.win';
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final initializing = Completer<Map<String, dynamic>>();
      var initializations = 0;
      final calls = <String>[];
      final store = _LoginStore()
        ..value = WebsiteSessionSnapshot(
          cookies: const [WebsiteCookie(name: 'chii_auth', value: 'old')],
          syncedAt: DateTime.now(),
        ).withVerifiedUser(1);
      final probe = _RejectingProbe();
      final controller = WebsiteSessionController(store, probe: probe);
      await controller.attachAccount(
        const BangumiUser(
          id: 1,
          username: 'user1',
          nickname: 'User 1',
          avatarUrl: '',
        ),
      );
      controller.reportFailure(
        WebsiteAccessStatus.expired,
        controller.state.snapshot!.requestKey,
      );
      messenger.setMockMethodCallHandler(const MethodChannel(prefix), (
        call,
      ) async {
        if (call.method == 'initialize') {
          initializations++;
          if (initializations == 1) {
            final reply = await initializing.future;
            calls.add('reply:72');
            return reply;
          }
          return {'textureId': 73};
        }
        calls.add('${call.method}:${call.arguments}');
        return null;
      });
      for (final id in [72, 73]) {
        messenger.setMockMethodCallHandler(
          MethodChannel('$prefix/$id/events'),
          (call) async {
            calls.add('$id:${call.method}');
            return null;
          },
        );
        messenger.setMockMethodCallHandler(MethodChannel('$prefix/$id'), (
          call,
        ) async {
          calls.add('$id:${call.method}');
          if (call.method == 'getCookies') return <Object>[];
          return null;
        });
      }
      addTearDown(() {
        for (final name in [
          prefix,
          '$prefix/72',
          '$prefix/72/events',
          '$prefix/73',
          '$prefix/73/events',
        ]) {
          messenger.setMockMethodCallHandler(MethodChannel(name), null);
        }
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionProvider.overrideWith((ref) => PmTestSession()),
            websiteSessionStoreProvider.overrideWithValue(store),
            websiteSessionProvider.overrideWith((ref) => controller),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => openWebsiteLoginScreen(context),
                  child: const Text('repair'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('repair'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(WebsiteLoginScreen), findsOneWidget);
      expect(
        probe.calls,
        0,
        reason: 'Interactive repair must not wait for HTTP.',
      );
      expect(
        initializations,
        1,
        reason: 'Only the visible browser is created.',
      );
      expect(
        tester
            .widget<CommunityWebScreen>(find.byType(CommunityWebScreen))
            .seedCookies,
        isEmpty,
      );
      await tester.pump(const Duration(seconds: 16));
      expect(find.textContaining('启动超时'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      await tester.tap(find.text('重试'));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(initializations, 2);
      expect(calls, contains('73:loadUrl'));
      expect(find.textContaining('启动超时'), findsNothing);
      initializing.complete({'textureId': 72});
      for (var i = 0; i < 10 && !calls.contains('dispose:72'); i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      // EventChannel cancellation also needs the real platform message queue.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      expect(calls, contains('dispose:72'));
      expect(
        calls,
        isNot(contains('72:loadUrl')),
        reason: 'A late native initialization must not navigate after timeout.',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
  for (final documentState in ['complete', 'interactive', 'loading']) {
    testWidgets(
      'visible WebView account verification respects document readiness: $documentState',
      (tester) async {
        if (!Platform.isWindows) return;
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        const prefix = 'io.jns.webview.win';
        var saved = 0;
        messenger.setMockMethodCallHandler(
          const MethodChannel(prefix),
          (call) async =>
              call.method == 'initialize' ? {'textureId': 78} : null,
        );
        messenger.setMockMethodCallHandler(
          const MethodChannel('$prefix/78/events'),
          (_) async => null,
        );
        messenger.setMockMethodCallHandler(const MethodChannel('$prefix/78'), (
          call,
        ) async {
          if (call.method == 'getCookies') {
            return [
              {
                'name': 'chii_auth',
                'value': 'browser-auth',
                'domain': '.bgm.tv',
                'path': '/',
                'expires': -1.0,
                'isSecure': true,
                'isHttpOnly': true,
                'sameSite': 1,
              },
            ];
          }
          if (call.method == 'executeScript') {
            return jsonEncode(
              jsonEncode({
                'url': 'https://bgm.tv/',
                'readyState': documentState,
                'userAgent': 'Mozilla/5.0 Test-Browser',
                'html':
                    '<div id="badgeUserPanel"><a class="avatar" href="/user/1"></a></div>',
              }),
            );
          }
          return null;
        });
        addTearDown(() {
          for (final name in [prefix, '$prefix/78/events', '$prefix/78']) {
            messenger.setMockMethodCallHandler(MethodChannel(name), null);
          }
        });
        final store = _LoginStore();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sessionProvider.overrideWith((ref) => PmTestSession()),
              websiteSessionProvider.overrideWith(
                (ref) =>
                    WebsiteSessionController(store, probe: _OfflineProbe()),
              ),
            ],
            child: MaterialApp(
              home: CommunityWebScreen(
                initialUrl: WebsiteLoginScreen.loginUrl,
                enableCookieCapture: true,
                showSectionSwitcher: false,
                onSessionSaved: () => saved++,
              ),
            ),
          ),
        );
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        for (final event in [
          {'type': 'urlChanged', 'value': 'https://bgm.tv/'},
          {
            'type': 'loadingStateChanged',
            'value': documentState == 'complete' ? 2 : 1,
          },
        ]) {
          await messenger.handlePlatformMessage(
            '$prefix/78/events',
            const StandardMethodCodec().encodeSuccessEnvelope(event),
            (_) {},
          );
          await tester.pump();
        }
        await tester.pump(const Duration(seconds: 2));
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(saved, documentState == 'loading' ? 0 : 1);
        expect(
          store.value?.verifiedUserId,
          documentState == 'loading' ? null : 1,
        );
        if (documentState != 'loading') {
          expect(store.value?.userAgent, 'Mozilla/5.0 Test-Browser');
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  }
  for (final diskFailure in [false, true]) {
    testWidgets(
      'temporary ${diskFailure ? 'storage' : 'network'} failure never pushes supplemental login',
      (tester) async {
        final store = diskFailure ? _UnavailableStore() : _LoginStore();
        final saved = WebsiteSessionSnapshot(
          cookies: const [WebsiteCookie(name: 'chii_auth', value: 'preserved')],
          syncedAt: DateTime.now(),
        );
        store.value = saved;
        bool? result;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sessionProvider.overrideWith((ref) => PmTestSession()),
              websiteSessionStoreProvider.overrideWithValue(store),
              websiteIdentityProbeProvider.overrideWith(
                (ref) => _OfflineProbe(),
              ),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () async {
                      result = await ensureWebsiteAccess(
                        context,
                        retryVerification: true,
                      );
                    },
                    child: const Text('打开私信'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('打开私信'));
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(result, false);
        expect(find.byType(WebsiteLoginScreen), findsNothing);
        expect(find.byType(CommunityWebScreen), findsNothing);
        expect(find.byType(SnackBar), findsOneWidget);
        expect(store.value, same(saved));
        expect(store.writes, 0);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  for (final failOnce in [false, true]) {
    testWidgets(
      'AJAX login recovers and is captured once (initial failure: $failOnce)',
      (tester) async {
        if (!Platform.isWindows) return;
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        const prefix = 'io.jns.webview.win';
        var loggedIn = false, saved = 0;
        final platformCalls = <String>[];
        messenger.setMockMethodCallHandler(
          const MethodChannel(prefix),
          (call) async =>
              call.method == 'initialize' ? {'textureId': 77} : null,
        );
        messenger.setMockMethodCallHandler(
          const MethodChannel('$prefix/77/events'),
          (_) async => null,
        );
        messenger.setMockMethodCallHandler(const MethodChannel('$prefix/77'), (
          call,
        ) async {
          platformCalls.add(call.method);
          if (call.method == 'getCookies') {
            return [
              if (loggedIn)
                {
                  'name': 'chii_auth',
                  'value': 'fresh%3D==',
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
        addTearDown(() {
          for (final name in [prefix, '$prefix/77/events', '$prefix/77']) {
            messenger.setMockMethodCallHandler(MethodChannel(name), null);
          }
        });
        final store = _LoginStore();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sessionProvider.overrideWith((ref) => PmTestSession()),
              websiteSessionProvider.overrideWith(
                (ref) => WebsiteSessionController(
                  store,
                  probe: _LoginProbe(failOnce: failOnce),
                ),
              ),
            ],
            child: MaterialApp(
              home: CommunityWebScreen(
                initialUrl: WebsiteLoginScreen.loginUrl,
                enableCookieCapture: true,
                showSectionSwitcher: false,
                onSessionSaved: () => saved++,
              ),
            ),
          ),
        );
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        loggedIn = true;
        await tester.pump(const Duration(seconds: 2));
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        if (failOnce) {
          expect(saved, 0);
          await tester.pump(const Duration(seconds: 6));
          for (var i = 0; i < 5; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
        }
        expect(
          saved,
          1,
          reason: 'Native calls: $platformCalls; writes: ${store.writes}',
        );
        expect(store.value?.verifiedUserId, 1);
        expect(store.value?.cookies.single.value, 'fresh%3D==');
        await tester.pump(const Duration(seconds: 4));
        expect(saved, 1);
        expect(store.writes, failOnce ? 2 : 1);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  }
  testWidgets(
    'manual account repair opens the website after a failed HTTP probe',
    (tester) async {
      final store = _LoginStore()
        ..value = WebsiteSessionSnapshot(
          cookies: const [WebsiteCookie(name: 'chii_auth', value: 'saved')],
          syncedAt: DateTime.now(),
        );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionProvider.overrideWith((ref) => PmTestSession()),
            websiteSessionStoreProvider.overrideWithValue(store),
            websiteIdentityProbeProvider.overrideWith((ref) => _OfflineProbe()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => openWebsiteLoginScreen(context),
                  child: const Text('补充验证'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('补充验证'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(WebsiteLoginScreen), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('expired login hint uses normal Material text on a phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionProvider.overrideWith((ref) => PmTestSession()),
          websiteSessionProvider.overrideWith((ref) => _ExpiredSession()),
        ],
        child: const MaterialApp(
          home: CommunityWebScreen(
            initialUrl: WebsiteLoginScreen.loginUrl,
            enableCookieCapture: true,
            showSectionSwitcher: false,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    final text = find.text('网页登录已过期，请补充验证');
    final style = tester.widget<Text>(text).style!;
    expect(style.fontSize, lessThanOrEqualTo(16));
    expect(style.decoration, isNot(TextDecoration.underline));
    expect(
      find.ancestor(of: text, matching: find.byType(Material)),
      findsWidgets,
    );
    expect(find.byTooltip('在浏览器中打开'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('fresh login never reinjects the rejected disk snapshot', (
    tester,
  ) async {
    var reads = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionProvider.overrideWith((ref) => PmTestSession()),
          websiteSessionProvider.overrideWith((ref) => _ExpiredSession()),
        ],
        child: MaterialApp(
          home: WebsiteLoginScreen(
            freshLogin: true,
            cookieLoader: () async {
              reads++;
              return const [
                WebsiteCookie(name: 'chii_auth', value: 'rejected-cookie'),
              ];
            },
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(reads, 0);
    expect(
      tester
          .widget<CommunityWebScreen>(find.byType(CommunityWebScreen))
          .seedCookies,
      isEmpty,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('cookie load failure shows retry instead of spinning forever', (
    tester,
  ) async {
    var calls = 0;
    Future<List<WebsiteCookie>> loadCookies() async {
      calls++;
      throw Exception('secure storage unavailable');
    }

    await tester.pumpWidget(
      ProviderScope(
        child: AppRouteScope(
          resolve: AppRouter.resolve,
          child: MaterialApp(
            home: WebsiteLoginScreen(cookieLoader: loadCookies),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('无法读取网站登录，请重试'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(calls, 2);
  });
}
