import 'package:mubangumi/navigation/app_destination.dart';
import 'package:mubangumi/navigation/app_router.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/network/community_service.dart';
import 'package:mubangumi/core/network/pm_service.dart';
import 'package:mubangumi/core/storage/pm_draft_store.dart';
import 'package:mubangumi/core/theme/app_theme.dart';
import 'package:mubangumi/models/community_models.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/models/topic_reading_position.dart';
import 'package:mubangumi/core/storage/browsing_store.dart';
import 'package:mubangumi/models/pm_models.dart';
import 'package:mubangumi/screens/community_hub_page.dart';
import 'package:mubangumi/screens/community_blog_screen.dart';
import 'package:mubangumi/screens/community_timeline_page.dart';
import 'package:mubangumi/screens/discovery_hub_page.dart';
import 'package:mubangumi/screens/messages_page.dart';
import 'package:mubangumi/screens/pm_page.dart';
import 'package:mubangumi/state/session_controller.dart';
import 'package:mubangumi/state/website_session_controller.dart';
import 'package:mubangumi/widgets/app_navigation_layout.dart';
import 'package:mubangumi/widgets/profile_home_layout.dart';
import 'support/pm_fixtures.dart';
import 'support/memory_pm_draft_repository.dart';

const capture = bool.fromEnvironment('LAYOUT_SCREENSHOTS');

