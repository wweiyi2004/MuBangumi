import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/feedback/feedback_service.dart';
import 'package:mubangumi/core/feedback/feedback_submission.dart';

void main() {
  const endpoint = 'https://feedback.example/api/feedback';
  const deviceInfo = FeedbackDeviceInfo(
    appVersion: '2.4.1',
    buildNumber: '4031',
    platform: 'android',
  );

  test('submits trimmed feedback and confirmed device information', () async {
    final dio = Dio();
    late Map<String, dynamic> body;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          expect(options.path, endpoint);
          body = Map<String, dynamic>.from(options.data as Map);
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: {'ok': true},
            ),
          );
        },
      ),
    );
    final service = FeedbackService(
      dio: dio,
      endpoint: endpoint,
      deviceInfoLoader: () async => deviceInfo,
    );

    await service.submit(
      category: FeedbackCategory.suggestion,
      message: '  希望按评分筛选  ',
      email: ' reader@example.net ',
    );

    expect(body['category'], 'suggestion');
    expect(body['message'], '希望按评分筛选');
    expect(body['email'], 'reader@example.net');
    expect(body['includeDeviceInfo'], isTrue);
    expect(body['appVersion'], '2.4.1');
    expect(body['buildNumber'], '4031');
    expect(body['platform'], 'android');
    expect(body['website'], '');
  });

  test('does not load or send device information when disabled', () async {
    final dio = Dio();
    late Map<String, dynamic> body;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          body = Map<String, dynamic>.from(options.data as Map);
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: {'ok': true},
            ),
          );
        },
      ),
    );
    final service = FeedbackService(
      dio: dio,
      endpoint: endpoint,
      deviceInfoLoader: () async => throw StateError('must not load'),
    );

    await service.submit(
      category: FeedbackCategory.other,
      message: '其他意见',
      includeDeviceInfo: false,
    );

    expect(body['includeDeviceInfo'], isFalse);
    expect(body['appVersion'], '');
    expect(body['buildNumber'], '');
    expect(body['platform'], '');
  });

  test('requires a valid message, email and configured endpoint', () async {
    final dio = Dio();
    var requests = 0;
    dio.interceptors.add(InterceptorsWrapper(onRequest: (_, _) => requests++));
    final service = FeedbackService(dio: dio, endpoint: endpoint);

    await expectLater(
      service.submit(category: FeedbackCategory.problem, message: '  '),
      throwsA(isA<FeedbackException>()),
    );
    await expectLater(
      service.submit(
        category: FeedbackCategory.problem,
        message: '问题',
        email: 'not-an-email',
      ),
      throwsA(isA<FeedbackException>()),
    );
    await expectLater(
      FeedbackService(
        dio: Dio(),
      ).submit(category: FeedbackCategory.problem, message: '问题'),
      throwsA(isA<FeedbackException>()),
    );
    expect(requests, 0);
  });

  test('does not retry uncertain submissions automatically', () async {
    final dio = Dio();
    var requests = 0;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests++;
          handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.connectionError,
            ),
          );
        },
      ),
    );
    final service = FeedbackService(dio: dio, endpoint: endpoint);

    await expectLater(
      service.submit(
        category: FeedbackCategory.problem,
        message: '同步失败',
        includeDeviceInfo: false,
      ),
      throwsA(isA<FeedbackException>()),
    );
    expect(requests, 1);
  });

  test('submits through a real local HTTP connection', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final service = FeedbackService(
      endpoint: 'http://127.0.0.1:${server.port}/api/feedback',
      deviceInfoLoader: () async => deviceInfo,
    );
    final submission = service.submit(
      category: FeedbackCategory.problem,
      message: '真实 HTTP 提交',
      email: 'reader@example.net',
    );

    final request = await server.first;
    expect(request.method, 'POST');
    expect(request.uri.path, '/api/feedback');
    expect(request.headers.contentType?.mimeType, 'application/json');
    final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
    expect(body['message'], '真实 HTTP 提交');
    expect(body['platform'], 'android');
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'ok': true}));
    await request.response.close();
    await submission;
  });
}
