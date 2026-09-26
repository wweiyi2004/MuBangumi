import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/network/community_service.dart';
import 'package:mubangumi/models/community_topic_submission.dart';
import 'support/pm_fixtures.dart';

final attempt = DateTime.utc(2026, 9, 22, 8);
Map<String, dynamic> topic({
  int id = 42,
  String author = 'alice',
  String group = 'demo',
  String title = 'title',
  String body = 'body',
  DateTime? created,
}) => {
  'id': id,
  'title': title,
  'creator': {'username': author},
  'createdAt': (created ?? attempt).millisecondsSinceEpoch ~/ 1000,
  'group': {'name': group},
  'replies': [
    {
      'creator': {'username': author},
      'content': body,
    },
  ],
};

CommunityService serviceFor(
  FutureOr<Object?> Function(RequestOptions) respond,
) {
  final dio = Dio()
    ..interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          try {
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: await respond(options),
              ),
            );
          } on DioException catch (error) {
            handler.reject(error);
          }
        },
      ),
    );
  final service = CommunityService.test(p1Dio: dio)
    ..setAccessToken('fixture')
    ..setCurrentUsername('alice');
  addTearDown(service.dispose);
  return service;
}

void main() {
  for (final result in [
    'redirect',
    'json',
    'unknown',
    'foreign',
    'server-error',
    'timeout',
  ]) {
    test('classic website publication receipt: $result', () async {
      var posts = 0;
      final api = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (request, handler) => handler.reject(
              DioException(
                requestOptions: request,
                type: DioExceptionType.badResponse,
                response: Response(
                  requestOptions: request,
                  statusCode: 403,
                  data: {
                    'code': 'NOT_ALLOWED',
                    'message': 'create posts, join group first',
                  },
                ),
              ),
            ),
          ),
        );
      final html = Dio(BaseOptions(baseUrl: 'https://bgm.tv'))
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (request, handler) {
              if (request.method == 'GET') {
                handler.resolve(
                  Response<String>(
                    requestOptions: request,
                    statusCode: 200,
                    data: '<input name="formhash" value="abcdefgh">',
                  ),
                );
                return;
              }
              posts++;
              if (result == 'timeout') {
                handler.reject(
                  DioException(
                    requestOptions: request,
                    type: DioExceptionType.receiveTimeout,
                  ),
                );
                return;
              }
              handler.resolve(
                Response<String>(
                  requestOptions: request,
                  statusCode: result == 'server-error'
                      ? 503
                      : const ['redirect', 'foreign'].contains(result)
                      ? 302
                      : 200,
                  data: result == 'json'
                      ? '{"id":42}'
                      : '<form id="postTopic"></form>',
                  headers: Headers.fromMap({
                    'location': [
                      result == 'foreign'
                          ? 'https://evil.test/group/topic/42'
                          : '/group/topic/42',
                    ],
                  }),
                ),
              );
            },
          ),
        );
      final service = CommunityService.test(
        p1Dio: api,
        htmlDio: html,
        sessionStore: PmTestWebsiteStore(),
      )..setAccessToken('fixture');
      addTearDown(service.dispose);
      final future = service.createGroupTopic(
        slug: 'demo',
        title: 'title',
        content: 'body',
        turnstileToken: 'once',
      );
      if (const ['redirect', 'json'].contains(result)) {
        expect((await future).id, 42);
      } else {
        await expectLater(future, throwsA(isA<CommunitySubmissionUncertain>()));
      }
      expect(posts, 1);
    });
  }

  test(
    'an ambiguous server error cannot trigger the private-group POST fallback',
    () async {
      var posts = 0;
      final service = serviceFor((request) {
        posts++;
        throw DioException(
          requestOptions: request,
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: request,
            statusCode: 500,
            data: {'code': 'NOT_JOIN_PRIVATE_GROUP_ERROR'},
          ),
        );
      });
      await expectLater(
        service.createGroupTopic(
          slug: 'demo',
          title: 'title',
          content: 'body',
          turnstileToken: 'once',
        ),
        throwsA(isA<CommunitySubmissionUncertain>()),
      );
      expect(posts, 1);
    },
  );

  test(
    'legacy draft readback checks recent matching content without sending',
    () async {
      final record = topic(
        created: DateTime.now().subtract(const Duration(minutes: 30)),
      );
      final service = serviceFor((request) {
        expect(request.method, 'GET');
        return request.path.endsWith('/42')
            ? record
            : {
                'data': [record],
              };
      });
      expect(
        (await service.findSubmittedGroupTopic(
          slug: 'demo',
          title: 'title',
          content: 'body',
          attemptedAt: null,
        ))?.id,
        42,
      );
    },
  );
  test(
    'successful API publication preserves its concrete topic receipt',
    () async {
      var writes = 0;
      final service = serviceFor((request) {
        writes++;
        return {'id': 42};
      });
      final receipt = await service.createGroupTopic(
        slug: 'demo',
        title: 'title',
        content: 'body',
        turnstileToken: 'once',
      );
      expect(receipt.id, 42);
      expect(receipt.webUrl, 'https://bgm.tv/group/topic/42');
      expect(writes, 1);
    },
  );

  for (final response in [
    null,
    {},
    {'id': 0},
    {'id': 'bad'},
    {'status': 'ok'},
  ]) {
    test(
      'HTTP success without a valid receipt stays uncertain: $response',
      () async {
        var writes = 0;
        final service = serviceFor((request) {
          writes++;
          return response;
        });
        await expectLater(
          service.createGroupTopic(
            slug: 'demo',
            title: 'title',
            content: 'body',
            turnstileToken: 'once',
          ),
          throwsA(isA<CommunitySubmissionUncertain>()),
        );
        expect(writes, 1);
      },
    );
  }

  test(
    'lost response is reconciled by reads and never replays publication',
    () async {
      final requests = <RequestOptions>[];
      final service = serviceFor((request) {
        requests.add(request);
        if (request.method == 'POST') {
          throw DioException(
            requestOptions: request,
            type: DioExceptionType.receiveTimeout,
          );
        }
        return request.path.endsWith('/42')
            ? topic(body: 'body\r\nline')
            : {
                'data': [topic()],
                'total': 1,
              };
      });
      await expectLater(
        service.createGroupTopic(
          slug: 'demo',
          title: 'title',
          content: 'body\nline',
          turnstileToken: 'once',
        ),
        throwsA(isA<CommunitySubmissionUncertain>()),
      );
      final result = await service.findSubmittedGroupTopic(
        slug: 'demo',
        title: 'title',
        content: 'body\nline',
        attemptedAt: attempt,
      );
      expect(result?.id, 42);
      expect(requests.where((r) => r.method == 'POST'), hasLength(1));
      expect(requests.where((r) => r.method == 'GET'), hasLength(2));
      expect(requests[1].queryParameters['mode'], 'created');
    },
  );

  for (final mismatch in [
    'author',
    'group',
    'title',
    'body',
    'old',
    'future',
    'ambiguous',
  ]) {
    test('readback cannot confirm $mismatch publication', () async {
      final wrong = topic(
        author: mismatch == 'author' ? 'bob' : 'alice',
        group: mismatch == 'group' ? 'other' : 'demo',
        title: mismatch == 'title' ? 'other' : 'title',
        body: mismatch == 'body' ? 'other' : 'body',
        created: mismatch == 'old'
            ? attempt.subtract(const Duration(days: 1))
            : mismatch == 'future'
            ? attempt.add(const Duration(hours: 1))
            : attempt,
      );
      final service = serviceFor(
        (request) => request.path.endsWith('/topics')
            ? {
                'data': [wrong, if (mismatch == 'ambiguous') topic(id: 43)],
              }
            : request.path.endsWith('/43')
            ? topic(id: 43)
            : wrong,
      );
      expect(
        await service.findSubmittedGroupTopic(
          slug: 'demo',
          title: 'title',
          content: 'body',
          attemptedAt: attempt,
        ),
        isNull,
      );
    });
  }

  test('account change during readback discards the old response', () async {
    final detail = Completer<Object?>();
    final started = Completer<void>();
    final service = serviceFor((request) {
      if (request.path.endsWith('/42')) {
        started.complete();
        return detail.future;
      }
      return {
        'data': [topic()],
      };
    });
    final pending = service.findSubmittedGroupTopic(
      slug: 'demo',
      title: 'title',
      content: 'body',
      attemptedAt: attempt,
    );
    await started.future;
    service.setCurrentUsername('bob');
    final assertion = expectLater(pending, throwsA(isA<FormatException>()));
    detail.complete(topic());
    await assertion;
  });

  test(
    'pending receipt survives restart and legacy drafts keep their body',
    () {
      final draft = CommunityTopicDraft()
        ..attemptedAt = attempt
        ..confirmedId = 42;
      final restored = CommunityTopicDraft();
      expect(restored.restore(draft.encode('[b]body[/b]')), '[b]body[/b]');
      expect(restored.pending, true);
      expect(restored.confirmedId, 42);
      expect(restored.attemptedAt, attempt);
      expect(
        CommunityTopicDraft().restore('plain legacy body'),
        'plain legacy body',
      );
    },
  );
}
