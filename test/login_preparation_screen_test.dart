import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/theme/app_theme.dart';
import 'package:mubangumi/screens/login_preparation_screen.dart';
import 'package:mubangumi/widgets/login_progress.dart';

void main() {
  testWidgets('preparation shows actual stages and slow-load escape', (
    tester,
  ) async {
    var entered = 0;
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: LoginPreparationScreen(nickname: '小沐', onEnter: () => entered++),
      ),
    );
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.text('欢迎，小沐'), findsOneWidget);
    final bars = tester
        .widgetList<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator),
        )
        .toList();
    expect(bars.map((bar) => bar.value), [1.0, 1.0, null]);
    await tester.pump(const Duration(seconds: 3));
    expect(find.textContaining('连接比平时慢'), findsOneWidget);
    await tester.tap(find.byKey(const Key('enter-home-now-button')));
    expect(entered, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('compact landscape and large text remain scrollable', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(568, 320));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(1.8),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: LoginPreparationScreen(nickname: '很长的昵称也可以自然换行', onEnter: () {}),
      ),
    );
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('enter-home-now-button')));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('entrance honors reduced motion', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: LoginEntrance(child: Text('首页')),
        ),
      ),
    );
    expect(find.text('首页'), findsOneWidget);
    expect(find.byType(TweenAnimationBuilder<double>), findsNothing);
  });
}
