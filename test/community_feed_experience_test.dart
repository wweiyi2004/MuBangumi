import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/network/community_service.dart';
import 'package:mubangumi/models/community_models.dart';
import 'package:mubangumi/screens/community_hub_page.dart';
import 'package:mubangumi/screens/community_group_screen.dart';
import 'package:mubangumi/screens/community_timeline_page.dart';
import 'package:mubangumi/screens/community_topic_screen.dart';
import 'package:mubangumi/widgets/community_widgets.dart';

void main() {
  testWidgets('reply refreshes its thread without reloading the timeline', (
    tester,
  ) async {
    final service = _Service()
      ..authenticated = true
      ..timelineItems = [
        for (var i = 1; i <= 3; i++)
          CommunityTimelineItem(
            id: i,
            user: const CommunityUser(id: 1, username: 'u', nickname: '用户'),
            description: '',
            content: '动态$i',
            isStatus: true,
            createdAt: DateTime(2026),
          ),
      ];
    await _show(
      tester,
      CommunityTimelinePage(
        service: service,
        tokenProvider: (_) async => 'test',
      ),
    );
    final card = tester.widget<CommunityTimelineCard>(
      find.byType(CommunityTimelineCard).first,
    );
    card.onReply!();
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '测试回复');
    await tester.pump();
    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();
    expect(service.timelineCalls, 1);
    expect(service.repliedTo, card.item.id);
    expect(
      tester
          .widget<CommunityTimelineCard>(
            find.byType(CommunityTimelineCard).first,
          )
          .item
          .replyCount,
      1,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
  for (final width in [320.0, 1200.0]) {
    testWidgets(
      'community controls and group cards fit width $width with large text',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 850));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final service = _Service()..groups = [_group];
        await _show(tester, CommunityPage(service: service), textScale: 1.8);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('小组'));
        await tester.pumpAndSettle();
        expect(find.text('测试小组'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('时光机'));
        await tester.tap(find.text('时光机'));
        await tester.pumpAndSettle();
        expect(find.text('暂时没有动态'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  testWidgets(
    'topic network starts before disk and late cache cannot replace it',
    (tester) async {
      final service = _Service()
        ..topicCache = Completer<CommunityPageResult<CommunityTopic>?>();
      await _show(tester, CommunityPage(service: service));
      expect(service.topicOffsets, [0]);
      expect(find.text('话题1'), findsOneWidget);
      service.topicCache!.complete(
        CommunityPageResult(data: [_topic(9)], total: 1),
      );
      await tester.pump();
      expect(find.text('话题9'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'switching topic mode ignores a slow previous cache and preserves loading state',
    (tester) async {
      final service = _Service()
        ..topicCache = Completer<CommunityPageResult<CommunityTopic>?>();
      await _show(tester, CommunityPage(service: service));
      await tester.tap(find.text('最新'));
      await tester.pump();
      expect(service.topicModes, [
        RakuenMode.subjectTrending,
        RakuenMode.subjectLatest,
      ]);
      service.topicCache!.complete(
        CommunityPageResult(data: [_topic(9)], total: 1),
      );
      await tester.pump();
      expect(find.text('话题9'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'overlapping pages advance raw offsets and empty page stops pagination',
    (tester) async {
      final service = _Service()
        ..topicPages = {
          0: [_topic(1), _topic(2)],
          2: [_topic(2), _topic(3)],
          4: [],
        }
        ..total = 8;
      await _show(tester, CommunityPage(service: service));
      await tester.tap(find.text('加载更多'));
      await tester.pump();
      expect(find.text('话题2'), findsOneWidget);
      await tester.tap(find.text('加载更多'));
      await tester.pump();
      expect(service.topicOffsets, [0, 2, 4]);
      expect(find.text('已经到底了'), findsOneWidget);
      expect(find.text('加载更多'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'pagination failure preserves content and offers an explicit retry',
    (tester) async {
      final service = _Service()
        ..total = 3
        ..failMore = true;
      await _show(tester, CommunityPage(service: service));
      await tester.tap(find.text('加载更多'));
      await tester.pump();
      expect(find.text('话题1'), findsOneWidget);
      expect(find.text('加载失败，点击重试'), findsOneWidget);
      service.failMore = false;
      await tester.tap(find.text('加载失败，点击重试'));
      await tester.pump();
      expect(service.topicOffsets, [0, 1, 1]);
      expect(find.text('加载失败，点击重试'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('refresh failure stays visible beside retained topics', (
    tester,
  ) async {
    final service = _Service();
    await _show(tester, CommunityPage(service: service));
    service.failFirst = true;
    await tester.tap(find.byTooltip('刷新话题'));
    await tester.pump();
    expect(find.text('话题1'), findsOneWidget);
    expect(find.text('刷新失败，已保留当前内容'), findsOneWidget);
    service.failFirst = false;
    await tester.tap(find.text('重试'));
    await tester.pump();
    expect(find.text('刷新失败，已保留当前内容'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('group detail is usable before optional cache finishes', (
    tester,
  ) async {
    final service = _Service()..groupCache = Completer<CommunityGroupDetail?>();
    await _show(tester, CommunityGroupScreen(group: _group, service: service));
    expect(find.text('新的小组介绍'), findsOneWidget);
    service.groupCache!.complete(
      const CommunityGroupDetail(group: _group, description: '旧介绍'),
    );
    await tester.pump();
    expect(find.text('旧介绍'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('timeline ignores late cache even when network result is empty', (
    tester,
  ) async {
    final service = _Service()
      ..timelineCache = Completer<List<CommunityTimelineItem>?>();
    await _show(tester, CommunityTimelinePage(service: service));
    expect(service.timelineCalls, 1);
    service.timelineCache!.complete([
      CommunityTimelineItem(
        id: 1,
        user: const CommunityUser(id: 1, username: 'u', nickname: '用户'),
        description: '旧动态',
        createdAt: DateTime(2026),
      ),
    ]);
    await tester.pump();
    expect(find.text('旧动态'), findsNothing);
    expect(find.text('暂时没有动态'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'topic refresh ignores an older response and keeps latest detail',
    (tester) async {
      final service = _Service();
      await _show(
        tester,
        CommunityTopicScreen(topic: _topic(1), service: service),
      );
      final slow = Completer<CommunityTopicDetail>();
      service.topicResponse = slow;
      final refresh = tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh;
      final oldRequest = refresh();
      service.topicResponse = null;
      await refresh();
      slow.complete(const CommunityTopicDetail(title: '旧标题', posts: []));
      await oldRequest;
      await tester.pump();
      expect(find.text('新标题'), findsOneWidget);
      expect(find.text('旧标题'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

Future<void> _show(
  WidgetTester tester,
  Widget child, {
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.pump();
}

CommunityTopic _topic(int id) => CommunityTopic(
  id: id,
  kind: CommunityTopicKind.subject,
  title: '话题$id',
  url: '',
  webUrl: '',
);
const _group = CommunityGroup(
  slug: 'test',
  name: '测试小组',
  url: 'https://bgm.tv/group/test',
);

class _Service extends CommunityService {
  _Service() : super.test();
  Completer<CommunityPageResult<CommunityTopic>?>? topicCache;
  Completer<CommunityGroupDetail?>? groupCache;
  Completer<List<CommunityTimelineItem>?>? timelineCache;
  Completer<CommunityTopicDetail>? topicResponse;
  final topicOffsets = <int>[];
  final topicModes = <RakuenMode>[];
  Map<int, List<CommunityTopic>> topicPages = {
    0: [_topic(1)],
  };
  List<CommunityGroup> groups = [];
  List<CommunityTimelineItem> timelineItems = [];
  bool authenticated = false;
  int? repliedTo;
  @override
  bool get isAuthenticated => authenticated;
  @override
  Future<void> replyToTimeline({
    required int timelineId,
    required String content,
    required String turnstileToken,
    int? replyTo,
  }) async {
    repliedTo = timelineId;
  }

  @override
  Future<List<CommunityTimelineReply>> loadTimelineReplies(
    int timelineId, {
    bool refresh = false,
  }) async => [];
  int total = 1, timelineCalls = 0;
  bool failMore = false, failFirst = false;
  @override
  Future<CommunityPageResult<CommunityTopic>?> readCachedTopics(
    RakuenMode mode,
  ) async => topicCache == null ? null : await topicCache!.future;
  @override
  Future<CommunityPageResult<CommunityTopic>> loadTopicPage(
    RakuenMode mode, {
    int limit = 20,
    int offset = 0,
    bool refresh = false,
  }) async {
    topicOffsets.add(offset);
    topicModes.add(mode);
    if (offset == 0 ? failFirst : failMore) throw StateError('offline');
    return CommunityPageResult(data: topicPages[offset] ?? [], total: total);
  }

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
    data: limit == 10 ? [] : groups,
    total: groups.length,
  );
  @override
  Future<CommunityGroupDetail?> readCachedGroupDetail(String slug) async =>
      groupCache == null ? null : await groupCache!.future;
  @override
  Future<CommunityGroupDetail> loadGroupDetail(
    String slug, {
    bool refresh = false,
  }) async => const CommunityGroupDetail(group: _group, description: '新的小组介绍');
  @override
  Future<List<CommunityTimelineItem>?> readCachedTimeline(
    CommunityTimelineMode mode,
  ) async => timelineCache == null ? null : await timelineCache!.future;
  @override
  Future<List<CommunityTimelineItem>> loadTimeline(
    CommunityTimelineMode mode, {
    int limit = 20,
    int? until,
    bool refresh = false,
  }) async {
    timelineCalls++;
    return timelineItems;
  }

  @override
  Future<CommunityTopicDetail> loadTopic(
    CommunityTopic topic, {
    bool refresh = false,
  }) async => topicResponse == null
      ? const CommunityTopicDetail(title: '新标题', posts: [])
      : await topicResponse!.future;
}
