import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/auth/website_session.dart';
import 'package:mubangumi/core/network/community_service.dart';
import 'package:mubangumi/core/storage/community_cache.dart';
import 'package:mubangumi/models/community_models.dart';
import 'package:mubangumi/models/community_topic_submission.dart';

const _title = '合成测试标题';
const _content = '合成测试正文';
const _alice = CommunityUser(id: 1, username: 'alice', nickname: 'Alice');
const _original = CommunityBlog(
  id: 42,
  title: _title,
  user: _alice,
  content: _content,
);

void main() {
  for (final group in [false, true]) {
    final kind = group ? 'group topic' : 'blog';
    for (final stage in ['list', 'detail']) {
      for (final outcome in ['failed', 'account_changed']) {
        test(
          '$kind 500 with $outcome during $stage reconciliation never posts again',
          () async {
            final fixture = _PublishFixture(
              group: group,
              stage: stage,
              outcome: outcome,
            );
            addTearDown(fixture.service.dispose);

            await expectLater(
              fixture.publish(),
              throwsA(
                group && outcome == 'account_changed'
                    ? isA<FormatException>()
                    : isA<CommunitySubmissionUncertain>(),
              ),
            );

            expect(fixture.apiWrites, 1);
            expect(fixture.websiteRequests, isEmpty);
            expect(fixture.cache.removed, isEmpty);
          },
        );
      }
    }
    test(
      '$kind malformed reconciliation response never starts a website write',
      () async {
        final fixture = _PublishFixture(group: group, outcome: 'malformed');
        addTearDown(fixture.service.dispose);
        await expectLater(
          fixture.publish(),
          throwsA(isA<CommunitySubmissionUncertain>()),
        );
        expect(fixture.apiWrites, 1);
        expect(fixture.websiteRequests, isEmpty);
      },
    );
    test(
      '$kind confirmed recent publication completes without another write',
      () async {
        final fixture = _PublishFixture(group: group, outcome: 'found');
        addTearDown(fixture.service.dispose);
        await fixture.publish();
        expect(fixture.apiWrites, 1);
        expect(fixture.websiteRequests, isEmpty);
      },
    );
    test(
      '$kind empty read-back after 500 remains uncertain and never posts again',
      () async {
        final fixture = _PublishFixture(group: group, outcome: 'empty');
        addTearDown(fixture.service.dispose);
        await expectLater(
          fixture.publish(),
          throwsA(isA<CommunitySubmissionUncertain>()),
        );
        expect(fixture.apiWrites, 1);
        expect(fixture.websiteRequests, isEmpty);
      },
    );
  }

  for (final editing in [false, true]) {
    test(
      'blog ${editing ? 'PATCH' : 'POST'} keeps cleanup scoped when the account changes during deletion',
      () async {
        final cache = _Cache();
        final api = Dio()
          ..interceptors.add(
            InterceptorsWrapper(
              onRequest: (request, handler) => handler.resolve(
                Response<Object?>(
                  requestOptions: request,
                  statusCode: 200,
                  data: {'id': 42},
                ),
              ),
            ),
          );
        final service = CommunityService.test(p1Dio: api, cache: cache)
          ..setAccessToken('synthetic-alice')
          ..setCurrentUsername('alice');
        addTearDown(service.dispose);
        cache.onRemove = () {
          if (cache.removed.length != 1) return;
          service.setCurrentUsername('bob');
          service.setAccessToken('synthetic-bob');
        };

        await expectLater(
          service.saveBlog(
            original: editing ? _original : null,
            title: _title,
            content: _content,
            tags: const [],
            isPublic: true,
            turnstileToken: 'synthetic',
          ),
          throwsA(isA<CommunitySubmissionUncertain>()),
        );
        expect(cache.removed, hasLength(CommunityTimelineMode.values.length));
        expect(cache.removed, everyElement(startsWith('community-v2:alice:')));
      },
    );
    for (final outcome in ['success', '500', '403', 'timeout']) {
      test(
        'blog ${editing ? 'PATCH' : 'POST'} late $outcome leaves the new account caches intact',
        () async {
          final cache = _Cache();
          final api = Dio(BaseOptions(baseUrl: 'https://next.bgm.tv'));
          late CommunityService service;
          var reads = 0, writes = 0, websiteRequests = 0;
          api.interceptors.add(
            InterceptorsWrapper(
              onRequest: (request, handler) async {
                if (request.method == 'GET') {
                  reads++;
                  handler.resolve(
                    Response<Map<String, dynamic>>(
                      requestOptions: request,
                      statusCode: 200,
                      data: _blog(77, username: 'bob'),
                    ),
                  );
                  return;
                }
                writes++;
                expect(request.method, editing ? 'PATCH' : 'POST');
                service.setCurrentUsername('bob');
                service.setAccessToken('synthetic-bob');
                // Populate B's cache while A's write response is still in flight.
                await service.loadBlog(77);
                if (outcome == 'success') {
                  handler.resolve(
                    Response<Object?>(
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
                          : Response<Object?>(
                              requestOptions: request,
                              statusCode: int.parse(outcome),
                              data: {
                                'message':
                                    'internal error, please contact admin',
                              },
                            ),
                    ),
                  );
                }
              },
            ),
          );
          final website = Dio()
            ..interceptors.add(
              InterceptorsWrapper(
                onRequest: (request, handler) {
                  websiteRequests++;
                  handler.resolve(
                    Response<String>(
                      requestOptions: request,
                      statusCode: 200,
                      data: '',
                    ),
                  );
                },
              ),
            );
          service =
              CommunityService.test(p1Dio: api, htmlDio: website, cache: cache)
                ..setAccessToken('synthetic-alice')
                ..setCurrentUsername('alice');
          addTearDown(service.dispose);

          await expectLater(
            service.saveBlog(
              original: editing ? _original : null,
              title: _title,
              content: _content,
              tags: const [],
              isPublic: true,
              turnstileToken: 'synthetic',
            ),
            throwsA(isA<CommunitySubmissionUncertain>()),
          );
          expect((await service.loadBlog(77)).user.username, 'bob');
          expect(
            reads,
            1,
            reason:
                'The rejected old response must not clear B\'s in-memory cache.',
          );
          expect(
            cache.removed,
            isEmpty,
            reason:
                'The rejected old response must not clear B\'s persistent timeline.',
          );
          expect(writes, 1);
          expect(websiteRequests, 0);
        },
      );
    }
  }
}

