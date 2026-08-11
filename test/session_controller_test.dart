import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/auth/bangumi_oauth.dart';
import 'package:mubangumi/core/auth/website_session.dart';
import 'package:mubangumi/core/network/bangumi_api.dart';
import 'package:mubangumi/core/network/bangumi_endpoints.dart';
import 'package:mubangumi/core/storage/token_store.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/state/session_controller.dart';

void main() {
  const config = OAuthConfig(clientId: 'client', clientSecret: 'secret');

  SessionController buildController({
    required TokenStore store,
    required BangumiOAuth oauth,
    BangumiApi? api,
  }) => SessionController(
    api ?? _FakeBangumiApi(),
    oauth,
    store,
    websiteSessionStore: _MemoryWebsiteSessionStore(),
  );

  test('transient OAuth refresh failure keeps stored credentials', () async {
    final store = _MemoryTokenStore(config: config);
    final controller = buildController(
      store: store,
      oauth: _FailingOAuth(const BangumiOAuthException('网络暂时不可用')),
    );
    addTearDown(controller.dispose);

    await _waitFor(() => controller.state.phase == SessionPhase.signedIn);

    expect(store.clearCalls, 0);
    expect(store.accessToken, 'stored-access-token');
    expect(store.refreshToken, 'stored-refresh-token');
  });

  test('invalid grant clears stored credentials', () async {
    final store = _MemoryTokenStore(config: config);
    final controller = buildController(
      store: store,
      oauth: _FailingOAuth(
        const BangumiOAuthException(
          'refresh token 已失效',
          invalidatesSession: true,
        ),
      ),
    );
    addTearDown(controller.dispose);

    await _waitFor(() => controller.state.phase == SessionPhase.signedOut);

    expect(store.clearCalls, 1);
    expect(store.accessToken, isNull);
    expect(store.refreshToken, isNull);
    expect(controller.state.message, contains('登录已过期'));
  });

  test('cancelling OAuth returns to login without an error message', () async {
    final store = _MemoryTokenStore(config: null)
      ..accessToken = null
      ..refreshToken = null
      ..expiresAt = null;
    final controller = buildController(
      store: store,
      oauth: _AuthorizeFailingOAuth(
        const BangumiOAuthException('已取消 Bangumi 授权', isCancelled: true),
      ),
    );
    addTearDown(controller.dispose);

    await _waitFor(() => controller.state.phase == SessionPhase.signedOut);
    final signedIn = await controller.signInWithOAuth(config);

    expect(signedIn, isFalse);
    expect(controller.state.phase, SessionPhase.signedOut);
    expect(controller.state.message, isNull);
    expect(store.config, config);
  });

  test('OAuth authorize keeps signedOut so the auth UI can host launchers',
      () async {
    final store = _MemoryTokenStore(config: null)
      ..accessToken = null
      ..refreshToken = null
      ..expiresAt = null;
    final oauth = _PhaseObservingOAuth();
    final controller = buildController(store: store, oauth: oauth);
    addTearDown(controller.dispose);

    await _waitFor(() => controller.state.phase == SessionPhase.signedOut);

    late SessionPhase phaseDuringAuthorize;
    late bool refreshingDuringAuthorize;
    oauth.onAuthorize = () {
      phaseDuringAuthorize = controller.state.phase;
      refreshingDuringAuthorize = controller.state.isRefreshing;
    };

    var launcherCalled = false;
    final signedIn = await controller.signInWithOAuth(
      config,
      launchAuthorization: (uri, callback) async {
        launcherCalled = true;
        // AuthScreen must still be the host route (signedOut, not booting).
        expect(controller.state.phase, SessionPhase.signedOut);
        return false;
      },
    );

    expect(signedIn, isFalse);
    expect(launcherCalled, isTrue);
    expect(phaseDuringAuthorize, SessionPhase.signedOut);
    expect(refreshingDuringAuthorize, isTrue);
    expect(controller.state.phase, SessionPhase.signedOut);
  });
}

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('Timed out waiting for asynchronous session state');
}

class _FailingOAuth extends BangumiOAuth {
  _FailingOAuth(this.error);

  final BangumiOAuthException error;

  @override
  Future<OAuthTokenBundle> refresh(
    OAuthConfig config,
    String refreshToken,
  ) async {
    throw error;
  }
}

class _AuthorizeFailingOAuth extends BangumiOAuth {
  _AuthorizeFailingOAuth(this.error);

  final BangumiOAuthException error;

  @override
  Future<OAuthTokenBundle> authorize(
    OAuthConfig config, {
    OAuthAuthorizationLauncher? launchAuthorization,
  }) async {
    throw error;
  }
}

/// Invokes [onAuthorize] while still inside authorize so the session phase
/// can be asserted before tokens exist.
class _PhaseObservingOAuth extends BangumiOAuth {
  void Function()? onAuthorize;

  @override
  Future<OAuthTokenBundle> authorize(
    OAuthConfig config, {
    OAuthAuthorizationLauncher? launchAuthorization,
  }) async {
    onAuthorize?.call();
    // Never-completing callback: this test only cares about the session phase
    // around the launcher call, not a full code exchange.
    final pendingCallback = Completer<Uri>().future;
    final opened = launchAuthorization == null
        ? true
        : await launchAuthorization(
            Uri.parse('https://bgm.tv/oauth/authorize'),
            pendingCallback,
          );
    if (!opened) {
      throw const BangumiOAuthException('已取消 Bangumi 授权', isCancelled: true);
    }
    throw const BangumiOAuthException('unexpected open');
  }
}

class _FakeBangumiApi extends BangumiApi {
  @override
  Future<BangumiUser> getMe() async => const BangumiUser(
    id: 1,
    username: 'tester',
    nickname: 'Tester',
    avatarUrl: '',
  );

  @override
  Future<List<UserCollection>> getUserCollections(
    String username, {
    SubjectType? subjectType,
    CollectionType? collectionType,
    int? maxItems,
  }) async => const [];
}

class _MemoryWebsiteSessionStore extends WebsiteSessionStore {
  WebsiteSessionSnapshot? snapshot;

  @override
  Future<WebsiteSessionSnapshot?> read() async => snapshot;

  @override
  Future<void> write(WebsiteSessionSnapshot snapshot) async {
    this.snapshot = snapshot;
  }

  @override
  Future<void> clear() async {
    snapshot = null;
  }
}

class _MemoryTokenStore extends TokenStore {
  _MemoryTokenStore({required this.config});

  String? accessToken = 'stored-access-token';
  String? refreshToken = 'stored-refresh-token';
  DateTime? expiresAt = DateTime.now().subtract(const Duration(minutes: 1));
  OAuthConfig? config;
  int clearCalls = 0;

  @override
  Future<String?> read() async => accessToken;

  @override
  Future<String?> readRefreshToken() async => refreshToken;

  @override
  Future<DateTime?> readExpiresAt() async => expiresAt;

  @override
  Future<OAuthConfig?> readOAuthConfig() async => config;

  @override
  Future<void> writeOAuthConfig(OAuthConfig config) async {
    this.config = config;
  }

  @override
  Future<BangumiNetworkRoute> readNetworkRoute() async =>
      BangumiNetworkRoute.official;

  @override
  Future<void> writeTokens(OAuthTokenBundle tokens) async {
    accessToken = tokens.accessToken;
    refreshToken = tokens.refreshToken;
    expiresAt = tokens.expiresAt;
  }

  @override
  Future<void> clear() async {
    clearCalls++;
    accessToken = null;
    refreshToken = null;
    expiresAt = null;
  }
}
