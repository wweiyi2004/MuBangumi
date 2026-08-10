import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/models/community_models.dart';
import 'package:mubangumi/state/notify_controller.dart';
import 'package:mubangumi/state/session_controller.dart';

void main() {
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
