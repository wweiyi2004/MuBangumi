import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/network/community_service.dart';
import 'package:mubangumi/models/community_models.dart';
import 'package:mubangumi/screens/notify_page.dart';
import 'package:mubangumi/state/notify_controller.dart';
import 'package:mubangumi/state/service_providers.dart';

void main() {
  testWidgets('old clear response cannot leave the new account toolbar busy', (
    tester,
  ) async {
    final service = _Notices()..pendingClear = Completer<void>();
    await _show(tester, service);
    final button = find.ancestor(
      of: find.byTooltip('全部已读'),
      matching: find.byType(IconButton),
    );
    await tester.tap(find.byTooltip('全部已读'));
    await tester.pump();
    service.setCurrentUsername('charlie');
    service.pendingClear!.complete();
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(tester.widget<IconButton>(button).onPressed, isNotNull);
    expect(find.text('已全部标为已读'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'a fast request settles while another lookup is stuck; timeout releases action',
    (tester) async {
      final service = _Notices()
        ..pendingStatus = Completer<bool>()
        ..includeFast = true;
      await _show(tester, service);
      expect(find.text('已接受'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pump(const Duration(seconds: 7));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '接受好友'))
            .onPressed,
        isNotNull,
      );
      service.pendingStatus!.complete(false);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'a persisted status avoids repeating the lookup after reopening',
    (tester) async {
      final service = _Notices()..cached = true;
      await _show(tester, service);
      expect(service.lookups, 0);
      expect(find.text('已接受'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await _show(tester, service);
      expect(service.lookups, 0);
    },
  );
  testWidgets('old accepted status cannot update another account', (
    tester,
  ) async {
    final service = _Notices()..pendingStatus = Completer<bool>();
    await _show(tester, service);
    service.setCurrentUsername('charlie');
    service.pendingStatus!.complete(true);
    await tester.pump();
    await tester.pump();
    expect(find.text('已接受'), findsNothing);
    expect(find.textContaining('dana'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'old accept response cannot mark notices accepted for a new account',
    (tester) async {
      final service = _Notices()..pendingAccept = Completer<void>();
      await _show(tester, service);
      await tester.tap(find.text('接受好友'));
      await tester.pump();
      service.setCurrentUsername('charlie');
      service.pendingAccept!.complete();
      await tester.pump();
      await tester.pump();
      expect(find.text('已接受'), findsNothing);
      expect(find.textContaining('已接受 bob 的好友申请'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

Future<void> _show(WidgetTester tester, _Notices service) async {
  service.setCurrentUsername('alice');
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        communityServiceProvider.overrideWithValue(service),
        notifyBadgeProvider.overrideWith((ref) => NotifyBadgeController()),
      ],
      child: const MaterialApp(home: NotifyPage()),
    ),
  );
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

class _Notices extends CommunityService {
  Completer<bool>? pendingStatus;
  Completer<void>? pendingAccept;
  Completer<void>? pendingClear;
  bool includeFast = false;
  bool? cached;
  int lookups = 0;
  @override
  Future<CommunityPageResult<BangumiNotice>> loadNotices({
    int limit = 40,
    bool unreadOnly = false,
    bool refresh = false,
  }) async => CommunityPageResult(
    data: [
      _notice(1, currentUsername == 'alice' ? 'bob' : 'dana'),
      if (includeFast) _notice(2, 'eve'),
    ],
    total: includeFast ? 2 : 1,
  );
  BangumiNotice _notice(int id, String sender) => BangumiNotice(
    id: id,
    title: '',
    type: 14,
    mainId: 0,
    relatedId: 0,
    unread: true,
    createdAt: DateTime(2026, 10, 1),
    sender: CommunityUser(id: id, username: sender, nickname: sender),
  );
  @override
  Future<bool?> readCachedFriendStatus(String username) async => cached;
  @override
  Future<void> cacheFriendStatus(String username, bool accepted) async {}
  @override
  Future<bool> isFriend(String username) {
    lookups++;
    return username == 'bob' && pendingStatus != null
        ? pendingStatus!.future
        : Future.value(username == 'eve');
  }

  @override
  Future<void> clearNotices({List<int> ids = const []}) async {
    if (pendingClear != null) await pendingClear!.future;
  }

  @override
  Future<void> acceptFriendRequest(BangumiNotice notice) async {
    if (pendingAccept != null) await pendingAccept!.future;
  }
}