void main() {
  for (final variant in [
    'desktop-profile',
    'phone-profile',
    'phone-large',
    'phone-dark',
    'desktop-chat',
    'phone-chat',
    'phone-groups',
    'phone-discussion',
    'phone-thread',
    'desktop-discovery',
  ]) {
    testWidgets('layout review $variant', (tester) async {
      final phone = variant.startsWith('phone');
      tester.view.physicalSize = Size(phone ? 390 : 1280, phone ? 844 : 880);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final website = PmTestWebsiteStore();
      final container = ProviderContainer(
        overrides: [
          sessionProvider.overrideWith((ref) => PmTestSession()),
          websiteSessionStoreProvider.overrideWithValue(website),
          pmDraftRepositoryProvider.overrideWithValue(
            MemoryPmDraftRepository(),
          ),
          topicReadingRepositoryProvider.overrideWithValue(_Reading()),
        ],
      );
      addTearDown(container.dispose);
      await container.read(websiteSessionProvider.notifier).reload();
      final boundary = GlobalKey();
      final service = _Community();
      if (capture) {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        debugDisableShadows = false;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        await tester.runAsync(() async {
          final font = FontLoader('Microsoft YaHei UI');
          for (final file in ['msyh-ui.ttf', 'msyhbd-ui.ttf']) {
            font.addFont(
              Future.value(
                ByteData.sublistView(
                  await File('.dart_tool/pm-chat-fonts/$file').readAsBytes(),
                ),
              ),
            );
          }
          await font.load();
          await (FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(
                rootBundle.load(
                  'packages/cupertino_icons/assets/CupertinoIcons.ttf',
                ),
              ))
              .load();
          await (FontLoader('MaterialIcons')
                ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
              .load();
        });
      }
      Widget content;
      final index = variant.endsWith('discovery')
          ? 2
          : variant.endsWith('chat') ||
                variant.endsWith('groups') ||
                variant.endsWith('thread') ||
                variant.endsWith('discussion')
          ? 3
          : 4;
      if (index == 4) {
        var feedTab = 0;
        final opened = <int>{0};
        content = StatefulBuilder(
          builder: (context, setState) => ProfileHomeLayout(
            nickname: '小沐',
            username: 'mubangumi_demo',
            sign: '记录喜欢的作品，也和朋友聊聊。',
            avatarUrl: '',
            total: 128,
            doing: 8,
            friends: 26,
            selectedTab: feedTab,
            onSelectTab: (value) => setState(() {
              feedTab = value;
              opened.add(value);
            }),
            onSettings: () {},
            onCollections: () {},
            onDoing: () {},
            onFriends: () {},
            content: ProfileFeedStack(
              index: feedTab,
              children: [
                CommunityTimelinePage(
                  usePrimaryScrollController: feedTab == 0,
                  service: service,
                  initialMode: CommunityTimelineMode.me,
                  showModeSelector: false,
                ),
                opened.contains(1)
                    ? CommunityTimelinePage(
                        usePrimaryScrollController: feedTab == 1,
                        service: service,
                        initialMode: CommunityTimelineMode.friends,
                        showModeSelector: false,
                      )
                    : const SizedBox.shrink(),
                opened.contains(2)
                    ? CommunityBlogListScreen(
                        service: service,
                        embedded: true,
                        usePrimaryScrollController: feedTab == 2,
                      )
                    : const SizedBox.shrink(),
              ],
            ),
          ),
        );
      } else if (index == 3) {
        content = MessageHubLayout(
          selectedTab: variant.endsWith('chat') ? 0 : 1,
          unreadCount: 3,
          onSelectTab: (_) {},
          onFriends: () {},
          content: variant.endsWith('chat')
              ? PmPage(
                  service: _Pm(website),
                  embedded: true,
                  friendsLoader: (_) async => const [
                    BangumiUser(
                      id: 1,
                      username: 'alice',
                      nickname: '小夏',
                      avatarUrl: '',
                    ),
                    BangumiUser(
                      id: 2,
                      username: 'bob',
                      nickname: '阿月',
                      avatarUrl: '',
                    ),
                    BangumiUser(
                      id: 3,
                      username: 'aki',
                      nickname: '阿秋',
                      avatarUrl: '',
                    ),
                    BangumiUser(
                      id: 4,
                      username: 'momo',
                      nickname: '桃子',
                      avatarUrl: '',
                    ),
                  ],
                )
              : CommunityGroupBrowser(service: service, joinedOnly: true),
        );
      } else {
        content = DiscoveryHubPage(initialTab: 1, communityService: service);
      }
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: AppRouteScope(
            resolve: AppRouter.resolve,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: variant.endsWith('dark') ? AppTheme.dark : AppTheme.light,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(
                    variant == 'phone-large' ? 1.6 : 1,
                  ),
                ),
                child: RepaintBoundary(key: boundary, child: child!),
              ),
              home: AppNavigationLayout(
                index: index,
                onChanged: (_) {},
                unreadCount: 3,
                onOpenSchedule: () {},
                body: content,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (variant.endsWith('chat')) {
        await tester.tap(find.text('周末补番'));
        await tester.pumpAndSettle();
      }
      if (variant.endsWith('discussion') || variant.endsWith('thread')) {
        await tester.tap(find.text('一起补旧番'));
        await tester.pumpAndSettle();
        expect(find.text('发起讨论'), findsOneWidget);
      }
      if (variant.endsWith('thread')) {
        await tester.tap(find.text('最近有什么想推荐给朋友的作品？'));
        await tester.pumpAndSettle();
        expect(find.text('参与这场讨论…'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      if (index == 4) {
        expect(find.text('我的动态'), findsOneWidget);
        expect(find.text('好友动态'), findsOneWidget);
        expect(find.text('本地备份与导入'), findsNothing);
        expect(find.byTooltip('设置'), findsOneWidget);
        expect(find.byTooltip('发动态'), findsOneWidget);
      }
      if (capture) {
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory('docs/qa/layout-review').create(recursive: true);
          await File(
            'docs/qa/layout-review/$variant.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      if (index == 4) {
        final list = find.descendant(
          of: find.byType(CommunityTimelinePage),
          matching: find.byType(ListView),
        );
        final tabs = find.byType(PersonalFeedTabs);
        final originalTop = tester.getTopLeft(tabs).dy;
        final originalHeight = tester.getSize(list).height;
        Offset scrollStart() => Offset(
          tester.getTopLeft(list).dx + 4,
          tester.getTopLeft(list).dy + 5,
        );
        final gesture = await tester.startGesture(scrollStart());
        await gesture.moveBy(const Offset(0, -100));
        await tester.pump();
        final fade = tester.widget<Opacity>(
          find.byKey(const Key('profile-header-fade')),
        );
        expect(fade.opacity, greaterThan(0));
        expect(fade.opacity, lessThan(1));
        expect(tester.getTopLeft(tabs).dy, lessThan(originalTop));
        await gesture.up();
        await tester.pumpAndSettle();
        await tester.dragFrom(scrollStart(), const Offset(0, -600));
        await tester.pumpAndSettle();
        expect(tester.getSize(list).height, greaterThan(originalHeight + 150));
        expect(find.text('我的动态').hitTestable(), findsOneWidget);
        expect(find.text('好友动态').hitTestable(), findsOneWidget);
        expect(find.byTooltip('发动态').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (capture) {
          await tester.runAsync(() async {
            final image =
                await (boundary.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(
              'docs/qa/layout-review/$variant-collapsed.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        final nested = tester.state<NestedScrollViewState>(
          find.byType(NestedScrollView),
        );
        final savedOffset = nested.innerController.position.pixels;
        for (final label in ['好友动态', '日志', '我的动态']) {
          await tester.tap(find.text(label));
          await tester.pumpAndSettle();
          expect(nested.innerController.positions.length, 1);
          expect(tester.takeException(), isNull);
        }
        expect(nested.innerController.position.pixels, closeTo(savedOffset, 1));
        await tester.dragFrom(scrollStart(), const Offset(0, 1600));
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(tabs).dy, closeTo(originalTop, 1));
        expect(
          tester
              .widget<Opacity>(find.byKey(const Key('profile-header-fade')))
              .opacity,
          1,
        );
        expect(tester.takeException(), isNull);
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: tester.getCenter(list),
            scrollDelta: const Offset(0, 100),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(tabs).dy, lessThan(originalTop));
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
      debugDisableShadows = true;
    });
  }
}

class _Community extends CommunityService {
  _Community() : super.test() {
    setAccessToken('review-only');
    setCurrentUsername('demo');
  }
  @override
  Future<List<BangumiUser>> loadAllFriends(
    String username, {
    int pageSize = 30,
    bool refresh = false,
  }) async => [];
  @override
  Future<CommunityTopicDetail> loadTopic(
    CommunityTopic topic, {
    bool refresh = false,
  }) async => CommunityTopicDetail(
    title: topic.title,
    sourceTitle: '一起补旧番',
    posts: const [
      CommunityPost(
        id: '1',
        author: '小夏',
        userUrl: '/user/alice',
        isOriginal: true,
        meta: '#1 · 今天 14:20',
        body: '最近在重看以前喜欢的作品。\n有没有哪一部，让你想拉上朋友一起看？',
      ),
      CommunityPost(
        id: '2',
        author: '小沐',
        userUrl: '/user/demo',
        meta: '#2 · 今天 14:25',
        body: '想推荐一部轻松的日常番，周末看刚刚好。',
      ),
      CommunityPost(
        id: '3',
        author: '阿月',
        userUrl: '/user/bob',
        isNested: true,
        meta: '#2-1 · 今天 14:27',
        body: '赞同！看完再来这个讨论里聊感想。',
      ),
    ],
  );
  @override
  Future<CommunityPageResult<CommunityBlog>> loadUserBlogs(
    String username, {
    int limit = 20,
    int offset = 0,
    bool refresh = false,
  }) async => const CommunityPageResult(total: 0, data: []);
  @override
  Future<CommunityGroupDetail> loadGroupDetail(
    String slug, {
    bool refresh = false,
  }) async => CommunityGroupDetail(
    group: const CommunityGroup(
      id: 1,
      slug: 'demo1',
      name: '一起补旧番',
      url: 'https://bgm.tv/group/demo1',
      memberCount: 286,
      topicCount: 32,
    ),
    joinedAt: DateTime(2025),
    description: '一起分享喜欢的作品，慢慢看，也慢慢聊。',
    recentTopics: (await loadTopicPage(RakuenMode.groupJoined)).data,
  );
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
  }) async => until != null
      ? []
      : [
          CommunityTimelineItem(
            id: 30,
            user: const CommunityUser(id: 1, username: 'demo', nickname: '小沐'),
            description: '发表了动态',
            content: '周末留一点时间给喜欢的作品。\n这次想慢慢看，也慢慢记录。',
            createdAt: DateTime.now().subtract(const Duration(minutes: 18)),
            isStatus: true,
            replyCount: 2,
          ),
          CommunityTimelineItem(
            id: 29,
            user: const CommunityUser(id: 1, username: 'demo', nickname: '小沐'),
            description: '玩过 银河旅人',
            content: '很喜欢这个故事的结尾。',
            createdAt: DateTime.now().subtract(const Duration(hours: 4)),
            targets: const [
              CommunityTimelineTarget(
                kind: CommunityTimelineTargetKind.subject,
                id: 42,
                title: '银河旅人',
                subjectType: 4,
              ),
            ],
          ),
          CommunityTimelineItem(
            id: 28,
            user: const CommunityUser(id: 1, username: 'demo', nickname: '小沐'),
            description: '收藏了角色 青叶',
            createdAt: DateTime.now().subtract(const Duration(days: 1)),
          ),
        ];
  @override
  Future<CommunityPageResult<CommunityGroup>?> readCachedGroups(
    CommunityGroupMode mode,
    CommunityGroupSort sort,
  ) async => null;
  @override
  Future<CommunityPageResult<CommunityGroup>> loadGroupPage({
    CommunityGroupMode mode = CommunityGroupMode.all,
    CommunityGroupSort sort = CommunityGroupSort.members,
    int limit = 20,
    int offset = 0,
    bool refresh = false,
  }) async => CommunityPageResult(
    total: 3,
    data: [
      for (final (id, name, members) in [
        (1, '一起补旧番', 286),
        (2, '周末游戏茶话会', 128),
        (3, '音乐与日常', 86),
      ])
        CommunityGroup(
          id: id,
          slug: 'demo$id',
          name: name,
          url: 'https://bgm.tv/group/demo$id',
          memberCount: members,
          topicCount: 32,
        ),
    ],
  );
  @override
  Future<CommunityPageResult<CommunityTopic>?> readCachedTopics(
    RakuenMode mode,
  ) async => null;
  @override
  Future<CommunityPageResult<CommunityTopic>> loadTopicPage(
    RakuenMode mode, {
    int limit = 20,
    int offset = 0,
    bool refresh = false,
  }) async => CommunityPageResult(
    total: 3,
    data: [
      for (final (id, title, count) in [
        (1, '最近有什么想推荐给朋友的作品？', 24),
        (2, '聊聊让你反复回味的结尾', 18),
        (3, '周末一起看：本周讨论', 9),
      ])
        CommunityTopic(
          id: id,
          kind: CommunityTopicKind.group,
          title: title,
          url: '',
          webUrl: '',
          author: '小夏',
          sourceTitle: '一起补旧番',
          replyCount: count,
          updatedText: '今天',
        ),
    ],
  );
}

class _Pm extends PmService {
  _Pm(PmTestWebsiteStore store) : super(sessionStore: store);
  @override
  Future<List<PmConversation>> loadInbox({int page = 1}) async => page > 1
      ? []
      : const [
          PmConversation(
            id: 'alice',
            title: '周末补番',
            preview: '看完之后一起聊聊吧',
            peerName: '小夏',
            peerUserId: 'alice',
            timeText: '14:32',
            isUnread: true,
          ),
          PmConversation(
            id: 'bob',
            title: '下次一起玩',
            preview: '我把游戏名字发给你',
            peerName: '阿月',
            peerUserId: 'bob',
            timeText: '昨天',
          ),
        ];
  @override
  Future<List<PmConversation>> loadOutbox({int page = 1}) async => [];
  @override
  Future<PmConversationDetail> loadConversation(
    String id, {
    String? threadId,
  }) async => const PmConversationDetail(
    peerName: '小夏',
    peerUserId: 'alice',
    form: PmReplyForm(formhash: 'review', msgReceivers: 'alice'),
    messages: [
      PmMessage(
        name: '小夏',
        userId: 'alice',
        contentHtml: '这周的新番看了吗？画面和配乐都很喜欢。',
        timeText: '今天 14:30',
      ),
      PmMessage(
        name: '我',
        userId: 'user1',
        contentHtml: '看了，最后那段很精彩。',
        timeText: '今天 14:31',
        isSelf: true,
      ),
      PmMessage(
        name: '小夏',
        userId: 'alice',
        contentHtml: '等更新后再一起聊聊吧。',
        timeText: '今天 14:32',
      ),
    ],
  );
}

class _Reading implements TopicReadingRepository {
  @override
  Future<TopicReadingPosition?> readTopicPosition(
    String account,
    String topic,
  ) async => null;
  @override
  Future<void> saveTopicPosition(
    String account,
    String topic,
    TopicReadingPosition position,
  ) async {}
}
