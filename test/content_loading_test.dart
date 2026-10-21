import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/widgets/content_loading.dart';
import 'package:mubangumi/core/theme/app_tokens.dart';

void main() {
  testWidgets(
    'fast requests never flash feedback; slow reads retain content and actions',
    (tester) async {
      var active = true, operation = 1, retries = 0, opens = 0;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return Column(
                  children: [
                    LoadingStatus(
                      active: active,
                      operation: operation,
                      message: '正在同步私信',
                      onRetry: () => retries++,
                      onOpenWebsite: () => opens++,
                    ),
                    TextButton(onPressed: () {}, child: const Text('已有内容仍可使用')),
                  ],
                );
              },
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('正在同步私信'), findsNothing);
      update(() => active = false);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('正在同步私信'), findsNothing);
      update(() {
        active = true;
        operation++;
      });
      await tester.pump();
      await tester.pump(AppMotion.loadingDelay);
      expect(find.text('正在同步私信'), findsOneWidget);
      await tester.tap(find.text('已有内容仍可使用'));
      await tester.pump(AppMotion.slowLoading);
      expect(find.text('仍在加载，网络可能较慢'), findsOneWidget);
      await tester.tap(find.text('重试'));
      await tester.tap(find.text('在官网打开'));
      expect(retries, 1);
      expect(opens, 1);
      update(() => operation++);
      await tester.pump();
      expect(find.text('仍在加载，网络可能较慢'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 10));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('reduced motion uses static content with no transition ticker', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(body: ContentTransition(child: ContentSkeleton())),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AnimatedSwitcher), findsNothing);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });
}
