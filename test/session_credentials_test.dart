import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/auth/bangumi_oauth.dart';
import 'package:mubangumi/core/network/bangumi_endpoints.dart';
import 'package:mubangumi/core/storage/token_store.dart';
import 'package:mubangumi/features/auth/application/session_credentials.dart';

void main() {
  test(
    'concurrent refresh requests rotate and persist credentials once',
    () async {
      final fixture = _Fixture();
      await fixture.credentials.readStored(1);
      final first = fixture.credentials.tryRefreshAccessToken();
      final second = fixture.credentials.tryRefreshAccessToken();
      expect(fixture.oauth.calls, 1);
      fixture.oauth.response.complete(_tokens('rotated'));
      expect(await first, isTrue);
      expect(await second, isTrue);
      expect(fixture.store.writes, ['rotated']);
      expect(fixture.activated, ['rotated']);
    },
  );

  for (final fails in [false, true]) {
    test(
      'late refresh ${fails ? 'failure' : 'success'} cannot affect a new login',
      () async {
        final fixture = _Fixture();
        await fixture.credentials.readStored(1);
        final old = fixture.credentials.tryRefreshAccessToken();
        fixture.generation++;
        fixture.credentials.reset(forgetStoredCredentials: true);
        await fixture.credentials.persistTokens(
          _tokens('replacement'),
          2,
          config: _config,
        );
        if (fails) {
          fixture.oauth.response.completeError(
            const BangumiOAuthException('revoked', invalidatesSession: true),
          );
        } else {
          fixture.oauth.response.complete(_tokens('stale'));
        }
        expect(await old, isFalse);
        expect(fixture.store.writes, ['replacement']);
        expect(fixture.credentials.accessToken, 'replacement');
        expect(fixture.activated, ['replacement']);
        expect(fixture.errors, isEmpty);
      },
    );
  }

  test(
    'logout waits for active writes and skips queued writes from old login',
    () async {
      final fixture = _Fixture();
      final started = Completer<void>();
      final release = Completer<void>();
      final events = <String>[];
      final first = fixture.credentials.writeCurrent(1, () async {
        started.complete();
        await release.future;
        events.add('old write');
      });
      await started.future;
      final queued = fixture.credentials.writeCurrent(1, () async {
        events.add('stale queued write');
      });
      fixture.generation++;
      fixture.credentials.reset(forgetStoredCredentials: true);
      final cleanup = fixture.credentials.writeCurrent(2, () async {
        events.add('logout cleanup');
      });
      expect(events, isEmpty);
      release.complete();
      expect(await first, isFalse);
      expect(await queued, isFalse);
      expect(await cleanup, isTrue);
      expect(events, ['old write', 'logout cleanup']);
    },
  );

  test('a failed credential write does not prevent logout cleanup', () async {
    final fixture = _Fixture();
    await expectLater(
      fixture.credentials.writeCurrent(1, () async => throw StateError('disk')),
      throwsStateError,
    );
    var cleaned = false;
    fixture.generation++;
    expect(
      await fixture.credentials.writeCurrent(2, () async {
        cleaned = true;
      }),
      isTrue,
    );
    expect(cleaned, isTrue);
  });

  test('late bootstrap read cannot replace current refresh metadata', () async {
    final fixture = _Fixture();
    fixture.store.pendingRead = Completer<String?>();
    final old = fixture.credentials.readStored(1);
    fixture.generation++;
    fixture.credentials.reset(forgetStoredCredentials: true);
    await fixture.credentials.persistTokens(_tokens('replacement'), 2);
    fixture.store.pendingRead!.complete('old');
    expect(await old, isNull);
    expect(fixture.credentials.accessToken, 'replacement');
    // Replacement has no OAuth config, so a late bootstrap must not make it
    // refreshable using the old account's client configuration.
    expect(await fixture.credentials.tryRefreshAccessToken(), isFalse);
    expect(fixture.oauth.calls, 0);
  });
}

const _config = OAuthConfig(
  clientId: 'test-client',
  clientSecret: 'test-secret',
);

OAuthTokenBundle _tokens(String token) => OAuthTokenBundle(
  accessToken: token,
  refreshToken: '$token-refresh',
  expiresAt: DateTime.now().add(const Duration(hours: 1)),
);

class _Fixture {
  _Fixture() {
    credentials = SessionCredentials(
      oauth: oauth,
      store: store,
      currentGeneration: () => generation,
      isCurrent: (value) => value == generation,
      canRefresh: () => true,
      onAccessTokenChanged: activated.add,
      onRefreshError: (error) async => errors.add(error),
    );
  }

  final store = _Store();
  final oauth = _OAuth();
  final activated = <String?>[];
  final errors = <Object>[];
  var generation = 1;
  late final SessionCredentials credentials;
}

class _OAuth extends BangumiOAuth {
  final response = Completer<OAuthTokenBundle>();
  var calls = 0;

  @override
  Future<OAuthTokenBundle> refresh(OAuthConfig config, String refreshToken) {
    calls++;
    return response.future;
  }
}

class _Store extends TokenStore {
  final writes = <String>[];
  Completer<String?>? pendingRead;

  @override
  Future<String?> read() => pendingRead?.future ?? Future.value('stored');
  @override
  Future<String?> readRefreshToken() async => 'stored-refresh';
  @override
  Future<DateTime?> readExpiresAt() async => DateTime(2020);
  @override
  Future<OAuthConfig?> readOAuthConfig() async => _config;
  @override
  Future<BangumiNetworkRoute> readNetworkRoute() async =>
      BangumiNetworkRoute.official;
  @override
  Future<void> writeTokens(OAuthTokenBundle tokens) async =>
      writes.add(tokens.accessToken);
  @override
  Future<void> writeOAuthSession(OAuthConfig config, OAuthTokenBundle tokens) =>
      writeTokens(tokens);
}
