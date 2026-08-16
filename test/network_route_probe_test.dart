import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/network/bangumi_endpoints.dart';
import 'package:mubangumi/core/network/network_route_probe.dart';

void main() {
  test('route probe reports success and caches recent results', () async {
    var requests = 0;
    final probe = BangumiRouteProbe(
      dioFactory: (route) {
        final dio = Dio(BaseOptions(baseUrl: route.apiBaseUrl));
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              requests++;
              handler.resolve(
                Response<void>(requestOptions: options, statusCode: 200),
              );
            },
          ),
        );
        return dio;
      },
    );

    final first = await probe.probe(BangumiNetworkRoute.reverseProxy);
    final cached = await probe.probe(BangumiNetworkRoute.reverseProxy);

    expect(first.available, isTrue);
    expect(first.summary, contains('ms · 畅通'));
    expect(cached.available, isTrue);
    expect(requests, 1);

    await probe.probe(BangumiNetworkRoute.reverseProxy, force: true);
    expect(requests, 2);
  });

  test(
    'route probe turns connection errors into an unavailable result',
    () async {
      final probe = BangumiRouteProbe(
        dioFactory: (route) {
          final dio = Dio(BaseOptions(baseUrl: route.apiBaseUrl));
          dio.interceptors.add(
            InterceptorsWrapper(
              onRequest: (options, handler) => handler.reject(
                DioException(
                  requestOptions: options,
                  type: DioExceptionType.connectionError,
                ),
              ),
            ),
          );
          return dio;
        },
      );

      final result = await probe.probe(BangumiNetworkRoute.official);

      expect(result.available, isFalse);
      expect(result.summary, '无法连接');
    },
  );
}
