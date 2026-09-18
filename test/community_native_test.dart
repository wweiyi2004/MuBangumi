import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/network/community_p1_parser.dart';
import 'package:mubangumi/core/network/community_service.dart';
import 'package:mubangumi/core/storage/community_draft_store.dart';
import 'package:mubangumi/models/community_models.dart';
import 'package:mubangumi/screens/community_blog_screen.dart';
import 'package:mubangumi/screens/community_timeline_page.dart';
import 'package:mubangumi/widgets/community_composer.dart';
import 'package:mubangumi/widgets/community_widgets.dart';
import 'package:mubangumi/widgets/mono_collection_button.dart';

const alice = CommunityUser(id: 1, username: 'alice', nickname: 'Alice');
const privateBlog = CommunityBlog(
  id: 42,
  title: '原始标题',
  user: alice,
  content: '[b]原文[/b]',
  tags: ['测试'],
  isPublic: false,
);
CommunityTimelineItem status({
  String username = 'alice',
  bool isStatus = true,
}) => CommunityTimelineItem(
  id: 8,
  user: CommunityUser(id: 1, username: username, nickname: username),
  description: '发表了吐槽',
  content: '动态正文',
  createdAt: DateTime(2026),
  isStatus: isStatus,
);

CommunityService serviceWith(Object Function(RequestOptions) respond) {
  final dio = Dio(BaseOptions(baseUrl: 'https://next.bgm.tv'));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        try {
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: respond(options),
            ),
          );
        } on DioException catch (error) {
          handler.reject(error);
        }
      },
    ),
  );
  return CommunityService.test(p1Dio: dio)
    ..setAccessToken('test')
    ..setCurrentUsername('alice');
}

