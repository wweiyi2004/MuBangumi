import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/auth/website_identity.dart';
import 'package:mubangumi/core/auth/website_session.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/screens/community_page.dart';
import 'package:mubangumi/screens/website_login_screen.dart';
import 'package:mubangumi/state/session_controller.dart';
import 'package:mubangumi/state/website_session_controller.dart';
import 'package:dio/dio.dart';
import 'package:mubangumi/core/network/pm_service.dart';
import 'package:mubangumi/models/pm_models.dart';

import 'support/pm_fixtures.dart';

const user = BangumiUser(
  id: 1,
  username: 'user1',
  nickname: 'User 1',
  avatarUrl: '',
);

class Store extends WebsiteSessionStore {
  WebsiteSessionSnapshot value = WebsiteSessionSnapshot(
    cookies: const [WebsiteCookie(name: 'chii_auth', value: 'test-login')],
    syncedAt: DateTime(2026),
  ).withVerifiedUser(1, at: DateTime(2026));
  bool failReads = false;
  @override
  Future<WebsiteSessionSnapshot?> read() async {
    if (failReads) throw StateError('storage temporarily locked');
    return value;
  }

  @override
  Future<void> write(WebsiteSessionSnapshot next) async => value = next;
}

class HomeProbe extends WebsiteIdentityProbe {
  int calls = 0;
  @override
  Future<int> verify(
    WebsiteSessionSnapshot snapshot,
    BangumiUser expected,
  ) async {
    calls++;
    return expected.id;
  }
}

