import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mubangumi/core/auth/website_identity.dart';
import 'package:mubangumi/core/network/community_service.dart';
import 'package:mubangumi/models/community_models.dart';
import 'package:mubangumi/navigation/app_destination.dart';
import 'package:mubangumi/navigation/app_router.dart';
import 'package:mubangumi/screens/community_hub_page.dart';
import 'package:mubangumi/screens/community_group_screen.dart';
import 'package:mubangumi/screens/community_topic_screen.dart';

CommunityGroup group(String name) => CommunityGroup(
  id: 7,
  slug: 'demo',
  name: name,
  url: 'https://bgm.tv/group/demo',
);

class Service extends CommunityService {
  Service() : super.test();
  Completer<CommunityPageResult<CommunityGroup>>? alicePending;
  bool invalidFirstPage = false;
  final offsets = <int>[];
  final owners = <String?>[];
  CommunityGroupDetail? detail;
  @override
  Future<CommunityPageResult<CommunityGroup>?> readCachedGroups(
    CommunityGroupMode mode,
    CommunityGroupSort sort,
  ) async => null;
  @override
  Future<CommunityGroupDetail?> readCachedGroupDetail(String slug) async =>
      null;
  @override
  Future<CommunityGroupDetail> loadGroupDetail(
    String slug, {
    bool refresh = false,
  }) async => detail ?? CommunityGroupDetail(group: group('小组详情'));
  @override
  Future<CommunityPageResult<CommunityGroup>> loadGroupPage({
    CommunityGroupMode mode = CommunityGroupMode.all,
    CommunityGroupSort sort = CommunityGroupSort.members,
    int limit = 20,
    int offset = 0,
    bool refresh = false,
  }) async {
    offsets.add(offset);
    owners.add(currentUsername);
    if (currentUsername == 'alice' && alicePending != null) {
      return alicePending!.future;
    }
    if (invalidFirstPage && offset == 0) {
      return const CommunityPageResult(data: [], total: 3, rawCount: 2);
    }
    return CommunityPageResult(
      data: [group('$currentUsername的小组')],
      total: invalidFirstPage ? 3 : 1,
      rawCount: 1,
    );
  }
}

class ExpiredTopicService extends CommunityService {
  ExpiredTopicService() : super.test();
  @override
  Future<CommunityTopicDetail> loadTopic(
    CommunityTopic topic, {
    bool refresh = false,
  }) async => throw const WebsiteAccessException(
    WebsiteAccessStatus.expired,
    '网页登录已过期，请补充验证',
  );
}

Future<void> show(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    AppRouteScope(
      resolve: AppRouter.resolve,
      child: MaterialApp(home: Scaffold(body: child)),
    ),
  );
  await tester.pump();
}

void main() {
  for (final role in [
    CommunityGroupRole.creator,
    CommunityGroupRole.moderator,
  ]) {
    testWidgets('${role.name} sees a management identity and posting entry', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final service = Service()
        ..setAccessToken('fixture')
        ..detail = CommunityGroupDetail(
          group: group('管理的小组'),
          accessible: false,
          membershipJoined: true,
          membershipRole: role,
        );
      addTearDown(service.dispose);
      await show(
        tester,
        CommunityGroupScreen(group: group('管理的小组'), service: service),
      );
      await tester.pumpAndSettle();
      expect(find.text('${role.label} · 管理'), findsOneWidget);
      expect(find.text('发起讨论'), findsOneWidget);
      expect(find.text('加入'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets('an expired group read provides a website recovery action', (
    tester,
  ) async {
    final service = ExpiredTopicService();
    addTearDown(service.dispose);
    await show(
      tester,
      ProviderScope(
        child: CommunityTopicScreen(
          service: service,
          topic: const CommunityTopic(
            id: 42,
            kind: CommunityTopicKind.group,
            title: '话题',
            url: '',
            webUrl: 'https://bgm.tv/group/topic/42',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('网页登录已过期，请补充验证'), findsOneWidget);
    expect(find.text('补充账号验证'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('my groups switches accounts and discards an older response', (
    tester,
  ) async {
    final old = Completer<CommunityPageResult<CommunityGroup>>();
    final service = Service()
      ..setAccessToken('fixture')
      ..setCurrentUsername('alice')
      ..alicePending = old;
    addTearDown(service.dispose);
    await show(
      tester,
      CommunityGroupBrowser(service: service, joinedOnly: true),
    );
    service.setCurrentUsername('bob');
    await tester.pump();
    await tester.pump();
    expect(find.text('bob的小组'), findsOneWidget);
    old.complete(CommunityPageResult(data: [group('alice的小组')], total: 1));
    await tester.pumpAndSettle();
    expect(find.text('alice的小组'), findsNothing);
    expect(service.owners, ['alice', 'bob']);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('filtered-out rows do not hide the next group page', (
    tester,
  ) async {
    final service = Service()
      ..setCurrentUsername('alice')
      ..invalidFirstPage = true;
    addTearDown(service.dispose);
    await show(
      tester,
      CommunityGroupBrowser(service: service, joinedOnly: true),
    );
    await tester.pumpAndSettle();
    expect(find.text('暂时没有小组'), findsNothing);
    await tester.tap(find.text('加载更多'));
    await tester.pumpAndSettle();
    expect(find.text('alice的小组'), findsOneWidget);
    expect(service.offsets, [0, 2]);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('returning from a group refreshes joined groups', (tester) async {
    final service = Service()..setCurrentUsername('alice');
    addTearDown(service.dispose);
    await show(
      tester,
      CommunityGroupBrowser(service: service, joinedOnly: true),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('alice的小组'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(service.offsets, [0, 0]);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a failed topic list is not presented as an empty group', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final service = Service()
      ..setAccessToken('fixture')
      ..detail = CommunityGroupDetail(
        group: group('小组'),
        membershipJoined: true,
        accessible: false,
        unavailableSections: {
          CommunityGroupSection.topics,
          CommunityGroupSection.members,
        },
      );
    addTearDown(service.dispose);
    await show(
      tester,
      CommunityGroupScreen(group: group('小组'), service: service),
    );
    await tester.pumpAndSettle();
    expect(find.text('已加入'), findsOneWidget);
    expect(find.text('发起讨论'), findsOneWidget);
    expect(find.text('还没有话题'), findsNothing);
    expect(find.text('话题暂时未能加载，不代表小组没有帖子'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