void main() {
  testWidgets(
    'late favorite state from the old account cannot replace the new account',
    (tester) async {
      final service = _SlowMonoService()
        ..setAccessToken('test')
        ..setCurrentUsername('alice');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MonoCollectionButton(
              kind: CommunityTimelineTargetKind.person,
              id: 7,
              service: service,
            ),
          ),
        ),
      );
      await tester.pump();
      service.setCurrentUsername('bob');
      await tester.pumpAndSettle();
      service.pending.complete(
        const CommunityMonoCollection(collected: true, count: 30),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);
      expect(find.byIcon(Icons.favorite), findsNothing);
    },
  );
  testWidgets(
    'timeline reaction failure preserves state and account switching resets actions',
    (tester) async {
      final service = _UiService()
        ..setCurrentUsername('alice')
        ..setAccessToken('test')
        ..failReaction = true;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(body: CommunityTimelinePage(service: service)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> react() async {
        await tester.tap(find.byKey(const ValueKey('post-reaction-picker')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('reaction-option-54')));
        await tester.pumpAndSettle();
      }

      await react();
      expect(
        tester
            .widget<CommunityTimelineCard>(find.byType(CommunityTimelineCard))
            .item
            .reactions,
        isEmpty,
      );
      service.failReaction = false;
      await react();
      expect(
        tester
            .widget<CommunityTimelineCard>(find.byType(CommunityTimelineCard))
            .item
            .reactions
            .single
            .isSelectedBy('alice'),
        isTrue,
      );
      service.setCurrentUsername('bob');
      await tester.pumpAndSettle();
      expect(find.byTooltip('删除这条动态'), findsNothing);
    },
  );

  test(
    'user blog list reads public schema and editor ownership from full details',
    () async {
      final service = serviceWith(
        (options) => options.path.endsWith('/blogs')
            ? {
                'total': 3,
                'data': [
                  {'id': 42, 'title': '公开日志', 'public': true},
                ],
              }
            : {
                'id': 42,
                'title': '日志',
                'content': '[color=red]正文[/color]',
                'public': false,
                'tags': ['标签'],
                'user': {'id': 1, 'username': 'alice', 'nickname': 'Alice'},
              },
      );
      final page = await service.loadUserBlogs('alice', offset: 2);
      expect(page.total, 3);
      expect(page.rawCount, 1);
      expect(page.data.single.user.username, 'alice');
      final blog = await service.loadBlog(42);
      expect(blog.isPublic, isFalse);
      expect(service.canEditBlog(blog), isTrue);
      service.setCurrentUsername('bob');
      expect(service.canEditBlog(blog), isFalse);
    },
  );
  test(
    'mono collection reads state and uses explicit idempotent PUT and DELETE',
    () async {
      final requests = <RequestOptions>[];
      final service = serviceWith((options) {
        requests.add(options);
        return {'collectedAt': 100, 'collects': 12};
      });
      final state = await service.loadMonoCollection(
        CommunityTimelineTargetKind.character,
        7,
      );
      expect(state.collected, isTrue);
      expect(state.count, 12);
      expect(requests.last.path, '/p1/characters/7');
      await service.setMonoCollection(
        CommunityTimelineTargetKind.character,
        7,
        collected: false,
      );
      expect(requests.last.path, '/p1/collections/characters/7');
      expect(requests.last.method, 'DELETE');
      await service.setMonoCollection(
        CommunityTimelineTargetKind.person,
        9,
        collected: true,
      );
      expect(requests.last.path, '/p1/collections/persons/9');
      expect(requests.last.method, 'PUT');
      await expectLater(
        service.setMonoCollection(
          CommunityTimelineTargetKind.blog,
          9,
          collected: true,
        ),
        throwsFormatException,
      );
      expect(requests, hasLength(3));
    },
  );

  test(
    'timeline restricts reactions and deletion and uses separate endpoints',
    () async {
      final requests = <RequestOptions>[];
      final service = serviceWith((options) {
        requests.add(options);
        return <String, dynamic>{};
      });
      await service.updateTimelineReaction(status(), 54);
      expect(requests.last.path, '/p1/timeline/8/like');
      expect(requests.last.data, {'value': 54});
      await service.updateTimelineReaction(status(), null);
      expect(requests.last.method, 'DELETE');
      await expectLater(
        service.updateTimelineReaction(status(isStatus: false), 54),
        throwsFormatException,
      );
      await expectLater(
        service.deleteTimeline(status(username: 'bob')),
        throwsFormatException,
      );
      await service.deleteTimeline(status());
      expect(requests.last.path, '/p1/timeline/8');
      expect(requests, hasLength(3));
    },
  );

  test(
    'blog PATCH preserves privacy and omits untouched associations; POST requires verification',
    () async {
      final requests = <RequestOptions>[];
      final service = serviceWith((options) {
        requests.add(options);
        return {'id': 100};
      });
      await service.saveBlog(
        original: privateBlog,
        title: '新标题',
        content: '[mask]内容[/mask]',
        tags: ['测试'],
        isPublic: false,
      );
      expect(requests.single.method, 'PATCH');
      expect(requests.single.path, '/p1/blogs/42');
      expect(requests.single.data, {
        'title': '新标题',
        'content': '[mask]内容[/mask]',
        'tags': ['测试'],
        'public': false,
      });
      await service.saveBlog(
        title: '新日志',
        content: '正文',
        tags: [],
        isPublic: true,
        turnstileToken: 'verified',
      );
      expect(requests.last.method, 'POST');
      expect(requests.last.path, '/p1/blogs');
      expect(requests.last.data['turnstileToken'], 'verified');
      await expectLater(
        service.saveBlog(title: '无验证', content: '正文', tags: [], isPublic: true),
        throwsFormatException,
      );
      service.setCurrentUsername('bob');
      await expectLater(
        service.saveBlog(
          original: privateBlog,
          title: '不允许',
          content: '正文',
          tags: [],
          isPublic: false,
        ),
        throwsFormatException,
      );
      expect(requests, hasLength(2));
    },
  );

  test(
    'credential refresh cannot resubmit a write under a different account',
    () async {
      var calls = 0;
      final service = serviceWith((options) {
        calls++;
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: options,
            statusCode: 401,
            data: {'code': 'NEED_LOGIN'},
          ),
        );
      });
      service.onUnauthorizedRefresh = () async {
        service.setCurrentUsername('bob');
        return true;
      };
      await expectLater(
        service.setMonoCollection(
          CommunityTimelineTargetKind.character,
          7,
          collected: true,
        ),
        throwsFormatException,
      );
      expect(calls, 1);
    },
  );

  test(
    'uncertain blog timeout is never automatically submitted twice',
    () async {
      var calls = 0;
      final service = serviceWith((options) {
        calls++;
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.receiveTimeout,
        );
      });
      await expectLater(
        service.saveBlog(
          title: '标题',
          content: '正文',
          tags: [],
          isPublic: true,
          turnstileToken: 'verified',
        ),
        throwsException,
      );
      expect(calls, 1);
    },
  );

  test(
    'timeline retains separate IDs for games, characters, persons and blogs',
    () {
      final rows = [
        {
          'id': 1,
          'cat': 3,
          'type': 8,
          'memo': {
            'subject': [
              {
                'subject': {'id': 7, 'type': 4, 'nameCN': '游戏'},
              },
              {
                'subject': {'id': 8, 'type': 4, 'nameCN': '另一个游戏'},
              },
            ],
          },
        },
        {
          'id': 2,
          'cat': 8,
          'type': 1,
          'memo': {
            'mono': {
              'characters': [
                {'id': 7, 'nameCN': '角色'},
              ],
              'persons': [
                {'id': 7, 'name': '人物'},
              ],
            },
          },
        },
        {
          'id': 3,
          'cat': 6,
          'type': 0,
          'memo': {
            'blog': {'id': 42, 'title': '日志'},
          },
        },
        {
          'id': 4,
          'cat': 5,
          'type': 1,
          'reactions': [
            {
              'value': 54,
              'users': [
                {'id': 1, 'username': 'alice'},
              ],
            },
          ],
        },
      ];
      final items = CommunityP1Parser().parseTimeline([
        for (final row in rows) {...row, 'uid': 1, 'createdAt': 1789567904},
      ], fallbackUsername: 'alice');
      expect(items[0].targets.map((target) => target.id), [7, 8]);
      expect(items[0].targets.first.subjectType, 4);
      expect(items[1].targets.map((target) => target.kind), [
        CommunityTimelineTargetKind.character,
        CommunityTimelineTargetKind.person,
      ]);
      expect(items[2].targets.single.id, 42);
      expect(items[3].reactions.single.isSelectedBy('alice'), isTrue);
      expect(items[1].copyWith(replyCount: 1).targets, hasLength(2));
    },
  );

  testWidgets('favorite failure does not flip state, rapid taps submit once', (
    tester,
  ) async {
    final service = _UiService()
      ..setCurrentUsername('alice')
      ..setAccessToken('test');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MonoCollectionButton(
            kind: CommunityTimelineTargetKind.character,
            id: 7,
            service: service,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    service.mutation = Completer<void>();
    await tester.tap(find.byType(IconButton));
    await tester.pump();
    await tester.tap(find.byType(IconButton));
    await tester.pump();
    expect(service.collectionWrites, 1);
    service.mutation!.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    service.mutation = null;
    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.favorite), findsOneWidget);
  });

  testWidgets(
    'timeline target cards send the selected object, including batch tails',
    (tester) async {
      CommunityTimelineTarget? opened;
      final targets = [
        for (var id = 1; id <= 6; id++)
          CommunityTimelineTarget(
            kind: CommunityTimelineTargetKind.person,
            id: id,
            title: '人物$id',
          ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CommunityTimelineCard(
                item: CommunityTimelineItem(
                  id: 1,
                  user: alice,
                  description: '收藏了人物',
                  createdAt: DateTime(2026),
                  targets: targets,
                ),
                onOpenTarget: (target) => opened = target,
              ),
            ),
          ),
        ),
      );
      expect(find.text('人物6'), findsNothing);
      await tester.ensureVisible(find.text('展开全部 6 项'));
      await tester.tap(find.text('展开全部 6 项'));
      await tester.pump();
      await tester.ensureVisible(find.text('人物6'));
      await tester.tap(find.text('人物6'));
      expect(opened?.id, 6);
    },
  );

  testWidgets(
    'timeline delete requires confirmation and removes only its own item',
    (tester) async {
      final service = _UiService()
        ..setCurrentUsername('alice')
        ..setAccessToken('test');
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(body: CommunityTimelinePage(service: service)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('更多动态操作'), findsOneWidget);
      await tester.tap(find.byTooltip('更多动态操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除这条动态'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(service.timelineDeletes, 0);
      await tester.tap(find.byTooltip('更多动态操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除这条动态'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(service.timelineDeletes, 1);
      expect(find.byTooltip('删除这条动态'), findsNothing);
    },
  );

  testWidgets(
    'blog list handles retry, pagination and private draft metadata',
    (tester) async {
      final service = _UiService()
        ..setCurrentUsername('alice')
        ..setAccessToken('test');
      await tester.pumpWidget(
        MaterialApp(home: CommunityBlogListScreen(service: service)),
      );
      await tester.pumpAndSettle();
      expect(find.text('原始标题'), findsOneWidget);
      expect(find.textContaining('仅好友可见'), findsOneWidget);
      await tester.tap(find.text('加载更多'));
      await tester.pumpAndSettle();
      expect(service.blogOffsets, [0, 1]);
      expect(find.text('已经到底了'), findsOneWidget);
      service.setCurrentUsername(null);
      service.setAccessToken(null);
      await tester.pumpAndSettle();
      expect(find.text('原始标题'), findsNothing);
    },
  );

  testWidgets('blog draft restores privacy tags and body together', (
    tester,
  ) async {
    final store = _DraftStore();
    CommunityBlogDraft? metadata;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              child: const Text('打开'),
              onPressed: () {
                metadata = CommunityBlogDraft();
                showCommunityComposer(
                  context,
                  heading: '日志',
                  requireTitle: true,
                  blogDraft: metadata,
                  draftKey: 'alice/blog-v1/new',
                  draftStore: store,
                  onSubmit: (_, _, _) async {},
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '标题'), '私密草稿');
    await tester.enterText(find.widgetWithText(TextField, '内容'), '[b]正文[/b]');
    await tester.enterText(find.widgetWithText(TextField, '标签'), '测试 日志');
    await tester.ensureVisible(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.tap(find.text('稍后再写'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(metadata!.isPublic, isFalse);
    expect(metadata!.tags, ['测试', '日志']);
    expect(find.text('仅好友可见'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, '内容'))
          .controller!
          .text,
      '[b]正文[/b]',
    );
    await tester.tap(find.text('稍后再写'));
    await tester.pumpAndSettle();
  });
}

class _UiService extends CommunityService {
  _UiService() : super.test();
  int collectionWrites = 0, timelineDeletes = 0;
  bool collected = false;
  bool failReaction = false;
  @override
  Future<void> updateTimelineReaction(
    CommunityTimelineItem item,
    int? value,
  ) async {
    if (failReaction) throw StateError('贴贴失败');
  }

  Completer<void>? mutation;
  final blogOffsets = <int>[];
  @override
  Future<CommunityMonoCollection> loadMonoCollection(
    CommunityTimelineTargetKind kind,
    int id, {
    bool refresh = false,
  }) async =>
      CommunityMonoCollection(collected: collected, count: collected ? 2 : 1);
  @override
  Future<void> setMonoCollection(
    CommunityTimelineTargetKind kind,
    int id, {
    required bool collected,
  }) async {
    collectionWrites++;
    if (mutation != null) await mutation!.future;
    this.collected = collected;
  }

  @override
  Future<List<CommunityTimelineItem>?> readCachedTimeline(
    CommunityTimelineMode mode,
  ) async => null;
  @override
  Future<List<CommunityTimelineItem>> loadTimeline(
    CommunityTimelineMode mode, {
    int limit = 20,
    int? until,
    bool refresh = false,
  }) async => until != null || timelineDeletes > 0 ? [] : [status()];
  @override
  Future<void> deleteTimeline(CommunityTimelineItem item) async {
    timelineDeletes++;
  }

  @override
  Future<CommunityPageResult<CommunityBlog>> loadUserBlogs(
    String username, {
    int offset = 0,
    int limit = 20,
    bool refresh = false,
  }) async {
    blogOffsets.add(offset);
    return CommunityPageResult(
      data: offset == 0 ? [privateBlog] : [],
      total: 2,
      rawCount: offset == 0 ? 1 : 0,
    );
  }
}

class _DraftStore extends CommunityDraftRepository {
  final data = <String, CommunityDraftData>{};
  @override
  Future<CommunityDraftData?> load(String key) async => data[key];
  @override
  Future<void> save(String key, CommunityDraftData draft) async {
    data[key] = draft;
  }
}

class _SlowMonoService extends _UiService {
  final pending = Completer<CommunityMonoCollection>();
  @override
  Future<CommunityMonoCollection> loadMonoCollection(
    CommunityTimelineTargetKind kind,
    int id, {
    bool refresh = false,
  }) async => currentUsername == 'alice'
      ? await pending.future
      : const CommunityMonoCollection(collected: false, count: 2);
}
