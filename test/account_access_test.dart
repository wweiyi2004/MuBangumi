import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mubangumi/core/auth/website_identity.dart';
import 'package:mubangumi/core/auth/website_session.dart';
import 'package:mubangumi/core/network/pm_service.dart';
import 'package:mubangumi/state/service_providers.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/models/pm_models.dart';
import 'package:mubangumi/state/account_access_controller.dart';
import 'package:mubangumi/state/website_session_controller.dart';
import 'package:mubangumi/state/session_controller.dart';
import 'support/pm_fixtures.dart';

const alice = BangumiUser(
  id: 1,
  username: 'alice',
  nickname: 'Alice',
  avatarUrl: '',
);
const bob = BangumiUser(id: 2, username: 'bob', nickname: 'Bob', avatarUrl: '');
WebsiteSessionSnapshot snapshot(String value, {int? legacyUser}) =>
    WebsiteSessionSnapshot(
      cookies: [WebsiteCookie(name: 'chii_auth', value: value)],
      syncedAt: DateTime.now(),
      verifiedUserId: legacyUser,
    );
String homepage(String name) =>
    '<div id="badgeUserPanel"><a class="avatar" href="/user/$name">user</a></div>';

void main() {
  test(
    'two provider scopes keep service instances and identity guards independent',
    () async {
      ProviderContainer scope(int id) {
        final session = PmTestSession()..switchUser(id);
        return ProviderContainer(
          overrides: [
            sessionProvider.overrideWith((_) => session),
            websiteSessionStoreProvider.overrideWithValue(
              _Store()..value = snapshot('cookie-$id', legacyUser: id),
            ),
            websiteIdentityProbeProvider.overrideWithValue(
              _Probe((_, user) async => user.id),
            ),
          ],
        );
      }

      final a = scope(1), b = scope(2);
      addTearDown(b.dispose);
      final accessA = a.read(accountAccessProvider),
          accessB = b.read(accountAccessProvider);
      expect(await accessA.verify(), true);
      expect(await accessB.verify(), true);
      expect(
        identical(a.read(pmServiceProvider), b.read(pmServiceProvider)),
        false,
      );
      expect(
        identical(
          a.read(communityServiceProvider),
          b.read(communityServiceProvider),
        ),
        false,
      );
      expect(
        (await a.read(pmServiceProvider).websiteSessionGuard!()).verifiedUserId,
        1,
      );
      a.dispose();
      expect(
        (await b.read(pmServiceProvider).websiteSessionGuard!()).verifiedUserId,
        2,
      );
    },
  );

  test(
    'application coordinator installs the same identity gate for website consumers',
    () async {
      final store = _Store()..value = snapshot('a');
      final session = PmTestSession();
      final container = ProviderContainer(
        overrides: [
          sessionProvider.overrideWith((ref) => session),
          websiteSessionStoreProvider.overrideWithValue(store),
          websiteIdentityProbeProvider.overrideWithValue(
            _Probe((_, user) async {
              if (user.id != 1) {
                throw const WebsiteAccessException(
                  WebsiteAccessStatus.mismatch,
                  '账号不一致',
                );
              }
              return 1;
            }),
          ),
        ],
      );
      addTearDown(container.dispose);
      final access = container.read(accountAccessProvider);
      expect(await access.verify(), isTrue);
      expect(
        (await container.read(pmServiceProvider).websiteSessionGuard!())
            .verifiedUserId,
        1,
      );
      session.switchUser(2);
      await Future<void>.delayed(Duration.zero);
      await expectLater(
        container.read(pmServiceProvider).websiteSessionGuard!(),
        throwsA(isA<WebsiteAccessException>()),
      );
      expect(session.state.phase, SessionPhase.signedIn);
      expect(session.state.user!.id, 2);
    },
  );
  test(
    'website identity is established only with Cookie, never the API Authorization',
    () async {
      final requests = <RequestOptions>[];
      final dio = Dio(
        BaseOptions(headers: {'Authorization': 'Bearer should-not-be-used'}),
      );
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) {
            requests.add(request);
            handler.resolve(
              Response(
                requestOptions: request,
                statusCode: 200,
                data: homepage('alice'),
              ),
            );
          },
        ),
      );
      expect(
        await WebsiteIdentityProbe(
          dio: dio,
        ).verify(snapshot('alice-cookie'), alice),
        1,
      );
      expect(requests.single.headers['Cookie'], 'chii_auth=alice-cookie');
      expect(
        requests.single.headers.keys.any(
          (key) => key.toLowerCase() == 'authorization',
        ),
        isFalse,
      );
      expect(requests.single.followRedirects, isFalse);
    },
  );

  test(
    'different website identity is resolved to a stable UID and rejected',
    () async {
      final requests = <RequestOptions>[];
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) {
            requests.add(request);
            handler.resolve(
              Response(
                requestOptions: request,
                statusCode: 200,
                data: request.uri.host == 'bgm.tv'
                    ? homepage('bob')
                    : {'id': 2},
              ),
            );
          },
        ),
      );
      await expectLater(
        WebsiteIdentityProbe(dio: dio).verify(snapshot('bob-cookie'), alice),
        throwsA(
          isA<WebsiteAccessException>().having(
            (error) => error.status,
            'status',
            WebsiteAccessStatus.mismatch,
          ),
        ),
      );
      expect(requests, hasLength(2));
      expect(requests.last.headers['Cookie'], isNull);
      expect(requests.last.uri.host, 'api.bgm.tv');
    },
  );

  test('verified account navigation wins over an embedded login panel', () async {
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) {
            handler.resolve(
              Response(
                requestOptions: request,
                statusCode: 200,
                data:
                    '${homepage('alice')}<form id="loginForm"><input name="password"></form>',
              ),
            );
          },
        ),
      );
    expect(
      await WebsiteIdentityProbe(dio: dio).verify(snapshot('valid'), alice),
      1,
    );
  });

  for (final (html, code, status) in [
    (
      '<form id="loginForm"><input name="password"></form>',
      200,
      WebsiteAccessStatus.expired,
    ),
    ('<div class="guest">登录</div>', 200, WebsiteAccessStatus.expired),
    (
      '<script src="/cdn-cgi/challenge-platform/test"></script>',
      403,
      WebsiteAccessStatus.challenge,
    ),
    ('gateway error', 502, WebsiteAccessStatus.unavailable),
  ]) {
    test(
      'website probe classifies $status without revoking the API login',
      () async {
        final dio = Dio()
          ..interceptors.add(
            InterceptorsWrapper(
              onRequest: (request, handler) => handler.resolve(
                Response(requestOptions: request, statusCode: code, data: html),
              ),
            ),
          );
        await expectLater(
          WebsiteIdentityProbe(dio: dio).verify(snapshot('cookie'), alice),
          throwsA(
            isA<WebsiteAccessException>().having(
              (error) => error.status,
              'status',
              status,
            ),
          ),
        );
      },
    );
  }

  test(
    'theme and challenge cookies are not treated as an authenticated session',
    () {
      final value = WebsiteSessionSnapshot(
        cookies: const [
          WebsiteCookie(name: 'chii_theme', value: 'pink'),
          WebsiteCookie(name: 'cf_clearance', value: 'ok'),
          WebsiteCookie(name: 'auth_token', value: 'unknown'),
        ],
        syncedAt: DateTime.now(),
      );
      expect(value.hasSessionCookies, isFalse);
      expect(
        WebsiteSessionSnapshot(
          cookies: const [
            WebsiteCookie(
              name: 'chii_auth',
              value: 'x',
              domain: 'evil.example',
            ),
          ],
          syncedAt: DateTime.now(),
        ).hasSessionCookies,
        isFalse,
      );
    },
  );

  test(
    'saved legacy identity must be probed and concurrent checks merge',
    () async {
      final store = _Store()..value = snapshot('a', legacyUser: 1);
      final gate = Completer<int>();
      final probe = _Probe((_, _) => gate.future);
      final controller = WebsiteSessionController(store, probe: probe);
      addTearDown(controller.dispose);
      await controller.reload();
      expect(controller.state.isSynced, isFalse);
      final attached = controller.attachAccount(alice);
      await until(() => probe.calls == 1);
      final first = controller.ensureVerified();
      final second = controller.ensureVerified();
      expect(probe.calls, 1);
      gate.complete(1);
      await attached;
      expect(await first, isTrue);
      expect(await second, isTrue);
      expect(controller.state.isSynced, isTrue);
      expect(store.value!.verificationVersion, 2);
      expect(store.value!.verifiedAt, isNotNull);
    },
  );

  test(
    'incorrect replacement Cookie never overwrites the verified saved session',
    () async {
      final store = _Store()..value = snapshot('a');
      final probe = _Probe((value, user) async {
        if (value.authenticationKey != 'chii_auth=a') {
          throw const WebsiteAccessException(
            WebsiteAccessStatus.mismatch,
            '账号不一致',
          );
        }
        return user.id;
      });
      final controller = WebsiteSessionController(store, probe: probe);
      addTearDown(controller.dispose);
      await controller.attachAccount(alice);
      expect(controller.state.isSynced, isTrue);
      expect(
        await controller.saveCookies(const [
          WebsiteCookie(name: 'chii_auth', value: 'b'),
        ]),
        isFalse,
      );
      expect(store.value!.authenticationKey, 'chii_auth=a');
      expect(controller.state.status, WebsiteAccessStatus.mismatch);
      expect(await controller.ensureVerified(), isFalse);
    },
  );

  test(
    'temporary verification failure keeps Cookie and current account',
    () async {
      final store = _Store()..value = snapshot('a');
      final controller = WebsiteSessionController(
        store,
        probe: _Probe((_, _) async {
          throw const WebsiteAccessException(
            WebsiteAccessStatus.unavailable,
            'offline',
          );
        }),
      );
      addTearDown(controller.dispose);
      await controller.attachAccount(alice);
      expect(controller.state.status, WebsiteAccessStatus.unavailable);
      expect(store.value!.authenticationKey, 'chii_auth=a');
      expect(controller.state.hasStoredSession, isTrue);
      expect(controller.state.isSynced, isFalse);
    },
  );

  test('late verification cannot restore cleared login', () async {
    final store = _Store()..value = snapshot('a');
    final gate = Completer<int>();
    final probe = _Probe((_, _) => gate.future);
    final controller = WebsiteSessionController(store, probe: probe);
    addTearDown(controller.dispose);
    final pending = controller.attachAccount(alice);
    await until(() => probe.calls == 1);
    await controller.markCleared();
    gate.complete(1);
    await pending;
    expect(store.value, isNull);
    expect(controller.state.isSynced, isFalse);
  });

  test('late old-account verification cannot replace a new login', () async {
    final store = _Store()..value = snapshot('a');
    final gate = Completer<int>();
    final probe = _Probe(
      (_, user) => user.id == 1 ? gate.future : Future.value(2),
    );
    final controller = WebsiteSessionController(store, probe: probe);
    addTearDown(controller.dispose);
    final pending = controller.attachAccount(alice);
    await until(() => probe.calls == 1);
    store.value = snapshot('b');
    await controller.attachAccount(bob);
    gate.complete(1);
    await pending;
    expect(store.value!.verifiedUserId, 2);
    expect(store.value!.authenticationKey, 'chii_auth=b');
  });

  test(
    'supplemental login is deduplicated and cannot finish for another account',
    () async {
      final store = _Store()..value = snapshot('a');
      final controller = WebsiteSessionController(
        store,
        probe: _Probe((_, user) async => user.id),
      );
      addTearDown(controller.dispose);
      BangumiUser current = alice;
      final access = AccountAccessController(
        website: controller,
        currentUser: () => current,
      );
      addTearDown(access.dispose);
      access.accountChanged(alice);
      await access.verify();
      final gate = Completer<bool>();
      var opened = 0;
      Future<bool> open() {
        opened++;
        return gate.future;
      }

      final a = access.runLogin(open);
      final b = access.runLogin(open);
      expect(opened, 1);
      current = bob;
      access.accountChanged(bob);
      gate.complete(true);
      expect(await a, isFalse);
      expect(await b, isFalse);
    },
  );

  test(
    'PM account guard stops network access before reading another account',
    () async {
      var requests = 0;
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (request, handler) {
              requests++;
              handler.resolve(
                Response(requestOptions: request, data: '', statusCode: 200),
              );
            },
          ),
        );
      final service =
          PmService(dio: dio, sessionStore: _Store()..value = snapshot('a'))
            ..websiteSessionGuard = () async =>
                throw const WebsiteAccessException(
                  WebsiteAccessStatus.mismatch,
                  '账号不一致',
                );
      await expectLater(service.loadInbox(), throwsA(isA<PmAuthException>()));
      expect(requests, 0);
    },
  );
}

Future<void> until(bool Function() test) async {
  for (var i = 0; i < 100; i++) {
    if (test()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('condition not reached');
}

class _Store extends WebsiteSessionStore {
  WebsiteSessionSnapshot? value;
  @override
  Future<WebsiteSessionSnapshot?> read() async => value;
  @override
  Future<void> write(WebsiteSessionSnapshot value) async {
    this.value = value;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

class _Probe extends WebsiteIdentityProbe {
  _Probe(this.respond);
  final Future<int> Function(WebsiteSessionSnapshot value, BangumiUser expected)
  respond;
  int calls = 0;
  @override
  Future<int> verify(WebsiteSessionSnapshot snapshot, BangumiUser expected) {
    calls++;
    return respond(snapshot, expected);
  }
}
