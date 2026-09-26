import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/network/community_service.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/models/community_models.dart';
import 'package:mubangumi/screens/common_friends_page.dart';
import 'package:mubangumi/screens/friends_page.dart';
import 'package:mubangumi/state/service_providers.dart';
import 'package:mubangumi/state/session_controller.dart';
import 'support/pm_fixtures.dart';

BangumiUser friend(String name) =>
    BangumiUser(id: 10, username: name, nickname: name, avatarUrl: '');

class Service extends CommunityService {
  final pending = Completer<CommunityPageResult<BangumiUser>>();
  bool delayOld = false;
  bool filteredPage = false;
  final offsets = <int>[];
  final removedBy = <String?>[];
  @override
  Future<CommunityPageResult<BangumiUser>> loadFriends(
    String username, {
    int limit = 30,
    int offset = 0,
    bool refresh = false,
  }) async {
    offsets.add(offset);
    if (filteredPage) {
      return offset == 0
          ? const CommunityPageResult(data: [], total: 3, rawCount: 2)
          : CommunityPageResult(
              data: [friend('last-friend')],
              total: 3,
              rawCount: 1,
            );
    }
    if (username == 'user1' && delayOld) return pending.future;
    return CommunityPageResult(data: [friend('$username-friend')], total: 1);
  }

  @override
  Future<List<BangumiUser>> loadAllFriends(
    String username, {
    bool refresh = false,
    int pageSize = 30,
  }) async {
    if (username == 'target') {
      return [friend('user1-friend'), friend('user2-friend')];
    }
    return (await loadFriends(username)).data;
  }

  @override
  Future<void> removeFriend(String username) async {
    removedBy.add(currentUsername);
  }
}

void main() {
  testWidgets('filtered friend rows still allow loading the next raw offset', (
    tester,
  ) async {
    final service = Service()..filteredPage = true;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          communityServiceProvider.overrideWithValue(service),
          sessionProvider.overrideWith((ref) => PmTestSession()),
        ],
        child: const MaterialApp(home: FriendsPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('加载更多好友'));
    await tester.pumpAndSettle();
    expect(service.offsets, [0, 2]);
    expect(find.text('last-friend'), findsOneWidget);
    expect(find.text('加载更多好友'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    service.dispose();
  });
  for (final common in [false, true]) {
    for (final delayed in [false, true]) {
      testWidgets(
        '${common ? 'common' : 'own'} friends resets on account change (pending: $delayed)',
        (tester) async {
          final service = Service()
            ..delayOld = delayed
            ..setCurrentUsername('user1');
          final session = PmTestSession();
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                communityServiceProvider.overrideWithValue(service),
                sessionProvider.overrideWith((ref) => session),
              ],
              child: MaterialApp(
                home: common
                    ? const CommonFriendsPage(
                        targetUsername: 'target',
                        targetDisplayName: 'target',
                      )
                    : const FriendsPage(),
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));
          session.switchUser(2);
          service.setCurrentUsername('user2');
          await tester.pumpAndSettle();
          if (delayed) {
            service.pending.complete(
              CommunityPageResult(data: [friend('user1-friend')], total: 1),
            );
            await tester.pumpAndSettle();
          }
          expect(find.text('user1-friend'), findsNothing);
          expect(find.text('user2-friend'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          service.dispose();
        },
      );
    }
  }
  testWidgets(
    'old remove-friend confirmation cannot operate under the new account',
    (tester) async {
      final service = Service()..setCurrentUsername('user1');
      final session = PmTestSession();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            communityServiceProvider.overrideWithValue(service),
            sessionProvider.overrideWith((ref) => session),
          ],
          child: const MaterialApp(home: FriendsPage()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.longPress(find.text('user1-friend'));
      await tester.pumpAndSettle();
      session.switchUser(2);
      service.setCurrentUsername('user2');
      await tester.pumpAndSettle();
      await tester.tap(find.text('解除'));
      await tester.pumpAndSettle();
      expect(service.removedBy, isEmpty);
      expect(find.text('user2-friend'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      service.dispose();
    },
  );
}
