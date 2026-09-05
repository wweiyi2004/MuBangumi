import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/network/netaba_api.dart';

void main() {
  test(
    'history, trends and reputation share in-flight requests and cache results',
    () async {
      var requests = 0;
      var now = DateTime(2026);
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests++;
            handler.resolve(
              Response(
                requestOptions: options,
                data: options.path == '/score-increases'
                    ? <dynamic>[]
                    : <String, dynamic>{},
              ),
            );
          },
        ),
      );
      final api = NetabaApi(dio: dio, now: () => now);
      await Future.wait([
        api.getSubjectHistory(7),
        api.getSubjectHistory(7),
        api.getTrending(),
        api.getTrending(),
        api.getScoreIncreases(),
      ]);
      expect(requests, 3);
      await api.getSubjectHistory(7);
      await api.getTrending();
      await api.getScoreIncreases();
      expect(requests, 3);
      now = now.add(const Duration(minutes: 10));
      await api.getSubjectHistory(7);
      expect(requests, 4);
      api.clearCache();
      await api.getSubjectHistory(7);
      expect(requests, 5);
    },
  );

  test('network error is not cached as an empty history', () async {
    var requests = 0;
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests++;
          if (requests == 1) {
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.connectionError,
              ),
            );
          } else {
            handler.resolve(
              Response(requestOptions: options, data: <String, dynamic>{}),
            );
          }
        },
      ),
    );
    final api = NetabaApi(dio: dio);
    await expectLater(api.getSubjectHistory(7), throwsA(isA<DioException>()));
    await api.getSubjectHistory(7);
    expect(requests, 2);
  });
}
