import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/network/bangumi_api.dart';
import 'package:mubangumi/core/network/bangumi_endpoints.dart';

DioException _failure({
  String method = 'GET',
  String? baseUrl,
  DioExceptionType type = DioExceptionType.connectionError,
  int? statusCode,
}) {
  final request = RequestOptions(
    path: '/subjects/8',
    method: method,
    baseUrl: baseUrl ?? BangumiNetworkRoute.reverseProxy.apiBaseUrl,
  );
  return DioException(
    requestOptions: request,
    type: type,
    response: statusCode == null
        ? null
        : Response<void>(requestOptions: request, statusCode: statusCode),
  );
}

void main() {
  test('retries transient reads on every route, official included', () {
    // The retry used to require the reverse proxy, leaving the default
    // official route with none at all: one blip failed the request outright,
    // including the /me call that finishes an OAuth sign-in.
    for (final route in BangumiNetworkRoute.values) {
      final base = route.apiBaseUrl;
      expect(
        shouldRetryBangumiReadRequest(_failure(baseUrl: base)),
        isTrue,
        reason: 'connectionError on ${route.name}',
      );
      expect(
        shouldRetryBangumiReadRequest(
          _failure(baseUrl: base, type: DioExceptionType.receiveTimeout),
        ),
        isTrue,
        reason: 'receiveTimeout on ${route.name}',
      );
      expect(
        shouldRetryBangumiReadRequest(
          _failure(
            baseUrl: base,
            type: DioExceptionType.badResponse,
            statusCode: 503,
          ),
        ),
        isTrue,
        reason: '503 on ${route.name}',
      );
    }
  });

  test('never retries writes', () {
    for (final method in ['POST', 'PUT', 'PATCH', 'DELETE']) {
      expect(
        shouldRetryBangumiReadRequest(_failure(method: method)),
        isFalse,
        reason: method,
      );
    }
  });

  test('does not retry deterministic client errors', () {
    for (final status in [400, 401, 403, 404, 422]) {
      expect(
        shouldRetryBangumiReadRequest(
          _failure(type: DioExceptionType.badResponse, statusCode: status),
        ),
        isFalse,
        reason: '$status',
      );
    }
  });
}
