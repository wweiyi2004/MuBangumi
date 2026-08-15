import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/auth/website_session.dart';
import 'package:mubangumi/core/network/community_service.dart';
import 'package:mubangumi/models/community_models.dart';

void main() {
  test(
    'me timeline keeps items whose user object is omitted by the API',
    () async {
      final service = _service(
        (options) => Response<List<dynamic>>(
          requestOptions: options,
          statusCode: 200,
          data: [
            {
              'id': 71228734,
              'uid': 763686,
              'cat': 4,
              'type': 2,
              'createdAt': 1786588552,
              'memo': {
                'progress': {
                  'single': {
                    'episode': {
                      'id': 1656013,
                      'subjectID': 590353,
                      'sort': 6,
                      'type': 0,
                      'name': 'EP',
                    },
                    'subject': {
                      'id': 590353,
                      'name': 'Example',
                      'nameCN': '示例动画',
                      'type': 2,
                    },
                  },
                },
              },
            },
          ],
        ),
      );
      service.setCurrentUsername(
        'wweiyi',
        nickname: '维依',
        avatarUrl: 'https://lain.bgm.tv/pic/user/l/me.jpg',
      );

      final items = await service.loadTimeline(CommunityTimelineMode.me);

      expect(items, hasLength(1));
      expect(items.single.user.username, 'wweiyi');
      expect(items.single.user.displayName, '维依');
      expect(
        items.single.user.avatarUrl,
        'https://lain.bgm.tv/pic/user/l/me.jpg',
      );
      expect(items.single.description, '看过 示例动画 EP.6');
    },
  );

  test(
    'user profile timeline keeps user-less items with the profile username',
    () async {
      final service = _service(
        (options) => Response<List<dynamic>>(
          requestOptions: options,
          statusCode: 200,
          data: [
            {
              'id': 42,
              'uid': 7,
              'cat': 5,
              'type': 1,
              'createdAt': 1786588552,
              'memo': {
                'status': {'tsukkomi': '你好'},
              },
            },
          ],
        ),
      );

      final items = await service.loadUserTimeline(
        'alice',
        fallbackAvatarUrl: 'https://lain.bgm.tv/pic/user/l/alice.jpg',
      );

      expect(items, hasLength(1));
      expect(items.single.user.id, 7);
      expect(items.single.user.username, 'alice');
      expect(items.single.user.displayName, 'alice');
      expect(
        items.single.user.avatarUrl,
        'https://lain.bgm.tv/pic/user/l/alice.jpg',
      );
      expect(items.single.description, '发表了吐槽');
    },
  );

  test(
    'user profile timeline synthesizes an avatar from uid when none is given',
    () async {
      final service = _service(
        (options) => Response<List<dynamic>>(
          requestOptions: options,
          statusCode: 200,
          data: [
            {
              'id': 42,
              'uid': 7,
              'cat': 5,
              'type': 1,
              'createdAt': 1786588552,
              'memo': {
                'status': {'tsukkomi': '你好'},
              },
            },
          ],
        ),
      );

      final items = await service.loadUserTimeline('alice');

      expect(
        items.single.user.avatarUrl,
        'https://lain.bgm.tv/pic/user/l/000/00/00/7.jpg',
      );
    },
  );

  test('user timeline forwards until for deep-link paging', () async {
    RequestOptions? seen;
    final service = _service((options) {
      seen = options;
      return Response<List<dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: const [],
      );
    });

    await service.loadUserTimeline('alice', until: 100);

    expect(seen?.path, '/p1/users/alice/timeline');
    expect(seen?.queryParameters['until'], 100);
  });

  test(
    'cached me timeline keeps user-less items with the signed-in identity',
    () {
      final service = CommunityService.test();
      service.setCurrentUsername(
        'wweiyi',
        nickname: '维依',
        avatarUrl: 'https://lain.bgm.tv/pic/user/l/me.jpg',
      );

      final items = service.decodeCachedTimeline(CommunityTimelineMode.me, [
        {
          'id': 71228734,
          'uid': 763686,
          'cat': 4,
          'type': 2,
          'createdAt': 1786588552,
          'memo': {
            'progress': {
              'single': {
                'episode': {
                  'id': 1656013,
                  'subjectID': 590353,
                  'sort': 6,
                  'type': 0,
                  'name': 'EP',
                },
                'subject': {
                  'id': 590353,
                  'name': 'Example',
                  'nameCN': '示例动画',
                  'type': 2,
                },
              },
            },
          },
        },
      ]);

      expect(items, hasLength(1));
      expect(items.single.user.id, 763686);
      expect(items.single.user.username, 'wweiyi');
      expect(items.single.user.displayName, '维依');
      expect(
        items.single.user.avatarUrl,
        'https://lain.bgm.tv/pic/user/l/me.jpg',
      );
      expect(items.single.description, '看过 示例动画 EP.6');
    },
  );

  test(
    'addFriend PUTs an empty JSON object to /p1/friends/{username}',
    () async {
      RequestOptions? seen;
      final service = _service((options) {
        seen = options;
        return Response<Map<String, dynamic>>(
          requestOptions: options,
          statusCode: 200,
          data: const {},
        );
      });
      service.setAccessToken('token');

      await service.addFriend('alice');

      expect(seen?.method, 'PUT');
      expect(seen?.path, '/p1/friends/alice');
      expect(seen?.data, const <String, dynamic>{});
    },
  );

  test('acceptFriendRequest targets only the notice sender', () async {
    RequestOptions? seen;
    final service = _service((options) {
      seen = options;
      return Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: const {},
      );
    });
    service.setAccessToken('token');
    final notice = BangumiNotice(
      id: 42,
      title: '爱丽丝',
      type: 14,
      mainId: 7,
      relatedId: 0,
      unread: true,
      createdAt: DateTime(2026),
      sender: const CommunityUser(id: 7, username: 'alice', nickname: '爱丽丝'),
    );

    await service.acceptFriendRequest(notice);

    expect(seen?.method, 'PUT');
    expect(seen?.path, '/p1/friends/alice');
    expect(seen?.data, const <String, dynamic>{});
  });

  test('acceptFriendRequest rejects unrelated notifications', () async {
    final service = _service((options) {
      fail('No request should be sent');
    });
    service.setAccessToken('token');
    final notice = BangumiNotice(
      id: 42,
      title: '测试话题',
      type: 1,
      mainId: 1,
      relatedId: 2,
      unread: true,
      createdAt: DateTime(2026),
      sender: const CommunityUser(id: 7, username: 'alice', nickname: '爱丽丝'),
    );

    await expectLater(
      service.acceptFriendRequest(notice),
      throwsA(isA<FormatException>()),
    );
  });

  test('isFriend reads the official profile flag', () async {
    final service = _service(
      (options) => Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: {
          'id': 7,
          'username': 'alice',
          'nickname': 'Alice',
          'isFriend': true,
        },
      ),
    );
    service.setAccessToken('token');
    service.setCurrentUsername('wweiyi');

    expect(await service.isFriend('alice'), isTrue);
  });

  test(
    'loadFriends accepts SlimUser rows from /users/{name}/friends',
    () async {
      final service = _service(
        (options) => Response<Map<String, dynamic>>(
          requestOptions: options,
          statusCode: 200,
          data: {
            'total': 1,
            'data': [
              {
                'id': 7,
                'username': 'alice',
                'nickname': 'Alice',
                'avatar': {'large': 'https://lain.bgm.tv/a.jpg'},
              },
            ],
          },
        ),
      );

      final page = await service.loadFriends('wweiyi');
      expect(page.data.single.username, 'alice');
      expect(page.data.single.displayName, 'Alice');
    },
  );

  test('loadFriends unwraps nested friend.user objects', () async {
    final service = _service(
      (options) => Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: {
          'total': 1,
          'data': [
            {
              'user': {
                'id': 7,
                'username': 'alice',
                'nickname': 'Alice',
                'avatar': {'large': 'https://lain.bgm.tv/a.jpg'},
              },
            },
          ],
        },
      ),
    );

    final page = await service.loadFriends('wweiyi');
    expect(page.data.single.username, 'alice');
  });

  test(
    'loadNoticeContents fetches a topic once and extracts replies',
    () async {
      var calls = 0;
      RequestOptions? seen;
      final service = _service((options) {
        calls++;
        seen = options;
        return Response<Map<String, dynamic>>(
          requestOptions: options,
          statusCode: 200,
          data: {
            'id': 1001,
            'title': '测试话题',
            'group': {'id': 9, 'name': 'test', 'title': '测试小组'},
            'replies': [
              {
                'id': 2002,
                'content': '这就是通知里的具体回复。',
                'createdAt': 1785986029,
                'creator': {'id': 7, 'username': 'alice', 'nickname': '爱丽丝'},
                'replies': <Object?>[],
              },
              {
                'id': 2003,
                'content': r'[img]https://lain.bgm.tv/example.jpg[/img]',
                'createdAt': 1785986030,
                'creator': {'id': 8, 'username': 'bob', 'nickname': '鲍勃'},
                'replies': <Object?>[],
              },
            ],
          },
        );
      });
      final notices = [
        BangumiNotice(
          id: 42,
          title: '测试话题',
          type: 1,
          mainId: 1001,
          relatedId: 2002,
          unread: true,
          createdAt: DateTime(2026),
        ),
        BangumiNotice(
          id: 43,
          title: '测试话题',
          type: 2,
          mainId: 1001,
          relatedId: 2003,
          unread: true,
          createdAt: DateTime(2026),
        ),
      ];

      final contents = await service.loadNoticeContents(notices);

      expect(calls, 1);
      expect(seen?.path, '/p1/groups/-/topics/1001');
      expect(contents[42], '这就是通知里的具体回复。');
      expect(contents[43], '（图片回复）');
    },
  );

  test('replyToTopic sends the official P1 reply contract', () async {
    RequestOptions? seen;
    final service = _service((options) {
      seen = options;
      return Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: const {'id': 456},
      );
    });
    service.setAccessToken('oauth-token');
    final token = '0.${'a' * 80}';

    await service.replyToTopic(
      topic: const CommunityTopic(
        id: 123,
        kind: CommunityTopicKind.group,
        title: '测试话题',
        url: 'https://bgm.tv/rakuen/topic/group/123',
        webUrl: 'https://bgm.tv/group/topic/123',
      ),
      content: '  测试回复  ',
      turnstileToken: token,
      replyTo: 321,
    );

    expect(seen?.method, 'POST');
    expect(seen?.path, '/p1/groups/-/topics/123/replies');
    expect(seen?.headers['Authorization'], 'Bearer oauth-token');
    expect(seen?.data, {
      'content': '测试回复',
      'turnstileToken': token,
      'replyTo': 321,
    });
  });

  test(
    'updatePostReaction uses the official like and unlike contracts',
    () async {
      final seen = <RequestOptions>[];
      final service = _service((options) {
        seen.add(options);
        return Response<Map<String, dynamic>>(
          requestOptions: options,
          statusCode: 200,
          data: const {},
        );
      });
      service.setAccessToken('oauth-token');
      const topic = CommunityTopic(
        id: 123,
        kind: CommunityTopicKind.group,
        title: '测试话题',
        url: 'https://bgm.tv/rakuen/topic/group/123',
        webUrl: 'https://bgm.tv/group/topic/123',
      );
      const post = CommunityPost(id: 'post_456', author: 'Alice', body: '正文');

      await service.updatePostReaction(topic: topic, post: post, value: 54);
      await service.updatePostReaction(topic: topic, post: post, value: null);

      expect(seen, hasLength(2));
      expect(seen[0].method, 'PUT');
      expect(seen[0].path, '/p1/groups/-/posts/456/like');
      expect(seen[0].data, const {'value': 54});
      expect(seen[1].method, 'DELETE');
      expect(seen[1].path, '/p1/groups/-/posts/456/like');
    },
  );

  test('reply does not burn the one-shot token on a captcha 401', () async {
    var requests = 0;
    var refreshes = 0;
    final service = _errorService(
      statusCode: 401,
      body: const {
        'statusCode': 401,
        'code': 'CAPTCHA_ERROR',
        'error': 'Unauthorized',
        'message': 'wrong captcha',
      },
      onRequest: () => requests++,
    );
    service.setAccessToken('oauth-token');
    service.onUnauthorizedRefresh = () async {
      refreshes++;
      return true;
    };

    await expectLater(
      service.replyToTopic(
        topic: _groupTopic,
        content: '测试回复',
        turnstileToken: 'turnstile-token',
      ),
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          'message',
          contains('人机验证失败或已过期'),
        ),
      ),
    );
    expect(requests, 1);
    expect(refreshes, 0);
  });

  test('private-group reply falls back to the classic website form', () async {
    var p1Requests = 0;
    final p1 = Dio(BaseOptions(baseUrl: 'https://next.bgm.tv'));
    p1.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          p1Requests++;
          handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.badResponse,
              response: Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 401,
                data: const {
                  'statusCode': 401,
                  'code': 'NOT_JOIN_PRIVATE_GROUP_ERROR',
                  'error': 'Unauthorized',
                  'message':
                      "you need to join private group '测试小组' before you create a post or reply",
                },
              ),
            ),
          );
        },
      ),
    );
    RequestOptions? formPost;
    final html = Dio(BaseOptions(baseUrl: 'https://bgm.tv'));
    html.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.method == 'GET') {
            handler.resolve(
              Response<String>(
                requestOptions: options,
                statusCode: 200,
                data:
                    '<html><body><form method="post" '
                    'action="/group/topic/123/new_reply">'
                    '<input type="hidden" name="formhash" value="abc12345">'
                    '</form></body></html>',
              ),
            );
            return;
          }
          formPost = options;
          handler.resolve(
            Response<String>(
              requestOptions: options,
              statusCode: 200,
              data: '{"posts":{"main":{"9":{}}}}',
            ),
          );
        },
      ),
    );
    final service = CommunityService.test(
      p1Dio: p1,
      htmlDio: html,
      sessionStore: _memorySessionStore(),
    );
    service.setAccessToken('oauth-token');

    await service.replyToTopic(
      topic: _groupTopic,
      content: '测试回复',
      turnstileToken: 'turnstile-token',
      replyTo: 456,
    );

    expect(p1Requests, 1);
    expect(formPost?.path, contains('/group/topic/123/new_reply'));
    expect(formPost?.data, containsPair('formhash', 'abc12345'));
    expect(formPost?.data, containsPair('content', '测试回复'));
    expect(formPost?.data, containsPair('submit', 'submit'));
    expect(formPost?.data, containsPair('topic_id', '123'));
    expect(formPost?.data, containsPair('related', '456'));
  });

  test('private-group fallback explains the missing website session', () async {
    final p1 = Dio(BaseOptions(baseUrl: 'https://next.bgm.tv'));
    p1.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) => handler.reject(
          DioException(
            requestOptions: options,
            type: DioExceptionType.badResponse,
            response: Response<Map<String, dynamic>>(
              requestOptions: options,
              statusCode: 401,
              data: const {
                'statusCode': 401,
                'code': 'NOT_JOIN_PRIVATE_GROUP_ERROR',
                'error': 'Unauthorized',
                'message':
                    "you need to join private group '测试小组' before you create a post or reply",
              },
            ),
          ),
        ),
      ),
    );
    final html = Dio(BaseOptions(baseUrl: 'https://bgm.tv'));
    html.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) =>
            fail('No website request should be sent without a session'),
      ),
    );
    final service = CommunityService.test(
      p1Dio: p1,
      htmlDio: html,
      sessionStore: _MemoryWebsiteSessionStore(),
    );
    service.setAccessToken('oauth-token');

    await expectLater(
      service.replyToTopic(
        topic: _groupTopic,
        content: '测试回复',
        turnstileToken: 'turnstile-token',
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('同步网站登录'),
        ),
      ),
    );
  });

  test('credential 401 still refreshes the OAuth token and retries', () async {
    var requests = 0;
    var refreshes = 0;
    final dio = Dio(BaseOptions(baseUrl: 'https://next.bgm.tv'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests++;
          if (requests == 1) {
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.badResponse,
                response: Response<Map<String, dynamic>>(
                  requestOptions: options,
                  statusCode: 401,
                  data: const {
                    'statusCode': 401,
                    'code': 'NEED_LOGIN',
                    'error': 'Unauthorized',
                    'message': 'you need to login before creating a reply',
                  },
                ),
              ),
            );
            return;
          }
          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: options,
              statusCode: 200,
              data: const {'id': 1},
            ),
          );
        },
      ),
    );
    final service = CommunityService.test(p1Dio: dio);
    service.setAccessToken('oauth-token');
    service.onUnauthorizedRefresh = () async {
      refreshes++;
      return true;
    };

    await service.replyToTopic(
      topic: _groupTopic,
      content: '测试回复',
      turnstileToken: 'turnstile-token',
    );

    expect(requests, 2);
    expect(refreshes, 1);
  });
}

