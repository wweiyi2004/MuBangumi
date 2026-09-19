import 'package:mubangumi/navigation/app_destination.dart';
import 'package:mubangumi/navigation/app_router.dart';
import 'package:flutter/material.dart';
import 'dart:io';
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
  @override
  Future<int> verify(
    WebsiteSessionSnapshot snapshot,
    BangumiUser expected,
  ) async => expected.id;
}

void main() {
  testWidgets(
    'AJAX login is captured once without a page-finished navigation',
    (tester) async {
      if (!Platform.isWindows) return;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const prefix = 'io.jns.webview.win';
      var loggedIn = false, saved = 0;
      messenger.setMockMethodCallHandler(
        const MethodChannel(prefix),
        (call) async => call.method == 'initialize' ? {'textureId': 77} : null,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('$prefix/77/events'),
        (_) async => null,
      );
      messenger.setMockMethodCallHandler(const MethodChannel('$prefix/77'), (
        call,
      ) async {
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
              (ref) => WebsiteSessionController(store, probe: _LoginProbe()),
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
      expect(saved, 1);
      expect(store.value?.verifiedUserId, 1);
      expect(store.value?.cookies.single.value, 'fresh%3D==');
      await tester.pump(const Duration(seconds: 4));
      expect(saved, 1);
      expect(store.writes, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
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
