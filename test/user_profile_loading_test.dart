import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/network/bangumi_api.dart';
import 'package:mubangumi/core/network/community_service.dart';
import 'package:mubangumi/core/storage/user_preference_store.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/models/community_models.dart';
import 'package:mubangumi/features/community/presentation/community_timeline_card.dart';
import 'package:mubangumi/screens/user_profile_page.dart';
import 'package:mubangumi/state/service_providers.dart';
import 'package:mubangumi/state/session_controller.dart';
import 'package:mubangumi/state/user_preferences_controller.dart';
import 'package:mubangumi/widgets/user_biography.dart';

import 'support/api_timeline_fixture.dart';
import 'support/pm_fixtures.dart';

class _ProfileApi extends BangumiApi {
  final counts = Completer<Map<CollectionType, int>>();
  final items = Completer<List<UserCollection>>();

  @override
  Future<BangumiUser> getUser(String username) async => const BangumiUser(
    id: 2,
    username: 'target',
    nickname: 'Target',
    avatarUrl: '',
  );

  @override
  Future<Map<CollectionType, int>> getUserCollectionCounts(
    String username, {
    SubjectType subjectType = SubjectType.anime,
  }) => counts.future;

  @override
  Future<List<UserCollection>> getUserCollections(
    String username, {
    SubjectType? subjectType,
    CollectionType? collectionType,
    int? maxItems,
    Future<bool> Function(List<UserCollection>)? onPage,
  }) => items.future;
}

class _Community extends CommunityService with ApiTimelineFixture {
  @override
  Future<List<CommunityTimelineItem>> loadUserTimeline(
    String username, {
    int limit = 12,
    int? until,
    bool refresh = false,
    String? fallbackAvatarUrl,
    String? fallbackNickname,
  }) async => [];
}

/// Website profile rows carry the owner's username only.
class _WebsiteCommunity extends CommunityService {
  final usernames = <String?>[];
  @override
  Future<CommunityTimelinePageResult> loadFreshTimelinePage(
    CommunityTimelineMode mode, {
    String? username,
    int? until,
    int? websitePage,
    bool refresh = false,
  }) async {
    usernames.add(username);
    return CommunityTimelinePageResult(
      items: [
        CommunityTimelineItem(
          id: 900,
          user: const CommunityUser(
            id: 0,
            username: 'target',
            nickname: 'target',
          ),
          description: '',
          content: '网站最新动态',
          isStatus: true,
          createdAt: DateTime(2026, 10, 21),
        ),
      ],
    );
  }

  @override
  Future<List<CommunityTimelineItem>> loadUserTimeline(
    String username, {
    int limit = 12,
    int? until,
    bool refresh = false,
    String? fallbackAvatarUrl,
    String? fallbackNickname,
  }) => throw StateError('profile preview must not read the lagging P1 inbox');
}

class _Preferences implements UserPreferenceRepository {
  @override
  Future<List<LocalUserPreference>> loadAll() async => [];
  @override
  Future<void> save(LocalUserPreference value) async {}
}

void main() {
  for (final firstFailure in ['items', 'counts']) {
    testWidgets('profile handles $firstFailure failure before the other read', (
      tester,
    ) async {
      final api = _ProfileApi();
      final community = _Community();
      addTearDown(community.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            bangumiApiProvider.overrideWithValue(api),
            communityServiceProvider.overrideWithValue(community),
            sessionProvider.overrideWith((ref) => PmTestSession()),
            userPreferencesProvider.overrideWith(
              (ref) => UserPreferencesController(_Preferences()),
            ),
            userBiographyProvider('target').overrideWith((ref) async => ''),
          ],
          child: const MaterialApp(home: UserProfilePage(username: 'target')),
        ),
      );
      await tester.pump();
      if (firstFailure == 'items') {
        api.items.completeError(const BangumiApiException('收藏列表读取失败'));
        await tester.pump();
        api.counts.complete({});
      } else {
        api.counts.completeError(const BangumiApiException('收藏统计读取失败'));
        await tester.pump();
        api.items.completeError(const BangumiApiException('收藏列表读取失败'));
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('收藏加载失败'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('收藏加载失败'), findsOneWidget);
      expect(
        find.text(firstFailure == 'items' ? '收藏列表读取失败' : '收藏统计读取失败'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets('profile preview reads the website and keeps profile identity', (
    tester,
  ) async {
    final api = _ProfileApi();
    final community = _WebsiteCommunity();
    addTearDown(community.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bangumiApiProvider.overrideWithValue(api),
          communityServiceProvider.overrideWithValue(community),
          sessionProvider.overrideWith((ref) => PmTestSession()),
          userPreferencesProvider.overrideWith(
            (ref) => UserPreferencesController(_Preferences()),
          ),
          userBiographyProvider('target').overrideWith((ref) async => ''),
        ],
        child: const MaterialApp(home: UserProfilePage(username: 'target')),
      ),
    );
    api.counts.complete({});
    api.items.complete([]);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(community.usernames, ['target']);
    await tester.scrollUntilVisible(
      find.text('网站最新动态'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    final card = find.ancestor(
      of: find.text('网站最新动态'),
      matching: find.byType(CommunityTimelineCard),
    );
    expect(
      find.descendant(of: card, matching: find.text('Target')),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
