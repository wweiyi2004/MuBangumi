import 'support/api_timeline_fixture.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/network/community_service.dart';
import 'package:mubangumi/models/community_models.dart';
import 'package:mubangumi/screens/community_timeline_page.dart';
import 'package:mubangumi/widgets/profile_home_layout.dart';
import 'package:mubangumi/widgets/retained_tab_stack.dart';

void main() {
  for (final cacheFirst in [true, false]) {
    testWidgets(
      'website cache survives fallback and keeps page cursor: cache first=$cacheFirst',
      (tester) async {
        final service = _CachedWebsiteService();
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: CommunityTimelinePage(
                  service: service,
                  showModeSelector: false,
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        final cached = CommunityTimelinePageResult(
          isWebsite: true,
          items: [for (var id = 1000; id > 980; id--) _item(id)],
          nextPage: 2,
        );
        final fallback = CommunityTimelinePageResult.api([
          _item(10),
        ], notice: '当前内容可能滞后');
        if (cacheFirst) {
          service.cached.complete(cached);
          await tester.pump();
          service.first.complete(fallback);
        } else {
          service.first.complete(fallback);
          await tester.pump();
          service.cached.complete(cached);
        }
        await tester.pumpAndSettle();
        expect(find.text('动态 1000'), findsOneWidget);
        expect(find.text('动态 10'), findsNothing);
        await tester.drag(find.byType(ListView).first, const Offset(0, -6000));
        await tester.pumpAndSettle();
        expect(service.pages, contains(2));
        expect(service.untils, everyElement(isNull));
        await tester.pumpWidget(const SizedBox.shrink());
        service.dispose();
      },
    );
  }
  for (final mode in CommunityTimelineMode.values) {
    testWidgets('${mode.name} refreshes retained tabs and bypasses cache', (
      tester,
    ) async {
      final service = _TimelineService();
      var selected = 0;
      late StateSetter select;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  select = setState;
                  return RetainedTabStack(
                    index: selected,
                    children: [
                      CommunityTimelinePage(
                        service: service,
                        initialMode: mode,
                        showModeSelector: false,
                      ),
                      const SizedBox.shrink(),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(service.requests.single.refresh, isTrue);
      expect(find.text('动态 1'), findsOneWidget);
      service.version = 2;
      select(() => selected = 1);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(minutes: 2));
      expect(service.requests, hasLength(1));
      select(() => selected = 0);
      await tester.pumpAndSettle();
      expect(find.text('动态 2'), findsOneWidget);
      expect(service.requests, hasLength(2));
      expect(service.requests.last, (mode: mode, until: null, refresh: true));
      service.version = 3;
      await tester.pump(const Duration(seconds: 60));
      await tester.pumpAndSettle();
      expect(find.text('动态 3'), findsOneWidget);
      expect(service.requests, hasLength(3));
      await tester.tap(find.byTooltip('刷新动态'));
      await tester.pumpAndSettle();
      expect(service.requests, hasLength(4));
      await tester.pumpWidget(const SizedBox.shrink());
      service.dispose();
    });
  }

  testWidgets('foreground refresh pauses in background and retains errors', (
    tester,
  ) async {
    final service = _TimelineService();
    await _show(tester, service);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(minutes: 2));
    expect(service.requests, hasLength(1));
    service.fail = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(service.requests, hasLength(2));
    expect(find.text('动态 1'), findsOneWidget);
    expect(find.text('刷新失败，已保留当前内容'), findsOneWidget);
    service.fail = false;
    service.version = 2;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('动态 2'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    service.dispose();
  });

  testWidgets('automatic refresh skips history and in-flight requests', (
    tester,
  ) async {
    final service = _TimelineService()..rows = 20;
    await _show(tester, service);
    final scroll = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    scroll.position.jumpTo(400);
    await tester.pump();
    await tester.pump(const Duration(seconds: 60));
    expect(service.requests, hasLength(1));
    scroll.position.jumpTo(0);
    await tester.pump();
    service.pending = Completer<List<CommunityTimelineItem>>();
    await tester.pump(const Duration(seconds: 60));
    expect(service.requests, hasLength(2));
    await tester.pump(const Duration(seconds: 60));
    expect(service.requests, hasLength(2));
    service.pending!.complete([_item(2)]);
    await tester.pumpAndSettle();
    expect(find.text('动态 2'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    service.dispose();
  });

  testWidgets('profile nested feed refreshes at top and preserves history', (
    tester,
  ) async {
    final service = _TimelineService()..rows = 20;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ProfileHomeLayout(
              nickname: 'Alice',
              username: 'alice',
              sign: '',
              avatarUrl: '',
              total: 0,
              doing: 0,
              friends: 0,
              selectedTab: 0,
              onSelectTab: (_) {},
              onSettings: () {},
              onCollections: () {},
              onDoing: () {},
              onFriends: () {},
              content: CommunityTimelinePage(
                service: service,
                usePrimaryScrollController: true,
                showModeSelector: false,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    service.version = 2;
    await tester.pump(const Duration(seconds: 60));
    await tester.pumpAndSettle();
    expect(find.text('动态 2'), findsOneWidget);
    final nested = tester.state<NestedScrollViewState>(
      find.byType(NestedScrollView),
    );
    nested.innerController.jumpTo(300);
    await tester.pumpAndSettle();
    final count = service.requests.length;
    await tester.pump(const Duration(seconds: 60));
    expect(service.requests, hasLength(count));
    await tester.pumpWidget(const SizedBox.shrink());
    service.dispose();
  });

  testWidgets('account switch rejects an older automatic refresh response', (
    tester,
  ) async {
    final service = _TimelineService()..setCurrentUsername('alice');
    await _show(tester, service);
    final old = Completer<List<CommunityTimelineItem>>();
    service.pending = old;
    await tester.pump(const Duration(seconds: 60));
    expect(service.requests, hasLength(2));
    service.pending = null;
    service.version = 3;
    service.setCurrentUsername('bob');
    await tester.pumpAndSettle();
    expect(find.text('动态 3'), findsOneWidget);
    old.complete([_item(2)]);
    await tester.pumpAndSettle();
    expect(find.text('动态 2'), findsNothing);
    expect(find.text('动态 3'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    service.dispose();
  });

  testWidgets('automatic refresh leaves a deep-linked timeline anchored', (
    tester,
  ) async {
    final service = _TimelineService();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: CommunityTimelinePage(
              service: service,
              initialTimelineId: 99,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // The website's first page lacks #99, so the P1 ID cursor locates it.
    expect(service.requests.map((r) => r.until), [null, 100]);
    await tester.pump(const Duration(minutes: 2));
    expect(service.requests, hasLength(2));
    await tester.pumpWidget(const SizedBox.shrink());
    service.dispose();
  });
  testWidgets(
    'website paging stays on website and stale fallback retains current content',
    (tester) async {
      final service = _WebsiteService();
      await _show(tester, service);
      expect(find.text('动态 30'), findsOneWidget);
      await tester.tap(find.text('加载更多'));
      await tester.pumpAndSettle();
      expect(service.pages, [null, 2]);
      expect(find.text('动态 20'), findsOneWidget);
      expect(find.text('已经到底了'), findsOneWidget);
      service.stale = true;
      await tester.tap(find.byTooltip('刷新动态'));
      await tester.pumpAndSettle();
      expect(find.text('动态 10'), findsNothing);
      expect(find.text('动态 30'), findsOneWidget);
      expect(find.text('当前内容可能滞后'), findsOneWidget);
      expect(find.text('验证网页登录'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      service.dispose();
    },
  );

  testWidgets('a next page continuing one friend keeps their avatar', (
    tester,
  ) async {
    final service = _WebsiteService()
      ..firstAvatar = 'https://lain.bgm.tv/a.jpg';
    await _show(tester, service);
    await tester.tap(find.text('加载更多'));
    await tester.pumpAndSettle();
    final avatars = tester
        .widgetList<CircleAvatar>(find.byType(CircleAvatar))
        .map((avatar) => avatar.foregroundImage)
        .toList();
    expect(avatars, hasLength(2));
    expect(avatars.every((image) => image != null), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    service.dispose();
  });

  testWidgets('a login-required fallback offers website verification', (
    tester,
  ) async {
    final service = _WebsiteService()..loginRequired = true;
    await _show(tester, service);
    expect(find.text('动态 10'), findsOneWidget);
    expect(find.text('好友最新动态需要验证网页登录'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '验证网页登录'), findsOneWidget);
    service.loginRequired = false;
    await tester.tap(find.byTooltip('刷新动态'));
    await tester.pumpAndSettle();
    expect(find.text('验证网页登录'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    service.dispose();
  });

  testWidgets('a recent notification target is found on the website page', (
    tester,
  ) async {
    final service = _WebsiteService()..firstPage = 99;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: CommunityTimelinePage(
              service: service,
              initialTimelineId: 99,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(service.untils, [null]);
    expect(find.text('动态 99'), findsOneWidget);
    expect(find.text('没有找到对应的动态'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    service.dispose();
  });
}

Future<void> _show(WidgetTester tester, CommunityService service) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: CommunityTimelinePage(
            service: service,
            showModeSelector: false,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _CachedWebsiteService extends _WebsiteService {
  final cached = Completer<CommunityTimelinePageResult?>();
  final first = Completer<CommunityTimelinePageResult>();
  @override
  Future<CommunityTimelinePageResult?> readCachedTimelinePage(
    CommunityTimelineMode mode,
  ) => cached.future;
  @override
  Future<CommunityTimelinePageResult> loadFreshTimelinePage(
    CommunityTimelineMode mode, {
    String? username,
    int? until,
    int? websitePage,
    bool refresh = false,
  }) => websitePage == null && until == null
      ? first.future
      : super.loadFreshTimelinePage(
          mode,
          username: username,
          until: until,
          websitePage: websitePage,
          refresh: refresh,
        );
}

class _WebsiteService extends _TimelineService {
  final pages = <int?>[];
  final untils = <int?>[];
  bool stale = false;
  bool loginRequired = false;
  int firstPage = 30;
  String firstAvatar = '';
  @override
  Future<CommunityTimelinePageResult> loadFreshTimelinePage(
    CommunityTimelineMode mode, {
    String? username,
    int? until,
    int? websitePage,
    bool refresh = false,
  }) async {
    untils.add(until);
    if (until != null) return CommunityTimelinePageResult.api([]);
    pages.add(websitePage);
    if (loginRequired) {
      return CommunityTimelinePageResult.api(
        [_item(10)],
        notice: '好友最新动态需要验证网页登录',
        websiteLoginRequired: true,
      );
    }
    if (stale) {
      return CommunityTimelinePageResult.api([_item(10)], notice: '当前内容可能滞后');
    }
    return CommunityTimelinePageResult(
      items: [
        websitePage == null
            ? _item(firstPage, avatarUrl: firstAvatar)
            : _item(20),
      ],
      nextPage: websitePage == null ? 2 : null,
    );
  }
}

CommunityTimelineItem _item(int id, {String avatarUrl = ''}) =>
    CommunityTimelineItem(
      id: id,
      user: CommunityUser(
        id: 1,
        username: 'alice',
        nickname: 'Alice',
        avatarUrl: avatarUrl,
      ),
      description: '',
      content: '动态 $id',
      isStatus: true,
      createdAt: DateTime(2026),
    );

class _TimelineService extends CommunityService with ApiTimelineFixture {
  _TimelineService() : super.test();
  int version = 1;
  int rows = 1;
  bool fail = false;
  Completer<List<CommunityTimelineItem>>? pending;
  final requests = <({CommunityTimelineMode mode, int? until, bool refresh})>[];

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
  }) async {
    requests.add((mode: mode, until: until, refresh: refresh));
    if (fail) throw StateError('offline');
    if (pending != null) return pending!.future;
    if (until != null) return [];
    return [for (var i = 0; i < rows; i++) _item(version + i)];
  }
}