const _groupTopic = CommunityTopic(
  id: 123,
  kind: CommunityTopicKind.group,
  title: '测试话题',
  url: 'https://bgm.tv/rakuen/topic/group/123',
  webUrl: 'https://bgm.tv/group/topic/123',
);

CommunityService _errorService({
  required int statusCode,
  required Map<String, dynamic> body,
  required void Function() onRequest,
}) {
  final dio = Dio(BaseOptions(baseUrl: 'https://next.bgm.tv'));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        onRequest();
        handler.reject(
          DioException(
            requestOptions: options,
            type: DioExceptionType.badResponse,
            response: Response<Map<String, dynamic>>(
              requestOptions: options,
              statusCode: statusCode,
              data: body,
            ),
          ),
        );
      },
    ),
  );
  return CommunityService.test(p1Dio: dio);
}

CommunityService _service(Response<Object?> Function(RequestOptions) respond) {
  final dio = Dio(BaseOptions(baseUrl: 'https://next.bgm.tv'));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) => handler.resolve(respond(options)),
    ),
  );
  return CommunityService.test(p1Dio: dio);
}

WebsiteSessionStore _memorySessionStore() =>
    _MemoryWebsiteSessionStore()
      ..snapshot = WebsiteSessionSnapshot(
        cookies: const [WebsiteCookie(name: 'chii_auth', value: 'cookie')],
        syncedAt: DateTime(2026),
      );

class _MemoryWebsiteSessionStore extends WebsiteSessionStore {
  WebsiteSessionSnapshot? snapshot;

  @override
  Future<WebsiteSessionSnapshot?> read() async => snapshot;

  @override
  Future<void> write(WebsiteSessionSnapshot snapshot) async {
    this.snapshot = snapshot;
  }

  @override
  Future<void> clear() async {
    snapshot = null;
  }
}
