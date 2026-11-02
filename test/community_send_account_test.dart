import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/network/community_service.dart';
import 'package:mubangumi/models/community_models.dart';

void main() {
  for (final verb in ['reply', 'new-topic']) {
    for (final outcome in ['success', '403', '500', 'timeout']) {
      test(
        '$verb late $outcome never changes or retries under the new account',
        () async {
          final received = Completer<void>(), release = Completer<void>();
          var writes = 0;
          final dio = Dio()
            ..interceptors.add(
              InterceptorsWrapper(
                onRequest: (request, handler) async {
                  writes++;
                  received.complete();
                  await release.future;
                  if (outcome == 'success') {
                    handler.resolve(
                      Response(
                        requestOptions: request,
                        statusCode: 200,
                        data: {'id': 42},
                      ),
                    );
                  } else {
                    handler.reject(
                      DioException(
                        requestOptions: request,
                        type: outcome == 'timeout'
                            ? DioExceptionType.receiveTimeout
                            : DioExceptionType.badResponse,
                        response: outcome == 'timeout'
                            ? null
                            : Response(
                                requestOptions: request,
                                statusCode: int.parse(outcome),
                                data: {
                                  'code': 'NOT_ALLOWED',
                                  'message': 'join group first',
                                },
                              ),
                      ),
                    );
                  }
                },
              ),
            );
          final service = CommunityService.test(p1Dio: dio)
            ..setAccessToken('synthetic')
            ..setCurrentUsername('alice');
          addTearDown(service.dispose);
          final future = verb == 'reply'
              ? service
                    .replyToTopic(
                      topic: const CommunityTopic(
                        id: 1,
                        kind: CommunityTopicKind.group,
                        title: '测试',
                        url: 'https://bgm.tv/group/topic/1',
                        webUrl: 'https://bgm.tv/group/topic/1',
                      ),
                      content: '合成正文',
                      turnstileToken: 'synthetic-verified',
                    )
                    .then((_) {})
              : service
                    .createGroupTopic(
                      slug: 'test',
                      title: '测试',
                      content: '合成正文',
                      turnstileToken: 'synthetic-verified',
                    )
                    .then((_) {});
          await received.future;
          service.setAccessToken('synthetic-b');
          service.setCurrentUsername('bob');
          final expectation = expectLater(future, throwsFormatException);
          release.complete();
          await expectation;
          expect(writes, 1);
          expect(service.currentUsername, 'bob');
        },
      );
    }
  }
}
