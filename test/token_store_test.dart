import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/auth/bangumi_oauth.dart';
import 'package:mubangumi/core/storage/token_store.dart';
import 'package:mubangumi/models/bangumi_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const config = OAuthConfig(
    clientId: 'new-client',
    clientSecret: 'new-secret',
  );
  final tokens = OAuthTokenBundle(
    accessToken: 'new-access',
    refreshToken: 'new-refresh',
    expiresAt: DateTime.utc(2030),
  );
  const user = BangumiUser(
    id: 123,
    username: 'alice',
    nickname: 'Alice',
    avatarUrl: '',
  );
  setUp(
    () => FlutterSecureStorage.setMockInitialValues({
      'bangumi_access_token': 'legacy-access',
      'bangumi_refresh_token': 'legacy-refresh',
      'bangumi_oauth_client_id': 'legacy-client',
      'bangumi_oauth_client_secret': 'legacy-secret',
    }),
  );

  test(
    'legacy credentials remain readable and migrate as one credential record',
    () async {
      final store = TokenStore();
      expect(await store.read(), 'legacy-access');
      await store.writeOAuthSession(config, tokens);
      final restarted = TokenStore();
      expect(await restarted.read(), 'new-access');
      expect(await restarted.readRefreshToken(), 'new-refresh');
      expect(await restarted.readExpiresAt(), tokens.expiresAt);
      expect((await restarted.readOAuthConfig())!.clientId, 'new-client');
    },
  );

  test(
    'legacy credentials have no trusted identity until /me verifies them',
    () async {
      final store = TokenStore();
      expect(await store.readVerifiedUser('legacy-access'), isNull);
      await store.bindVerifiedUser((await store.read()) ?? '', user);
      expect((await TokenStore().readVerifiedUser('legacy-access'))?.id, 123);
      expect(await store.readRefreshToken(), 'legacy-refresh');
      expect(await store.readVerifiedUser('another-token'), isNull);
    },
  );

  test(
    'refresh atomically preserves identity and rejects the old token',
    () async {
      final store = TokenStore();
      await store.bindVerifiedUser((await store.read()) ?? '', user);
      await store.writeTokens(tokens);
      expect(
        (await TokenStore().readVerifiedUser('new-access'))?.username,
        'alice',
      );
      expect(await store.readVerifiedUser('legacy-access'), isNull);
    },
  );

  test(
    'replacement OAuth and personal credentials never inherit identity',
    () async {
      final store = TokenStore();
      await store.bindVerifiedUser((await store.read()) ?? '', user);
      await store.writeOAuthSession(config, tokens);
      expect(await store.readVerifiedUser('new-access'), isNull);
      await store.bindVerifiedUser((await store.read()) ?? '', user);
      await store.write('personal-token');
      expect(await store.readVerifiedUser('personal-token'), isNull);
      await store.bindVerifiedUser((await store.read()) ?? '', user);
      await store.clear();
      expect(await store.readVerifiedUser('personal-token'), isNull);
      await expectLater(
        store.bindVerifiedUser((await store.read()) ?? '', user),
        throwsStateError,
      );
    },
  );

  test(
    'a stale verification cannot bind identity to replacement credentials',
    () async {
      final store = TokenStore();
      await store.write('replacement');
      await expectLater(
        store.bindVerifiedUser('legacy-access', user),
        throwsStateError,
      );
      expect(await store.readVerifiedUser('replacement'), isNull);
      expect(await store.read(), 'replacement');
    },
  );

  test('personal token cannot inherit old refresh credentials', () async {
    final store = TokenStore();
    await store.writeOAuthSession(config, tokens);
    await store.write('personal-token');
    expect(await store.read(), 'personal-token');
    expect(await store.readRefreshToken(), isNull);
    expect(await store.readExpiresAt(), isNull);
  });

  test(
    'a verified personal token can replace a corrupt saved record',
    () async {
      await const FlutterSecureStorage().write(
        key: 'bangumi_credentials_v2',
        value: '{broken',
      );
      final store = TokenStore();
      await expectLater(store.read(), throwsFormatException);
      await store.write('replacement-token');
      expect(await store.read(), 'replacement-token');
      expect(await store.readRefreshToken(), isNull);
    },
  );

  test('an absent new refresh token cannot revive an older one', () async {
    final store = TokenStore();
    await store.writeOAuthSession(config, tokens);
    await store.writeTokens(
      OAuthTokenBundle(
        accessToken: 'access-only',
        refreshToken: '',
        expiresAt: DateTime.utc(2031),
      ),
    );
    expect(await store.readRefreshToken(), isNull);
    expect((await store.readOAuthConfig())!.clientId, 'new-client');
  });

  test(
    'signed-out record takes precedence over leftover legacy credentials',
    () async {
      final store = TokenStore();
      await store.writeOAuthSession(config, tokens);
      await store.clear();
      await const FlutterSecureStorage().write(
        key: 'bangumi_access_token',
        value: 'stale',
      );
      await const FlutterSecureStorage().write(
        key: 'bangumi_refresh_token',
        value: 'stale-refresh',
      );
      expect(await TokenStore().read(), isNull);
      expect(await TokenStore().readRefreshToken(), isNull);
      expect((await TokenStore().readOAuthConfig())!.clientId, 'new-client');
    },
  );
}
