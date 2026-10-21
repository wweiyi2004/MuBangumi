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
  for (final target in ['subjects', 'characters', 'persons']) {
    test(
      'read-only $target POST retries a transient filter service failure',
      () async {
        final dio = Dio(BaseOptions(baseUrl: 'https://api.bgm.tv/v0'));
        final api = BangumiApi(dio: dio);
        addTearDown(() => dio.close(force: true));
        var calls = 0;
        Map<String, dynamic>? payload;
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              calls++;
              payload = Map<String, dynamic>.from(options.data as Map);
              if (calls == 1) {
                handler.reject(
                  DioException(
                    requestOptions: options,
                    type: DioExceptionType.badResponse,
                    response: Response(
                      requestOptions: options,
                      statusCode: 503,
                    ),
                  ),
                );
              } else {
                handler.resolve(
                  Response(
                    requestOptions: options,
                    statusCode: 200,
                    data: {'data': <dynamic>[]},
                  ),
                );
              }
            },
          ),
        );
        switch (target) {
          case 'subjects':
            await api.searchSubjects(
              '  ',
              minimumRating: 8.1,
              startYear: 2007,
              endYear: 2011,
            );
          case 'characters':
            await api.searchCharacters('测试');
          case 'persons':
            await api.searchPersons('测试');
        }
        expect(calls, 2);
        if (target == 'subjects') {
          expect(payload!['keyword'], '');
          expect(payload!['sort'], 'rank');
          expect((payload!['filter'] as Map)['rating'], ['>=8.1']);
          expect((payload!['filter'] as Map)['air_date'], [
            '>=2007-01-01',
            '<2012-01-01',
          ]);
        }
      },
    );
  }
  test(
    'search-like writes and client errors never enter the read retry allowlist',
    () {
      for (final path in [
        '/v0/search/subjects/42',
        '/v0/users/-/collections/1',
        '/v0/search/messages',
        '/search/subjects/write',
      ]) {
        final request = RequestOptions(
          path: path,
          method: 'POST',
          baseUrl: 'https://api.bgm.tv',
        );
        expect(
          shouldRetryBangumiReadRequest(
            DioException(
              requestOptions: request,
              type: DioExceptionType.connectionError,
            ),
          ),
          false,
        );
      }
      for (final code in [400, 401, 403, 422, 429]) {
        final request = RequestOptions(
          path: '/v0/search/subjects',
          method: 'POST',
        );
        expect(
          shouldRetryBangumiReadRequest(
            DioException(
              requestOptions: request,
              type: DioExceptionType.badResponse,
              response: Response(requestOptions: request, statusCode: code),
            ),
          ),
          false,
        );
      }
    },
  );
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
