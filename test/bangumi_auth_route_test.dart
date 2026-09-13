import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/network/bangumi_api.dart';
import 'package:mubangumi/core/network/bangumi_endpoints.dart';

void main() {
  for (final route in BangumiNetworkRoute.values) {
    test('identity verification uses the issuer on ${route.name}', () async {
      final requests = <RequestOptions>[];
      final dio = Dio()
        ..httpClientAdapter = _Adapter((options) {
          requests.add(options);
          return _response(200, {'id': 1, 'username': 'tester'});
        });
      final api = BangumiApi(dio: dio)
        ..setNetworkRoute(route)
        ..setAccessToken('test-token');

      expect((await api.getMe()).username, 'tester');
      expect(requests.single.uri.toString(), 'https://api.bgm.tv/v0/me');
      expect(requests.single.headers['Authorization'], 'Bearer test-token');
      expect(requests.single.headers['Cache-Control'], 'no-store');
      // Checking identity must not silently change the user's content route.
      expect(dio.options.baseUrl, route.apiBaseUrl);
    });
  }

  test('a proxy 401 neither refreshes credentials nor proves expiry', () async {
    var requests = 0;
    var refreshes = 0;
    final dio = Dio()
      ..httpClientAdapter = _Adapter((options) {
        requests++;
        expect(options.uri.host, 'bgmapi.anibt.net');
        expect(options.headers['Authorization'], 'Bearer test-token');
        return _response(401, {'description': 'need Login'});
      });
    final api = BangumiApi(dio: dio)
      ..setNetworkRoute(BangumiNetworkRoute.reverseProxy)
      ..setAccessToken('test-token');
    api.onUnauthorizedRefresh = () async {
      refreshes++;
      return true;
    };

    await expectLater(
      api.getUser('tester'),
      throwsA(
        isA<BangumiApiException>()
            .having((e) => e.statusCode, 'status', 401)
            .having((e) => e.retryable, 'retryable', isTrue)
            .having((e) => e.message, 'message', contains('切换官方线路')),
      ),
    );
    expect(refreshes, 0);
    expect(requests, 1);
  });

  test(
    'official rejection remains definitive while proxy is selected',
    () async {
      final dio = Dio()
        ..httpClientAdapter = _Adapter(
          (_) => _response(401, {
            'description': "access token has been expired or doesn't exist",
          }),
        );
      final api = BangumiApi(dio: dio)
        ..setNetworkRoute(BangumiNetworkRoute.reverseProxy)
        ..setAccessToken('rejected-token');

      await expectLater(
        api.getMe(),
        throwsA(
          isA<BangumiApiException>()
              .having((e) => e.statusCode, 'status', 401)
              .having((e) => e.retryable, 'retryable', isFalse)
              .having((e) => e.message, 'message', contains('Bangumi 未接受')),
        ),
      );
    },
  );

  test('official 401 refresh retries with the rotated bearer token', () async {
    final bearers = <Object?>[];
    var refreshes = 0;
    final dio = Dio()
      ..httpClientAdapter = _Adapter((options) {
        expect(options.uri.host, 'api.bgm.tv');
        bearers.add(options.headers['Authorization']);
        return bearers.length == 1
            ? _response(401, {'description': 'expired'})
            : _response(200, {'id': 1, 'username': 'tester'});
      });
    final api = BangumiApi(dio: dio)
      ..setNetworkRoute(BangumiNetworkRoute.reverseProxy)
      ..setAccessToken('old-token');
    api.onUnauthorizedRefresh = () async {
      refreshes++;
      api.setAccessToken('rotated-token');
      return true;
    };

    expect((await api.getMe()).username, 'tester');
    expect(refreshes, 1);
    expect(bearers, ['Bearer old-token', 'Bearer rotated-token']);
  });
}

ResponseBody _response(int status, Map<String, dynamic> body) =>
    ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
  final ResponseBody Function(RequestOptions) respond;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => respond(options);

  @override
  void close({bool force = false}) {}
}
