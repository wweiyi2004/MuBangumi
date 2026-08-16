import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/auth/bangumi_oauth.dart';
import 'package:mubangumi/core/network/bangumi_api.dart';
import 'package:mubangumi/core/network/bangumi_endpoints.dart';
import 'package:mubangumi/core/network/network_route_probe.dart';
import 'package:mubangumi/core/storage/token_store.dart';
import 'package:mubangumi/state/session_controller.dart';
import 'package:mubangumi/widgets/network_route_picker.dart';

void main() {
  testWidgets('picker surfaces unexpected switch errors as a snackbar', (
    tester,
  ) async {
    final controller = _ThrowingRouteSessionController();
    // Disposed by the ProviderScope container when the tree is torn down.

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sessionProvider.overrideWith((ref) => controller)],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => Center(
                child: ElevatedButton(
                  onPressed: () => showNetworkRoutePicker(
                    context,
                    ref,
                    probe: _instantProbe(),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(BangumiNetworkRoute.reverseProxy.label));
    await tester.pumpAndSettle();
    await tester.tap(find.text('信任并启用'));
    await tester.pumpAndSettle();

    expect(find.textContaining('意外错误'), findsOneWidget);
  });
}

BangumiRouteProbe _instantProbe() => BangumiRouteProbe(
  dioFactory: (route) {
    final dio = Dio(BaseOptions(baseUrl: route.apiBaseUrl));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) => handler.resolve(
          Response<void>(requestOptions: options, statusCode: 200),
        ),
      ),
    );
    return dio;
  },
);

class _ThrowingRouteSessionController extends SessionController {
  _ThrowingRouteSessionController()
    : super(BangumiApi(), BangumiOAuth(), _EmptyPickerTokenStore());

  @override
  Future<String?> setNetworkRoute(BangumiNetworkRoute route) async {
    throw StateError('boom');
  }
}

class _EmptyPickerTokenStore extends TokenStore {
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
