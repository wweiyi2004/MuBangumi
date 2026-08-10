import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/auth/bangumi_oauth.dart';
import 'package:mubangumi/core/network/bangumi_api.dart';
import 'package:mubangumi/core/network/bangumi_endpoints.dart';
import 'package:mubangumi/core/storage/token_store.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/state/session_controller.dart';

void main() {
  const config = OAuthConfig(clientId: 'client', clientSecret: 'secret');

  test('transient OAuth refresh failure keeps stored credentials', () async {
    final store = _MemoryTokenStore(config: config);
    final controller = SessionController(
      _FakeBangumiApi(),
      _FailingOAuth(const BangumiOAuthException('网络暂时不可用')),
      store,
    );
    addTearDown(controller.dispose);

    await _waitFor(() => controller.state.phase == SessionPhase.signedIn);

    expect(store.clearCalls, 0);
    expect(store.accessToken, 'stored-access-token');
    expect(store.refreshToken, 'stored-refresh-token');
  });

  test('invalid grant clears stored credentials', () async {
    final store = _MemoryTokenStore(config: config);
    final controller = SessionController(
      _FakeBangumiApi(),
      _FailingOAuth(
        const BangumiOAuthException(
          'refresh token 已失效',
          invalidatesSession: true,
        ),
      ),
      store,
    );
    addTearDown(controller.dispose);

    await _waitFor(() => controller.state.phase == SessionPhase.signedOut);

    expect(store.clearCalls, 1);
    expect(store.accessToken, isNull);
    expect(store.refreshToken, isNull);
    expect(controller.state.message, contains('登录已过期'));
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
