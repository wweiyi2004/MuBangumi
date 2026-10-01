import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/theme/app_theme.dart';
import 'package:mubangumi/core/theme/custom_colors.dart';
import 'package:mubangumi/core/shortcuts/shared_bangumi_link.dart';
import 'package:mubangumi/screens/library_page.dart';
import 'package:mubangumi/state/session_controller.dart';
import 'package:mubangumi/widgets/home_greeting_clock.dart';
import 'support/pm_fixtures.dart';
import 'support/ux_visuals.dart';

void main() {
  testWidgets('clock uses greeting typography without a colored badge', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: DefaultTextStyle(
            style: const TextStyle(height: 2.2),
            child: HomeGreetingClock(
              nickname: '小沐',
              phone: true,
              now: () => DateTime(2026, 10, 1, 12, 13),
            ),
          ),
        ),
      ),
    );
    final text = find.byKey(const ValueKey('home-clock'));
    final greeting = tester.widget<Text>(find.text('下午好'));
    final time = tester.widget<Text>(text);
    expect(time.style!.fontSize, greeting.style!.fontSize);
    expect(time.style!.fontWeight, greeting.style!.fontWeight);
    expect(time.style!.color, greeting.style!.color);
    expect(time.style!.fontFamily, greeting.style!.fontFamily);
    expect(time.style!.height, greeting.style!.height);
    expect(
      find.descendant(
        of: find.byType(HomeGreetingClock),
        matching: find.byType(DecoratedBox),
      ),
      findsNothing,
    );
    expect(
      tester.getCenter(text).dy,
      closeTo(tester.getCenter(find.text('下午好')).dy, .5),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  test(
    'download QR wrappers preserve destinations and reject forged download hosts',
    () {
      for (final source in [
        'https://bgm.tv/subject/42',
        'https://bgm.tv/index/9',
        'https://bgm.tv/user/alice/timeline/status/64',
        'https://bgm.tv/user/alice/timeline?until=65',
      ]) {
        final original = SharedBangumiLink.parse(source)!;
        final qr = original.qrUrl;
        expect(
          Uri.parse(qr).removeFragment().toString(),
          SharedBangumiLink.downloadUrl,
        );
        expect(SharedBangumiLink.parse(qr)!.url, original.url);
        expect(SharedBangumiLink.fromText('分享：$qr').single.url, original.url);
        expect(
          SharedBangumiLink.parse(
            qr.replaceFirst('github.com', 'github.com.evil.test'),
          ),
          isNull,
        );
      }
      for (final raw in [
        '${SharedBangumiLink.downloadUrl}#https://evil.test/subject/42',
        '${SharedBangumiLink.downloadUrl}?next=evil#subject/42',
        '${SharedBangumiLink.downloadUrl}#subject/0',
        '${SharedBangumiLink.downloadUrl}#settings',
        'https://user@github.com/wweiyi2004/MuBangumi/releases/latest#subject/42',
        'https://github.com:8443/wweiyi2004/MuBangumi/releases/latest#subject/42',
      ]) {
        expect(SharedBangumiLink.parse(raw), isNull);
      }
    },
  );
  testWidgets(
    '24-hour clock changes greetings at minute boundaries and refreshes after resume',
    (tester) async {
      var now = DateTime(2026, 10, 1, 10, 59, 59);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: HomeGreetingClock(
              nickname: '小沐',
              phone: true,
              now: () => now,
            ),
          ),
        ),
      );
      expect(find.text('10:59'), findsOneWidget);
      expect(find.text('早上好'), findsOneWidget);
      now = DateTime(2026, 10, 1, 11);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('11:00'), findsOneWidget);
      expect(find.text('下午好'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      now = DateTime(2026, 10, 2, 0, 3);
      await tester.pump(const Duration(minutes: 2));
      expect(find.text('11:00'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('00:03'), findsOneWidget);
      expect(find.text('早上好'), findsOneWidget);
      expect(find.textContaining('10 月 2 日'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(minutes: 2));
      expect(tester.takeException(), isNull);
    },
  );
  for (final width in [320.0, 390.0, 520.0]) {
    for (final scale in [1.0, 1.8]) {
      testWidgets(
        'collection header keeps three actions on one row at $width / $scale',
        (tester) async {
          tester.view.physicalSize = Size(width, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final theme = await uxTheme(tester, dark: false);
          final key = GlobalKey();
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                sessionProvider.overrideWith((ref) => PmTestSession()),
              ],
              child: MaterialApp(
                theme: theme,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: RepaintBoundary(key: key, child: child!),
                ),
                home: Scaffold(body: const LibraryPage(rememberFilters: false)),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final positions = [
            for (final label in ['番剧单', '统计与回顾', '批量整理'])
              tester.getCenter(find.text(label)),
          ];
          expect(positions[0].dy, closeTo(positions[1].dy, 1));
          expect(positions[1].dy, closeTo(positions[2].dy, 1));
          expect(positions[0].dx, lessThan(positions[1].dx));
          expect(positions[1].dx, lessThan(positions[2].dx));
          expect(tester.takeException(), isNull);
          await captureUx(
            tester,
            key,
            'library-header-${width.toInt()}-$scale',
          );
          if (scale == 1) {
            await tester.tap(find.byTooltip('收藏状态'));
            await tester.pumpAndSettle();
            final shapes = tester
                .widgetList<Material>(find.byType(Material))
                .map((m) => m.shape)
                .whereType<RoundedRectangleBorder>();
            expect(
              shapes.any(
                (s) =>
                    s.borderRadius.resolve(TextDirection.ltr).topLeft.x == 16,
              ),
              true,
            );
            await captureUx(tester, key, 'library-status-${width.toInt()}');
            await tester.tap(find.text('全部状态'));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          }
        },
      );
    }
  }
  testWidgets('clock fits narrow greeting area at large text', (tester) async {
    final key = GlobalKey();
    final theme = await uxTheme(tester, dark: false);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Center(
            child: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
              child: RepaintBoundary(
                key: key,
                child: SizedBox(
                  width: 170,
                  child: HomeGreetingClock(
                    nickname: '小沐',
                    phone: true,
                    now: () => DateTime(2026, 10, 1, 14, 7),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('14:07'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await captureUx(tester, key, 'home-clock-large');
    await tester.pumpWidget(const SizedBox());
  });
  test('floating menus match light, dark and custom surfaces', () {
    for (final t in [
      AppTheme.light,
      AppTheme.dark,
      applyCustomColors(
        AppTheme.light,
        const CustomColors(primary: Color(0xFF9386C8)),
      ),
    ]) {
      expect(t.popupMenuTheme.color, t.colorScheme.surface);
      final shapes = [
        t.popupMenuTheme.shape!,
        t.menuTheme.style!.shape!.resolve({})!,
        t.dropdownMenuTheme.menuStyle!.shape!.resolve({})!,
      ];
      for (final shape in shapes) {
        expect(
          (shape as RoundedRectangleBorder).borderRadius
              .resolve(TextDirection.ltr)
              .topLeft
              .x,
          16,
        );
      }
    }
  });
}
