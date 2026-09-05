import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/models/community_models.dart';
import 'package:mubangumi/state/notify_controller.dart';
import 'package:mubangumi/state/session_controller.dart';

void main() {
  testWidgets(
    'background pauses polling and resume refreshes only when stale',
    (tester) async {
      var now = DateTime(2026);
      var calls = 0;
      final controller = NotifyBadgeController(
        now: () => now,
        isAuthenticated: () => true,
        noticeLoader: () async {
          calls++;
          return const CommunityPageResult<BangumiNotice>(data: [], total: 2);
        },
      );
      controller.updateSession(SessionPhase.signedIn);
      await tester.pump();
      expect(calls, 1);
      controller.setForeground(false);
      await tester.pump(const Duration(minutes: 9));
      await controller.refresh();
      expect(calls, 1);
      now = now.add(const Duration(minutes: 9));
      controller.setForeground(true);
      await tester.pump();
      expect(calls, 2);
      controller.setForeground(false);
      now = now.add(const Duration(seconds: 20));
      controller.setForeground(true);
      await tester.pump();
      expect(calls, 2);
      controller.dispose();
    },
  );

  test('switching sessions does not reuse the old in-flight request', () async {
    final old = Completer<CommunityPageResult<BangumiNotice>>();
    var calls = 0;
    final controller = NotifyBadgeController(
      isAuthenticated: () => true,
      noticeLoader: () {
        calls++;
        return calls == 1
            ? old.future
            : Future.value(
                const CommunityPageResult(data: <BangumiNotice>[], total: 3),
              );
      },
    );
    addTearDown(controller.dispose);
    controller.updateSession(SessionPhase.signedIn);
    controller.updateSession(SessionPhase.signedOut);
    controller.updateSession(SessionPhase.signedIn);
    await Future<void>.delayed(Duration.zero);
    expect(calls, 2);
    expect(controller.state.unreadCount, 3);
    old.complete(const CommunityPageResult(data: <BangumiNotice>[], total: 8));
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.unreadCount, 3);
  });
  test('completed notice refresh does not block the next refresh', () async {
    var calls = 0;
    final controller = NotifyBadgeController(
      isAuthenticated: () => true,
      noticeLoader: () async {
        calls++;
        return CommunityPageResult(data: const <BangumiNotice>[], total: calls);
      },
    );
    addTearDown(controller.dispose);

    controller.updateSession(SessionPhase.signedIn);
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);
    expect(controller.state.unreadCount, 1);

    await controller.refresh();
    expect(calls, 2);
    expect(controller.state.unreadCount, 2);
  });

  test('notice response finishing after logout stays cleared', () async {
    final response = Completer<CommunityPageResult<BangumiNotice>>();
    var authenticated = true;
    final controller = NotifyBadgeController(
      isAuthenticated: () => authenticated,
      noticeLoader: () => response.future,
    );
    addTearDown(controller.dispose);

    controller.updateSession(SessionPhase.signedIn);
    await Future<void>.delayed(Duration.zero);
    authenticated = false;
    controller.updateSession(SessionPhase.signedOut);
    response.complete(
      const CommunityPageResult(data: <BangumiNotice>[], total: 7),
    );
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.unreadCount, 0);
    expect(controller.state.isLoading, isFalse);
  });
}
