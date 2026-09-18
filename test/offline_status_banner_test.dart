import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/state/network_status_controller.dart';
import 'package:mubangumi/state/session_controller.dart';
import 'package:mubangumi/widgets/network_recovery_host.dart';

import 'support/progress_fixtures.dart';
import 'support/ux_visuals.dart';

void main() {
  for (final width in [320.0, 1200.0]) {
    testWidgets(
      'offline notice fits $width with large text and preserves navigation',
      (tester) async {
        final env = _Environment();
        final key = GlobalKey();
        await _show(tester, env, key, width: width);
        expect(find.textContaining('当前无网络'), findsOneWidget);
        expect(find.textContaining('2026/01/02'), findsOneWidget);
        await tester.tap(find.text('详情'));
        await tester.pumpAndSettle();
        await captureUx(tester, key, 'offline_notice_${width}_1.8');
        expect(find.text('详情内容'), findsOneWidget);
        env.monitor.events.add(NetworkAvailability.available);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pumpAndSettle();
        expect(env.session.refreshCalls, 1);
        expect(find.textContaining('当前无网络'), findsNothing);
        expect(find.text('详情内容'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'interface with no Internet keeps cache notice and does not loop',
    (tester) async {
      final env = _Environment()..session.failRefresh = true;
      await _show(tester, env, GlobalKey());
      env.monitor.events.add(NetworkAvailability.available);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 10));
      expect(env.session.refreshCalls, 1);
      expect(find.textContaining('收藏暂未更新'), findsOneWidget);
      expect(find.textContaining('2026/01/02'), findsOneWidget);
    },
  );

  testWidgets('a pending recovery cannot refresh after logout', (tester) async {
    final env = _Environment();
    await _show(tester, env, GlobalKey());
    env.monitor.events.add(NetworkAvailability.available);
    await tester.pump();
    env.session.leave();
    await tester.pump(const Duration(milliseconds: 600));
    expect(env.session.refreshCalls, 0);
    expect(find.textContaining('当前无网络'), findsNothing);
  });
}

class _Environment {
  final session = _Session();
  final monitor = _Monitor();
}

class _Session extends ProgressSession {
  _Session() : super(ProgressApi(), ProgressCache()) {
    state = state.copyWith(
      isUsingCachedCollections: true,
      collectionsSavedAt: DateTime(2026, 1, 2, 3, 4),
    );
  }
  int refreshCalls = 0;
  bool failRefresh = false;
  void leave() => state = const SessionState(phase: SessionPhase.signedOut);
  @override
  Future<void> refresh({bool showIndicator = true}) async {
    refreshCalls++;
    state = state.copyWith(isLoadingCollections: true);
    await Future<void>.value();
    state = state.copyWith(
      isLoadingCollections: false,
      isUsingCachedCollections: failRefresh,
    );
  }
}

class _Monitor implements NetworkMonitor {
  final events = StreamController<NetworkAvailability>.broadcast();
  @override
  Future<NetworkAvailability> check() async => NetworkAvailability.unavailable;
  @override
  Stream<NetworkAvailability> get changes => events.stream;
}

Future<void> _show(
  WidgetTester tester,
  _Environment env,
  GlobalKey key, {
  double width = 390,
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(env.monitor.events.close);
  final theme = await uxTheme(tester, dark: false);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionProvider.overrideWith((ref) => env.session),
        networkMonitorProvider.overrideWithValue(env.monitor),
      ],
      child: MaterialApp(
        theme: theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(1.8)),
          child: RepaintBoundary(
            key: key,
            child: NetworkRecoveryHost(child: child!),
          ),
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                child: const Text('详情'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const Scaffold(body: Text('详情内容')),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