Map<String, dynamic> _blog(int id, {String username = 'alice'}) => {
  'id': id,
  'title': _title,
  'content': _content,
  'createdAt': DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
  'user': {'id': username == 'alice' ? 1 : 2, 'username': username},
};

Map<String, dynamic> _topic() => {
  'id': 42,
  'title': _title,
  'createdAt': DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
  'creator': {'id': 1, 'username': 'alice'},
  'group': {'name': 'fixture'},
  'replies': [
    {
      'content': _content,
      'creator': {'id': 1, 'username': 'alice'},
    },
  ],
};

class _PublishFixture {
  _PublishFixture({
    required this.group,
    this.stage = 'list',
    required this.outcome,
  }) {
    final api = Dio(BaseOptions(baseUrl: 'https://next.bgm.tv'));
    api.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          if (request.method == 'POST') {
            apiWrites++;
            handler.reject(
              DioException(
                requestOptions: request,
                type: DioExceptionType.badResponse,
                response: Response<Object?>(
                  requestOptions: request,
                  statusCode: 500,
                  data: {'message': 'internal error, please contact admin'},
                ),
              ),
            );
            return;
          }
          final list = request.path.endsWith(group ? '/topics' : '/blogs');
          if (list == (stage == 'list')) {
            if (outcome == 'account_changed') {
              service.setCurrentUsername('bob');
              service.setAccessToken('synthetic-bob');
            } else if (outcome == 'failed') {
              handler.reject(
                DioException(
                  requestOptions: request,
                  type: DioExceptionType.badResponse,
                  response: Response<Object?>(
                    requestOptions: request,
                    statusCode: 403,
                    data: {},
                  ),
                ),
              );
              return;
            }
          }
          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: request,
              statusCode: 200,
              data: list
                  ? {
                      'total': outcome == 'empty' ? 0 : 1,
                      'data': outcome == 'malformed'
                          ? 'invalid list'
                          : [
                              if (outcome != 'empty')
                                group ? _topic() : _blog(42),
                            ],
                    }
                  : group
                  ? _topic()
                  : _blog(42),
            ),
          );
        },
      ),
    );
    final website = Dio(BaseOptions(baseUrl: 'https://bgm.tv'));
    website.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          websiteRequests.add(request);
          handler.resolve(
            Response<String>(
              requestOptions: request,
              statusCode: request.method == 'POST' ? 302 : 200,
              headers: Headers.fromMap({
                'location': [group ? '/group/topic/42' : '/blog/42'],
              }),
              data: request.method == 'POST'
                  ? ''
                  : '<form action="${group ? '/group/fixture/topic/new' : '/blog/create'}">'
                        '<input name="title"><textarea name="content"></textarea>'
                        '<input name="formhash" value="synthetic"></form>',
            ),
          );
        },
      ),
    );
    service = CommunityService.test(p1Dio: api, htmlDio: website, cache: cache)
      ..setAccessToken('synthetic-alice')
      ..setCurrentUsername('alice');
    service.websiteSessionGuard = () async => WebsiteSessionSnapshot(
      cookies: [
        WebsiteCookie(name: 'chii_auth', value: service.currentUsername!),
      ],
      syncedAt: DateTime.now(),
    );
  }

  final bool group;
  final String stage, outcome;
  final cache = _Cache();
  final websiteRequests = <RequestOptions>[];
  int apiWrites = 0;
  late final CommunityService service;

  Future<void> publish() async {
    if (group) {
      final topic = await service.createGroupTopic(
        slug: 'fixture',
        title: _title,
        content: _content,
        turnstileToken: 'synthetic',
      );
      expect(topic.id, 42);
    } else {
      await service.saveBlog(
        title: _title,
        content: _content,
        tags: const [],
        isPublic: true,
        turnstileToken: 'synthetic',
      );
    }
  }
}

class _Cache implements CommunityCache {
  final removed = <String>[];
  void Function()? onRemove;
  @override
  Future<void> remove(String key) async {
    removed.add(key);
    onRemove?.call();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
