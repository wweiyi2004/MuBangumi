import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/network/community_service.dart';
import 'package:mubangumi/models/community_models.dart';
import 'package:mubangumi/screens/community_group_browse_screen.dart';

CommunityTopic topic(CommunityTopicKind kind) => CommunityTopic(
  id: 42,
  kind: kind,
  title: '讨论',
  url: '',
  webUrl: 'https://bgm.tv/${kind.name}/42',
);
const ownPost = CommunityPost(
  id: '7',
  author: 'Alice',
  userUrl: 'https://bgm.tv/user/alice',
  body: '原文',
  rawBody: '[b]原文[/b]',
  canEdit: true,
);

CommunityService serviceWith(Object Function(RequestOptions) response) {
  final dio = Dio(BaseOptions(baseUrl: 'https://next.bgm.tv'));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        handler.resolve(
          Response(
            requestOptions: options,
            statusCode: 200,
            data: response(options),
          ),
        );
      },
    ),
  );
  return CommunityService.test(p1Dio: dio)
    ..setAccessToken('test')
    ..setCurrentUsername('alice');
}

void main() {
  testWidgets(
    'account change clears group content and ignores the old response',
    (tester) async {
      final service = _AccountGroupService()..setCurrentUsername('alice');
      await tester.pumpWidget(
        MaterialApp(
          home: CommunityGroupBrowseScreen(
            group: const CommunityGroup(
              id: 1,
              slug: 'test',
              name: '测试小组',
              url: 'https://bgm.tv/group/test',
            ),
            service: service,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('alice的内容'), findsOneWidget);
      service.pending = Completer<CommunityPageResult<CommunityTopic>>();
      final refresh = tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh();
      await tester.pump();
      service.setCurrentUsername('bob');
      await tester.pump();
      service.pending!.complete(service.page('alice'));
      await refresh;
      await tester.pumpAndSettle();
      expect(find.text('alice的内容'), findsNothing);
      expect(find.text('bob的内容'), findsOneWidget);
    },
  );
  testWidgets('failed refresh of a populated group retries the first page', (
    tester,
  ) async {
    final service = _GroupService()..fail = false;
    await tester.pumpWidget(
      MaterialApp(
        home: CommunityGroupBrowseScreen(
          group: const CommunityGroup(
            id: 1,
            slug: 'test',
            name: '测试小组',
            url: 'https://bgm.tv/group/test',
          ),
          service: service,
        ),
      ),
    );
    await tester.pumpAndSettle();
    service.failRefresh = true;
    await tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    await tester.pumpAndSettle();
    service.failRefresh = false;
    await tester.tap(find.text('加载失败，点击重试'));
    await tester.pumpAndSettle();
    expect(service.offsets, [0, 0, 0]);
  });
  test(
    'edits topic title and BBCode; deletes only replies owned by current user',
    () async {
      final requests = <RequestOptions>[];
      final service = serviceWith((options) {
        requests.add(options);
        return <String, dynamic>{};
      });
      const original = CommunityPost(
        id: '6',
        author: 'Alice',
        userUrl: 'https://bgm.tv/user/alice',
        body: '原文',
        rawBody: '[b]原文[/b]',
        canEdit: true,
        isOriginal: true,
      );
      await service.editPost(
        topic: topic(CommunityTopicKind.group),
        post: original,
        title: '修改标题',
        content: '[mask]新内容[/mask]',
      );
      expect(requests.single.method, 'PUT');
      expect(requests.single.path, '/p1/groups/-/topics/42');
      expect(requests.single.data, {
        'title': '修改标题',
        'content': '[mask]新内容[/mask]',
      });
      await service.editPost(
        topic: topic(CommunityTopicKind.subject),
        post: ownPost,
        content: '修改回复',
      );
      expect(requests.last.path, '/p1/subjects/-/posts/7');
      await service.deletePost(
        topic: topic(CommunityTopicKind.group),
        post: ownPost,
      );
      expect(requests.last.path, '/p1/groups/-/posts/7');
      expect(requests.last.method, 'DELETE');
      await expectLater(
        service.deletePost(
          topic: topic(CommunityTopicKind.group),
          post: original,
        ),
        throwsFormatException,
      );
      service.setCurrentUsername('bob');
      await expectLater(
        service.editPost(
          topic: topic(CommunityTopicKind.group),
          post: ownPost,
          content: 'wrong',
        ),
        throwsFormatException,
      );
      await expectLater(
        service.deletePost(
          topic: topic(CommunityTopicKind.group),
          post: ownPost,
        ),
        throwsFormatException,
      );
      expect(requests, hasLength(3));
    },
  );

  for (final (kind, area) in [
    (CommunityTopicKind.episode, 'episodes'),
    (CommunityTopicKind.character, 'characters'),
    (CommunityTopicKind.person, 'persons'),
    (CommunityTopicKind.blog, 'blogs'),
  ]) {
    test(
      '$area reads real comment shape and supports reply edit delete',
      () async {
        final requests = <RequestOptions>[];
        final service = serviceWith((options) {
          requests.add(options);
          if (options.method == 'GET' && options.path.endsWith('/comments')) {
            return <dynamic>[
              {
                'id': 7,
                'creatorID': 1,
                'user': {'id': 1, 'username': 'alice', 'nickname': 'Alice'},
                'content': '[b]原文[/b]',
                'state': 0,
                'createdAt': 1789567904,
                'replies': [
                  {
                    'id': 8,
                    'user': {'id': 2, 'username': 'bob'},
                    'content': '嵌套回复',
                    'createdAt': 1789567905,
                  },
                ],
              },
            ];
          }
          return <String, dynamic>{'title': '日志', 'content': '[b]日志正文[/b]'};
        });
        final detail = await service.loadTopic(topic(kind));
        final first = detail.posts.firstWhere((post) => post.id == '7');
        expect(first.isOriginal, isFalse);
        expect(first.rawBody, '[b]原文[/b]');
        expect(service.canManagePost(topic(kind), first), isTrue);
        expect(detail.posts.last.isNested, isTrue);
        await service.replyToTopic(
          topic: topic(kind),
          content: '回复',
          turnstileToken: 'verified',
          replyTo: 7,
        );
        expect(requests.last.path, '/p1/$area/42/comments');
        expect(requests.last.data['replyTo'], 7);
        await service.editPost(topic: topic(kind), post: first, content: '修改');
        expect(requests.last.path, '/p1/$area/-/comments/7');
        await service.deletePost(topic: topic(kind), post: first);
        expect(requests.last.method, 'DELETE');
        expect(requests.last.path, '/p1/$area/-/comments/7');
      },
    );
  }

  test(
    'creates subject discussion and rejects unsafe or unsupported actions locally',
    () async {
      final requests = <RequestOptions>[];
      final service = serviceWith((options) {
        requests.add(options);
        return <String, dynamic>{};
      });
      await service.createSubjectTopic(
        subjectId: 42,
        title: '新讨论',
        content: '[b]正文[/b]',
        turnstileToken: 'verified',
      );
      expect(requests.single.path, '/p1/subjects/42/topics');
      expect(requests.single.data['turnstileToken'], 'verified');
      await expectLater(
        service.createSubjectTopic(
          subjectId: 42,
          title: '',
          content: '内容',
          turnstileToken: 'verified',
        ),
        throwsFormatException,
      );
      await expectLater(
        service.updatePostReaction(
          topic: topic(CommunityTopicKind.person),
          post: ownPost,
          value: 54,
        ),
        throwsFormatException,
      );
      await expectLater(
        service.replyToTopic(
          topic: topic(CommunityTopicKind.unknown),
          content: '内容',
          turnstileToken: 'verified',
        ),
        throwsFormatException,
      );
      expect(requests, hasLength(1));
    },
  );

  test(
    'aggregate list slices one bounded snapshot without repeating its first page',
    () async {
      var calls = 0;
      final service = serviceWith((options) {
        calls++;
        expect(options.path, '/p1/rakuen/topics');
        expect(options.queryParameters, {'type': 'character', 'limit': 200});
        return {
          'total': 900,
          'data': [
            for (var id = 1; id <= 25; id++)
              {
                'id': id,
                'type': 'character',
                'name': '角色$id',
                'nameCN': '',
                'comment': 2,
                'updatedAt': 1789567904,
              },
          ],
        };
      });
      final first = await service.loadTopicPage(RakuenMode.characterLatest);
      final next = await service.loadTopicPage(
        RakuenMode.characterLatest,
        offset: 20,
      );
      expect(first.data, hasLength(20));
      expect(next.data.map((item) => item.id), [21, 22, 23, 24, 25]);
      expect(next.data.first.kind, CommunityTopicKind.character);
      expect(first.total, 25);
      expect(calls, 1);
    },
  );

  for (final members in [false, true]) {
    testWidgets(
      'group ${members ? 'members' : 'topics'} advances raw offsets and retries failed pages',
      (tester) async {
        final service = _GroupService();
        await tester.pumpWidget(
          MaterialApp(
            home: CommunityGroupBrowseScreen(
              group: const CommunityGroup(
                id: 1,
                slug: 'test',
                name: '测试小组',
                url: 'https://bgm.tv/group/test',
              ),
              service: service,
              members: members,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(members ? '用户1' : '话题1'), findsOneWidget);
        await tester.tap(find.text('加载更多'));
        await tester.pumpAndSettle();
        expect(find.text('加载失败，点击重试'), findsOneWidget);
        expect(find.text(members ? '用户1' : '话题1'), findsOneWidget);
        service.fail = false;
        await tester.tap(find.text('加载失败，点击重试'));
        await tester.pumpAndSettle();
        expect(find.text(members ? '用户2' : '话题2'), findsOneWidget);
        expect(service.offsets, [0, 2, 2]);
        expect(find.text('已经到底了'), findsOneWidget);
      },
    );
  }
}

class _AccountGroupService extends CommunityService {
  _AccountGroupService() : super.test();
  Completer<CommunityPageResult<CommunityTopic>>? pending;
  CommunityPageResult<CommunityTopic> page(String account) =>
      CommunityPageResult(
        total: 1,
        data: [
          CommunityTopic(
            id: 1,
            kind: CommunityTopicKind.group,
            title: '$account的内容',
            url: '',
            webUrl: '',
          ),
        ],
      );
  @override
  Future<CommunityPageResult<CommunityTopic>> loadGroupTopics(
    String slug, {
    int offset = 0,
    int limit = 20,
    bool refresh = false,
  }) async => currentUsername == 'alice' && pending != null
      ? await pending!.future
      : page(currentUsername!);
}

class _GroupService extends CommunityService {
  _GroupService() : super.test();
  bool fail = true;
  bool failRefresh = false;
  final offsets = <int>[];
  void record(int offset) {
    offsets.add(offset);
    if ((offset > 0 && fail) || (offset == 0 && failRefresh)) {
      throw StateError('offline');
    }
  }

  @override
  Future<CommunityPageResult<CommunityTopic>> loadGroupTopics(
    String slug, {
    int offset = 0,
    int limit = 20,
    bool refresh = false,
  }) async {
    record(offset);
    return CommunityPageResult(
      total: 4,
      rawCount: 2,
      data: [
        for (final id in offset == 0 ? [1] : [1, 2])
          CommunityTopic(
            id: id,
            kind: CommunityTopicKind.group,
            title: '话题$id',
            url: '',
            webUrl: '',
          ),
      ],
    );
  }

  @override
  Future<CommunityPageResult<CommunityUser>> loadGroupMembers(
    String slug, {
    int offset = 0,
    int limit = 20,
    int? role,
    bool refresh = false,
  }) async {
    record(offset);
    return CommunityPageResult(
      total: 4,
      rawCount: 2,
      data: [
        for (final id in offset == 0 ? [1] : [1, 2])
          CommunityUser(id: id, username: 'u$id', nickname: '用户$id'),
      ],
    );
  }
}