void main() {
  test(
    'a challenged PM request records its actual GET recovery location',
    () async {
      final controller = WebsiteSessionController(Store(), probe: HomeProbe());
      addTearDown(controller.dispose);
      await controller.attachAccount(user);
      final dio = Dio(BaseOptions(baseUrl: 'https://bgm.tv'))
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (request, handler) => handler.resolve(
              Response<String>(
                requestOptions: request,
                statusCode: 403,
                data: '',
                headers: Headers.fromMap({
                  'cf-mitigated': ['challenge'],
                }),
              ),
            ),
          ),
        );
      final pm = PmService(dio: dio)
        ..onWebsiteSessionFailure = controller.reportFailure
        ..websiteSessionGuard = () => controller.requireVerifiedSession(user);
      addTearDown(pm.dispose);
      await expectLater(pm.loadInbox(), throwsA(isA<PmAuthException>()));
      expect(controller.state.recoveryUri?.path, '/pm/inbox.chii');
      expect(controller.state.status, WebsiteAccessStatus.challenge);
    },
  );

  test('recovery routes reject external and logout destinations', () {
    for (final url in [
      'https://evil.test/pm',
      'https://bgm.tv.evil.test/',
      'http://bgm.tv/',
      'https://bgm.tv/logout/abc',
      'https://me@bgm.tv/',
    ]) {
      expect(websiteRecoveryUri(Uri.parse(url)), isNull);
    }
    expect(
      websiteRecoveryUri(Uri.parse('https://bgm.tv/group/topic/42'))?.path,
      '/group/topic/42',
    );
  });

  test('browser capture rejects navigation and authentication changes', () async {
    final cookies = Store().value.cookies;
    Future<Object?> document(String _) async => jsonEncode({
      'url': 'https://bgm.tv/oauth/authorize',
      'readyState': 'interactive',
      'userAgent': 'Android-WebView/test',
      'html':
          '<div id="badgeUserPanel"><a class="avatar" href="/user/user1">User</a></div>',
    });
    final accepted = await WebsiteBrowserIdentity.capture(
      cookies: cookies,
      evaluate: document,
      recapture: () async => cookies,
      isCurrent: () => true,
    );
    expect(accepted?.identifierFor(Store().value), 'user1');
    expect(accepted?.userAgent, 'Android-WebView/test');
    expect(
      await WebsiteBrowserIdentity.capture(
        cookies: cookies,
        evaluate: document,
        recapture: () async => const [
          WebsiteCookie(name: 'chii_auth', value: 'changed'),
        ],
        isCurrent: () => true,
      ),
      isNull,
    );
    expect(
      await WebsiteBrowserIdentity.capture(
        cookies: cookies,
        evaluate: document,
        recapture: () async => cookies,
        isCurrent: () => false,
      ),
      isNull,
    );
  });
  test('same-clock renewals have different persisted request contexts', () {
    final snapshot = Store().value;
    final renewed = snapshot.withVerifiedUser(1, at: snapshot.verifiedAt);
    expect(renewed.requestKey, isNot(snapshot.requestKey));
    expect(
      WebsiteSessionSnapshot.fromJson(renewed.toJson()).requestKey,
      renewed.requestKey,
    );
  });
  test(
    'ordinary website requests recover after temporary secure-storage failure',
    () async {
      final store = Store()..failReads = true;
      final probe = HomeProbe();
      final controller = WebsiteSessionController(store, probe: probe);
      addTearDown(controller.dispose);
      await expectLater(
        controller.requireVerifiedSession(user),
        throwsA(isA<WebsiteAccessException>()),
      );
      store.failReads = false;
      final sessions = await Future.wait([
        controller.requireVerifiedSession(user),
        controller.requireVerifiedSession(user),
      ]);
      expect(sessions.every((s) => s.isVerifiedFor(1, DateTime.now())), true);
      expect(
        probe.calls,
        0,
        reason: 'Restoring a valid stored binding needs no homepage probe.',
      );
    },
  );

  testWidgets(
    'a successful homepage probe does not bypass explicit challenge recovery',
    (tester) async {
      final store = Store();
      final probe = HomeProbe();
      final controller = WebsiteSessionController(store, probe: probe);
      await controller.attachAccount(user);
      controller.reportFailure(
        WebsiteAccessStatus.challenge,
        controller.state.snapshot!.requestKey,
      );
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
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(WebsiteLoginScreen), findsOneWidget);
      expect(
        probe.calls,
        0,
        reason: 'The challenged route must be opened for the user to solve.',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final pendingDocument in ['challenge', 'loading', 'missing']) {
    testWidgets(
      'a $pendingDocument document cannot auto-complete login through a healthy homepage',
      (tester) async {
        if (!Platform.isWindows) return;
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        const prefix = 'io.jns.webview.win';
        var completed = 0;
        var solved = false;
        messenger.setMockMethodCallHandler(
          const MethodChannel(prefix),
          (call) async =>
              call.method == 'initialize' ? {'textureId': 91} : null,
        );
        messenger.setMockMethodCallHandler(
          const MethodChannel('$prefix/91/events'),
          (_) async => null,
        );
        messenger.setMockMethodCallHandler(const MethodChannel('$prefix/91'), (
          call,
        ) async {
          if (call.method == 'getCookies') {
            return [
              {
                'name': 'chii_auth',
                'value': 'test-login',
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
            if (!solved && pendingDocument == 'missing') return null;
            return jsonEncode(
              jsonEncode({
                'url': 'https://bgm.tv/pm',
                'readyState': !solved && pendingDocument == 'loading'
                    ? 'loading'
                    : 'complete',
                'userAgent': 'Android-WebView/test',
                'html': solved
                    ? '<div id="badgeUserPanel"><a class="avatar" href="/user/user1">User</a></div>'
                    : '<div id="challenge-form">Verify</div><title>Just a moment...</title>',
              }),
            );
          }
          return null;
        });
        addTearDown(() {
          for (final channel in [prefix, '$prefix/91/events', '$prefix/91']) {
            messenger.setMockMethodCallHandler(MethodChannel(channel), null);
          }
        });
        final store = Store();
        final controller = WebsiteSessionController(store, probe: HomeProbe());
        await controller.attachAccount(user);
        controller.reportFailure(
          WebsiteAccessStatus.challenge,
          controller.state.snapshot!.requestKey,
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sessionProvider.overrideWith((ref) => PmTestSession()),
              websiteSessionProvider.overrideWith((ref) => controller),
            ],
            child: MaterialApp(
              home: CommunityWebScreen(
                initialUrl: 'https://bgm.tv/pm',
                enableCookieCapture: true,
                showSectionSwitcher: false,
                onSessionSaved: () => completed++,
              ),
            ),
          ),
        );
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.pump(const Duration(seconds: 2));
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(
          completed,
          0,
          reason: 'Cookies alone must not dismiss an unsolved challenge.',
        );
        solved = true;
        await tester.pump(const Duration(seconds: 6));
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(completed, 1);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
