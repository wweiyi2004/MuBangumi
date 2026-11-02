import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/feedback/feedback_service.dart';
import 'package:mubangumi/core/feedback/feedback_submission.dart';
import 'package:mubangumi/screens/feedback_page.dart';
import 'package:mubangumi/state/service_providers.dart';

void main() {
  const endpoint = 'https://feedback.example/api/feedback';
  const deviceInfo = FeedbackDeviceInfo(
    appVersion: '2.4.1',
    buildNumber: '4031',
    platform: 'windows',
  );

  Future<void> pumpPage(WidgetTester tester, FeedbackService service) {
    return tester.pumpWidget(
      ProviderScope(
        overrides: [feedbackServiceProvider.overrideWithValue(service)],
        child: const MaterialApp(home: FeedbackPage()),
      ),
    );
  }

  testWidgets('focused form submits category, details and optional contact', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
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
    await pumpPage(
      tester,
      FeedbackService(
        dio: dio,
        endpoint: endpoint,
        deviceInfoLoader: () async => deviceInfo,
      ),
    );

    expect(find.text('反馈问题'), findsOneWidget);
    expect(find.text('提出建议'), findsOneWidget);
    expect(find.text('其他'), findsOneWidget);
    await tester.tap(find.text('提出建议'));
    await tester.enterText(find.byType(TextFormField).first, '希望在收藏页增加评分筛选');
    await tester.enterText(
      find.byType(TextFormField).last,
      'reader@example.net',
    );
    await tester.pump();
    await tester.ensureVisible(find.text('提交反馈'));
    await tester.tap(find.text('提交反馈'));
    await tester.pumpAndSettle();

    expect(body['category'], 'suggestion');
    expect(body['message'], '希望在收藏页增加评分筛选');
    expect(body['email'], 'reader@example.net');
    expect(body['appVersion'], '2.4.1');
    expect(find.text('反馈已发送'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed submission preserves entered content', (tester) async {
    final dio = Dio();
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
    await pumpPage(
      tester,
      FeedbackService(
        dio: dio,
        endpoint: endpoint,
        deviceInfoLoader: () async => deviceInfo,
      ),
    );

    await tester.enterText(find.byType(TextFormField).first, '这条内容不能丢');
    await tester.pump();
    await tester.ensureVisible(find.text('提交反馈'));
    await tester.tap(find.text('提交反馈'));
    await tester.pumpAndSettle();

    expect(find.text('这条内容不能丢'), findsOneWidget);
    expect(find.text('提交失败，请检查网络后稍后重试'), findsOneWidget);
    expect(find.text('反馈已发送'), findsNothing);
  });

  testWidgets('metadata can be disabled from the form', (tester) async {
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
    await pumpPage(
      tester,
      FeedbackService(
        dio: dio,
        endpoint: endpoint,
        deviceInfoLoader: () async => deviceInfo,
      ),
    );

    await tester.enterText(find.byType(TextFormField).first, '不附带设备信息');
    await tester.ensureVisible(find.text('附带版本与平台信息'));
    await tester.tap(find.text('附带版本与平台信息'));
    await tester.pump();
    await tester.ensureVisible(find.text('提交反馈'));
    await tester.tap(find.text('提交反馈'));
    await tester.pumpAndSettle();

    expect(body['includeDeviceInfo'], isFalse);
    expect(body['appVersion'], '');
    expect(body['platform'], '');
  });
}
