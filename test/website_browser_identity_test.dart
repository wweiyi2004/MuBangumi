import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/auth/website_identity.dart';
import 'package:mubangumi/core/auth/website_session.dart';
import 'package:mubangumi/core/network/pm_service.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/state/website_session_controller.dart';

const alice = BangumiUser(
  id: 1,
  username: 'alice',
  nickname: 'Alice',
  avatarUrl: '',
);
const cookies = [WebsiteCookie(name: 'chii_auth', value: 'test-auth')];
const browserAgent = 'Mozilla/5.0 Test-WebView/1.0';
WebsiteBrowserIdentity evidence({
  String owner = 'alice',
  String url = 'https://bgm.tv/',
  String key = 'chii_auth=test-auth',
  String? html,
}) => WebsiteBrowserIdentity(
  url: url,
  authenticationKey: key,
  userAgent: browserAgent,
  html:
      html ??
      '<div id="badgeUserPanel"><a class="avatar" href="/user/$owner">avatar</a></div>',
);

class Store extends WebsiteSessionStore {
  WebsiteSessionSnapshot? value;
  @override
  Future<WebsiteSessionSnapshot?> read() async => value;
  @override
  Future<void> write(WebsiteSessionSnapshot snapshot) async {
    value = snapshot;
  }
}

class ChallengeProbe extends WebsiteIdentityProbe {
  int calls = 0;
  WebsiteAccessStatus status = WebsiteAccessStatus.challenge;
  bool recovered = false;
  @override
  Future<int> verify(
    WebsiteSessionSnapshot snapshot,
    BangumiUser expected,
  ) async {
    calls++;
    if (recovered) return expected.id;
    throw WebsiteAccessException(status, 'HTTP probe failed');
  }
}

void main() {
  test(
    'logged-in WebView establishes owner even when independent HTTP probe is challenged',
    () async {
      final store = Store();
      final probe = ChallengeProbe();
      final controller = WebsiteSessionController(store, probe: probe);
      addTearDown(controller.dispose);
      await controller.attachAccount(alice);
      expect(
        await controller.saveCookies(cookies, browserIdentity: evidence()),
        isTrue,
      );
      expect(controller.state.isSynced, isTrue);
      expect(store.value!.verifiedUserId, 1);
      expect(store.value!.requestHeaders['User-Agent'], browserAgent);
      expect(await controller.ensureVerified(), isTrue);
      expect(probe.calls, 0);
      final restarted = WebsiteSessionController(store, probe: probe);
      addTearDown(restarted.dispose);
      await restarted.attachAccount(alice);
      expect(await restarted.requireVerifiedSession(alice), isNotNull);
      expect(probe.calls, 0);
    },
  );

  test(
    'different browser account is rejected even when cookies had a cached binding',
    () async {
      final store = Store()
        ..value = WebsiteSessionSnapshot(
          cookies: cookies,
          syncedAt: DateTime.now(),
        ).withVerifiedUser(1);
      final controller = WebsiteSessionController(
        store,
        probe: ChallengeProbe(),
      );
      addTearDown(controller.dispose);
      await controller.attachAccount(alice);
      final original = store.value;
      expect(
        await controller.saveCookies(
          cookies,
          browserIdentity: evidence(owner: '2'),
        ),
        isFalse,
      );
      expect(controller.state.status, WebsiteAccessStatus.mismatch);
      expect(store.value, same(original));
    },
  );

  for (final invalid in [
    evidence(url: 'https://evil.test/'),
    evidence(url: 'https://bgm.tv.evil.test/'),
    evidence(key: 'chii_auth=other'),
    evidence(url: 'http://bgm.tv/'),
    evidence(
      html:
          '<article><a class="avatar" href="/user/alice">author</a></article>',
    ),
  ]) {
    test(
      'untrusted origin, changed cookies or content author cannot establish identity: ${invalid.url}/${invalid.authenticationKey}',
      () async {
        final store = Store();
        final probe = ChallengeProbe();
        final controller = WebsiteSessionController(store, probe: probe);
        addTearDown(controller.dispose);
        await controller.attachAccount(alice);
        expect(
          await controller.saveCookies(cookies, browserIdentity: invalid),
          isFalse,
        );
        expect(controller.state.isSynced, isFalse);
        expect(probe.calls, 1);
        expect(store.value, isNull);
      },
    );
  }

  test(
    'temporary verification failure persists pending cookies without claiming an owner',
    () async {
      final store = Store();
      final probe = ChallengeProbe()..status = WebsiteAccessStatus.unavailable;
      final controller = WebsiteSessionController(store, probe: probe);
      await controller.attachAccount(alice);
      expect(await controller.saveCookies(cookies), isFalse);
      expect(store.value!.authenticationKey, 'chii_auth=test-auth');
      expect(store.value!.verifiedUserId, isNull);
      controller.dispose();
      probe.recovered = true;
      final restarted = WebsiteSessionController(store, probe: probe);
      addTearDown(restarted.dispose);
      await restarted.attachAccount(alice);
      expect(await restarted.ensureVerified(), isTrue);
    },
  );

  test('numeric canonical username is not mistaken for another UID', () async {
    const numericUser = BangumiUser(
      id: 1,
      username: '123456',
      nickname: '',
      avatarUrl: '',
    );
    expect(
      await WebsiteIdentityProbe().verifyIdentifier('123456', numericUser),
      1,
    );
  });

  test('browser user agent survives storage and verification copies', () {
    final original = WebsiteSessionSnapshot(
      cookies: cookies,
      syncedAt: DateTime.now(),
      userAgent: browserAgent,
    );
    final restored = WebsiteSessionSnapshot.fromJson(
      original.withVerifiedUser(1).toJson(),
    ).withoutVerification();
    expect(restored.requestHeaders, {
      'Cookie': 'chii_auth=test-auth',
      'User-Agent': browserAgent,
    });
    final invalid = WebsiteSessionSnapshot(
      cookies: cookies,
      syncedAt: DateTime.now(),
      userAgent: 'agent\r\nInjected: value',
    );
    expect(invalid.requestHeaders.containsKey('User-Agent'), isFalse);
  });

  test(
    'PM requests retain the user agent of the verified website session',
    () async {
      final store = Store()
        ..value = WebsiteSessionSnapshot(
          cookies: cookies,
          syncedAt: DateTime.now(),
          userAgent: browserAgent,
        ).withVerifiedUser(1);
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            expect(options.headers['User-Agent'], browserAgent);
            expect(options.headers['Cookie'], 'chii_auth=test-auth');
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data:
                    '<div id="badgeUserPanel"><a class="avatar" href="/user/alice"></a></div><div class="pm-conversation-list"></div>',
              ),
            );
          },
        ),
      );
      final service = PmService(sessionStore: store, dio: dio);
      addTearDown(service.dispose);
      expect(await service.loadInbox(), isEmpty);
    },
  );
}
