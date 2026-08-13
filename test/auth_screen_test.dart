import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/auth/bangumi_oauth.dart';
import 'package:mubangumi/core/auth/oauth_builtin.dart';
import 'package:mubangumi/core/network/bangumi_api.dart';
import 'package:mubangumi/core/network/bangumi_endpoints.dart';
import 'package:mubangumi/core/storage/token_store.dart';
import 'package:mubangumi/core/theme/app_theme.dart';
import 'package:mubangumi/screens/auth_screen.dart';
import 'package:mubangumi/state/session_controller.dart';

void main() {
  testWidgets('keeps advanced login choices out of the primary screen', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [tokenStoreProvider.overrideWithValue(_EmptyTokenStore())],
        child: MaterialApp(theme: AppTheme.light, home: const AuthScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('登录 Bangumi'), findsOneWidget);
    expect(find.byKey(const Key('primary-login-button')), findsOneWidget);
    expect(
      find.text(
        OAuthBuiltin.isConfigured ? '使用 Bangumi 一键登录' : '配置 Bangumi 登录',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('login-options-button')), findsOneWidget);
    expect(find.text('Access Token 备用登录'), findsNothing);

    await tester.tap(find.byKey(const Key('login-options-button')));
    await tester.pumpAndSettle();

    expect(find.text('其他登录方式与设置'), findsWidgets);
    expect(find.text('Access Token 备用登录'), findsOneWidget);
    expect(find.byKey(const Key('access-token-field')), findsOneWidget);
  });

  testWidgets('fallback login entrances stay reachable while OAuth waits', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = _StubSessionController();
    // Disposed by the ProviderScope container when the tree is torn down.

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionProvider.overrideWith((ref) => controller),
          tokenStoreProvider.overrideWithValue(_EmptyTokenStore()),
        ],
        child: MaterialApp(theme: AppTheme.light, home: const AuthScreen()),
      ),
    );
    await tester.pumpAndSettle();

    controller.setSessionState(
      const SessionState(phase: SessionPhase.signedOut, isRefreshing: true),
    );
    await tester.pump();

    // The OAuth flow itself stays guarded...
    expect(find.text('正在等待 Bangumi 授权…'), findsOneWidget);
    final primary = tester.widget<FilledButton>(
      find.byKey(const Key('primary-login-button')),
    );
    expect(primary.onPressed, isNull);

    // ...but the fallback entrances (token login, network route) must remain
    // reachable while the in-app browser waits for the callback.
    final options = tester.widget<OutlinedButton>(
      find.byKey(const Key('login-options-button')),
    );
    expect(options.onPressed, isNotNull);

    await tester.tap(find.byKey(const Key('login-options-button')));
    // The OAuth spinner keeps animating while isRefreshing, so pump with
    // explicit durations instead of pumpAndSettle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byKey(const Key('access-token-field')), findsOneWidget);
    expect(find.text('网络线路'), findsOneWidget);
  });
}

class _StubSessionController extends SessionController {
  _StubSessionController()
    : super(BangumiApi(), BangumiOAuth(), _EmptyTokenStore());

  void setSessionState(SessionState value) => state = value;
}

class _EmptyTokenStore extends TokenStore {
  @override
  Future<String?> read() async => null;

  @override
  Future<String?> readRefreshToken() async => null;

  @override
  Future<DateTime?> readExpiresAt() async => null;

  @override
  Future<OAuthConfig?> readOAuthConfig() async => null;

  @override
  Future<BangumiNetworkRoute> readNetworkRoute() async =>
      BangumiNetworkRoute.official;

  @override
  Future<void> clear() async {}
}
