import 'package:mubangumi/navigation/app_destination.dart';
import 'package:mubangumi/navigation/app_router.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/widgets/ascii_refresh.dart';

Widget surface(
  GlobalKey<AsciiRefreshState> key,
  Future<void> Function() refresh, {
  bool initial = true,
  bool reduced = false,
}) => AppRouteScope(
  resolve: AppRouter.resolve,
  child: MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduced),
      child: Scaffold(
        body: AsciiRefresh(
          key: key,
          initialRefresh: initial,
          onRefresh: refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: ClampingScrollPhysics(),
            ),
            children: const [SizedBox(height: 120, child: Text('内容'))],
          ),
        ),
      ),
    ),
  ),
);
void main() {
  testWidgets('failed refresh shows failure instead of a success tick', (
    tester,
  ) async {
    final key = GlobalKey<AsciiRefreshState>();
    await tester.pumpWidget(
      surface(key, () async => throw StateError('offline')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.text('加载失败，向下重试'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(SizeTransition)).height, 0);
  });
  testWidgets(
    'first load slides in, animates projection dots and retracts after completion',
    (tester) async {
      final key = GlobalKey<AsciiRefreshState>(), gate = Completer<void>();
      await tester.pumpWidget(surface(key, () => gate.future));
      await tester.pump(const Duration(milliseconds: 220));
      expect(find.text('正在加载…'), findsOneWidget);
      String frame() => tester
          .widgetList<Text>(find.byType(Text))
          .where((t) => t.textSpan != null)
          .single
          .textSpan!
          .toPlainText();
      final first = frame();
      await tester.pump(const Duration(milliseconds: 240));
      expect(frame(), isNot(first));
      gate.complete();
      await tester.pump();
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(SizeTransition)).height, 0);
    },
  );
  testWidgets(
    'short pull cancels and released longer pull refreshes exactly once',
    (tester) async {
      final key = GlobalKey<AsciiRefreshState>();
      var count = 0;
      await tester.pumpWidget(
        surface(key, () async {
          count++;
        }, initial: false),
      );
      await tester.drag(find.byType(ListView), const Offset(0, 30));
      await tester.pumpAndSettle();
      expect(count, 0);
      await tester.drag(find.byType(ListView), const Offset(0, 220));
      await tester.pumpAndSettle();
      expect(count, 1);
      expect(tester.getSize(find.byType(SizeTransition)).height, 0);
    },
  );
  testWidgets(
    'refresh requests coalesce and disposal cancels animation delays',
    (tester) async {
      final key = GlobalKey<AsciiRefreshState>(), gate = Completer<void>();
      var count = 0;
      await tester.pumpWidget(
        surface(key, () {
          count++;
          return gate.future;
        }, initial: false),
      );
      unawaited(key.currentState!.refresh());
      unawaited(key.currentState!.refresh());
      await tester.pump();
      expect(count, 1);
      gate.complete();
      await tester.pump(const Duration(milliseconds: 420));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('reduced motion keeps the character drawing still', (
    tester,
  ) async {
    final key = GlobalKey<AsciiRefreshState>(), gate = Completer<void>();
    await tester.pumpWidget(surface(key, () => gate.future, reduced: true));
    await tester.pump();
    final text = tester
        .widgetList<Text>(find.byType(Text))
        .where((t) => t.textSpan != null)
        .single
        .textSpan!
        .toPlainText();
    await tester.pump(const Duration(milliseconds: 450));
    expect(
      tester
          .widgetList<Text>(find.byType(Text))
          .where((t) => t.textSpan != null)
          .single
          .textSpan!
          .toPlainText(),
      text,
    );
    gate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
