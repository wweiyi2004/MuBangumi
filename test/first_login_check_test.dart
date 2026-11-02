import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/auth/bangumi_oauth.dart';
import 'package:mubangumi/core/network/bangumi_api.dart';
import 'package:mubangumi/core/network/bangumi_endpoints.dart';
import 'package:mubangumi/core/storage/token_store.dart';
import 'package:mubangumi/features/auth/application/first_login_check.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/screens/first_login_check_screen.dart';
import 'package:mubangumi/state/session_controller.dart';

typedef _Probes = Map<LoginCheckId, LoginCheckProbe>;

_Probes _passing() => {
  for (final id in LoginCheckId.values) id: () async => null,
};

void main() {
  test('entry requires both the API account and website login', () async {
    final checks = FirstLoginChecks({
      ..._passing(),
      LoginCheckId.website: () async => '尚未登录网页版',
    });
    addTearDown(checks.dispose);
    await checks.runAll();
    expect(checks[LoginCheckId.api].status, LoginCheckStatus.passed);
    expect(checks[LoginCheckId.website].status, LoginCheckStatus.failed);
    expect(checks[LoginCheckId.website].detail, '尚未登录网页版');
    expect(checks.canEnter, isFalse);

    final api = FirstLoginChecks({
      ..._passing(),
      LoginCheckId.api: () async => throw Exception('令牌已失效'),
    });
    addTearDown(api.dispose);
    await api.runAll();
    expect(api[LoginCheckId.api].detail, '令牌已失效');
    expect(api.canEnter, isFalse);
  });

  test('website features wait for website login, then run', () async {
    var websiteReady = false;
    final ran = <LoginCheckId>[];
    final checks = FirstLoginChecks({
      for (final id in LoginCheckId.values)
        id: () async {
          ran.add(id);
          return id == LoginCheckId.website && !websiteReady ? '未登录' : null;
        },
    });
    addTearDown(checks.dispose);
    await checks.runAll();
    expect(
      checks[LoginCheckId.friendsTimeline].status,
      LoginCheckStatus.blocked,
    );
    expect(checks[LoginCheckId.messages].status, LoginCheckStatus.blocked);
    expect(ran, isNot(contains(LoginCheckId.friendsTimeline)));
    expect(ran, isNot(contains(LoginCheckId.messages)));

    websiteReady = true;
    await checks.run(LoginCheckId.website);
    expect(
      checks[LoginCheckId.friendsTimeline].status,
      LoginCheckStatus.passed,
    );
    expect(checks[LoginCheckId.messages].status, LoginCheckStatus.passed);
    expect(checks.canEnter, isTrue);
    expect(checks.failedCount, 0);
  });

  test('feature failures are reported but do not block entry', () async {
    var attempts = 0;
    final checks = FirstLoginChecks({
      ..._passing(),
      LoginCheckId.messages: () async => ++attempts == 1 ? '私信页暂时无法打开' : null,
      LoginCheckId.community: () => Completer<String?>().future,
    }, timeout: const Duration(milliseconds: 20));
    addTearDown(checks.dispose);
    await checks.runAll();
    expect(checks[LoginCheckId.messages].detail, '私信页暂时无法打开');
    expect(checks[LoginCheckId.community].detail, '连接超时，请重试');
    expect(checks.failedCount, 2);
    expect(checks.canEnter, isTrue);
    await checks.run(LoginCheckId.messages);
    expect(checks[LoginCheckId.messages].status, LoginCheckStatus.passed);
    expect(checks.failedCount, 1);
  });

  Future<_CheckSession> show(
    WidgetTester tester,
    FirstLoginChecks checks, {
    Future<bool?> Function(BuildContext)? openWebsiteLogin,
  }) async {
    addTearDown(checks.dispose);
    final session = _CheckSession();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sessionProvider.overrideWith((ref) => session)],
        child: MaterialApp(
          home: FirstLoginCheckScreen(
            checks: checks,
            openWebsiteLogin: openWebsiteLogin,
          ),
        ),
      ),
    );
    return session;
  }

  testWidgets('passing checks enter home without any extra tap', (
    tester,
  ) async {
    final session = await show(tester, FirstLoginChecks(_passing()));
    expect(find.text('正在准备你的首页'), findsOneWidget);
    await _settle(tester);
    expect(session.completed, 1);
    expect(find.byType(FilledButton), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('missing website login asks once, then continues by itself', (
    tester,
  ) async {
    var websiteReady = false;
    var logins = 0;
    final session = await show(
      tester,
      FirstLoginChecks({
        ..._passing(),
        LoginCheckId.website: () async => websiteReady ? null : '尚未登录网页版',
      }),
      openWebsiteLogin: (_) async {
        logins++;
        websiteReady = true;
        return true;
      },
    );
    await _settle(tester);
    expect(session.completed, 0);
    expect(find.text('还差一步：登录 Bangumi 网页版，好友动态和私信需要用到。'), findsOneWidget);
    expect(find.text('换个账号'), findsOneWidget);
    await tester.tap(find.text('登录网页版'));
    await _settle(tester);
    expect(logins, 1);
    expect(session.completed, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a failing or slow feature check never shows or blocks', (
    tester,
  ) async {
    final slow = Completer<String?>();
    final session = await show(
      tester,
      FirstLoginChecks({
        ..._passing(),
        LoginCheckId.messages: () async => '私信页暂时无法打开',
        LoginCheckId.community: () => slow.future,
      }),
    );
    await tester.pump();
    expect(session.completed, 0);
    await tester.pump(const Duration(seconds: 3));
    expect(session.completed, 1);
    expect(find.text('私信页暂时无法打开'), findsNothing);
    slow.complete(null);
    await _settle(tester);
    expect(session.completed, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('an API failure offers retry instead of entering', (
    tester,
  ) async {
    var attempts = 0;
    final session = await show(
      tester,
      FirstLoginChecks({
        ..._passing(),
        LoginCheckId.api: () async {
          if (++attempts == 1) throw Exception('暂时无法连接 Bangumi');
          return null;
        },
      }),
    );
    await _settle(tester);
    expect(session.completed, 0);
    expect(find.text('暂时无法连接 Bangumi'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await _settle(tester);
    expect(session.completed, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _CheckSession extends SessionController {
  _CheckSession() : super(BangumiApi(), BangumiOAuth(), _TokenStore()) {
    state = const SessionState(
      phase: SessionPhase.signedIn,
      requiresAccessCheck: true,
      user: BangumiUser(
        id: 1,
        username: 'alice',
        nickname: 'Alice',
        avatarUrl: '',
      ),
    );
  }

  int completed = 0;

  @override
  Future<void> completeAccessCheck() async => completed++;
}

class _TokenStore extends TokenStore {
  @override
  Future<BangumiNetworkRoute> readNetworkRoute() =>
      Completer<BangumiNetworkRoute>().future;
}

/// The indeterminate progress bar never settles; flush the probe futures.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
