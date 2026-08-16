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
  test('retries transient reverse-proxy GET failures', () {
    expect(shouldRetryBangumiProxyRequest(_failure()), isTrue);
    expect(
      shouldRetryBangumiProxyRequest(
        _failure(type: DioExceptionType.badResponse, statusCode: 503),
      ),
      isTrue,
    );
  });

  test('does not retry writes or official-route failures', () {
    expect(shouldRetryBangumiProxyRequest(_failure(method: 'PATCH')), isFalse);
    expect(
      shouldRetryBangumiProxyRequest(
        _failure(baseUrl: BangumiNetworkRoute.official.apiBaseUrl),
      ),
      isFalse,
    );
    expect(
      shouldRetryBangumiProxyRequest(
        _failure(type: DioExceptionType.badResponse, statusCode: 401),
      ),
      isFalse,
    );
  });
}
