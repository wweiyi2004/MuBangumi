import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/storage/browsing_store.dart';
import 'package:mubangumi/screens/home_page.dart';
import 'package:mubangumi/state/notify_controller.dart';
import 'package:mubangumi/state/session_controller.dart';
import 'package:mubangumi/widgets/episode_grid_sheet.dart';
import 'package:mubangumi/widgets/continue_watching_tile.dart';

import 'support/memory_home_pins.dart';
import 'support/progress_fixtures.dart';
import 'support/ux_visuals.dart';

final _boundary = GlobalKey();

void main() {
  testWidgets(
    'an open chapter status dialog cannot edit after an account switch',
    (tester) async {
      final env = _Environment();
      await _show(tester, env, grid: true);
      await tester.longPress(find.text('1').last);
      await tester.pumpAndSettle();
      env.session.switchUser(2);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(SimpleDialog),
          matching: find.text('看过'),
        ),
      );
      await tester.pumpAndSettle();
      expect(env.api.writes, isEmpty);
      expect(find.text('登录已变化，请重新打开章节'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'home pinning promotes a hidden preview item and preserves total count',
    (tester) async {
      final env = _Environment();
      await _show(tester, env);
      expect(_homeIds(tester), isNot(contains(20)));
      await tester.tap(find.byTooltip('管理首页置顶'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('正在追的作品 20'),
        500,
        scrollable: find.byType(Scrollable).last,
      );
      final tile = find.ancestor(
        of: find.text('正在追的作品 20'),
        matching: find.byType(Card),
      );
      await tester.tap(
        find.descendant(of: tile, matching: find.byTooltip('置顶到首页')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      expect(_homeIds(tester).first, 20);
      expect(_homeIds(tester), hasLength(18));
      expect(find.text('查看全部（20）'), findsOneWidget);
      env.session.finish(20);
      await tester.pumpAndSettle();
      expect(_homeIds(tester), isNot(contains(20)));
      expect(find.text('查看全部（19）'), findsOneWidget);
    },
  );

  testWidgets('pin order controls affect only the current account', (
    tester,
  ) async {
    final env = _Environment()
      ..pins.data[1] = [2, 1]
      ..pins.data[2] = [3];
    await _show(tester, env);
    expect(_homeIds(tester).take(2), [2, 1]);
    await tester.tap(find.byTooltip('管理首页置顶'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('下移').first);
    await tester.pumpAndSettle();
    expect(env.pins.data[1], [1, 2]);
    env.session.switchUser(2);
    await tester.pumpAndSettle();
    expect(find.text('登录已变化，请重新打开首页置顶'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(_homeIds(tester).first, 3);
  });

  testWidgets('next episode offers undo with a specific title and chapter', (
    tester,
  ) async {
    final env = _Environment();
    await _show(tester, env);
    await _next(tester);
    expect(find.textContaining('本篇 第 1 话'), findsOneWidget);
    expect(env.session.state.collectionFor(1)!.episodeStatus, 1);
    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect(env.session.state.collectionFor(1)!.episodeStatus, 0);
    expect(env.api.writes, [2, 0]);
  });

  testWidgets(
    'undo times out normally but stays available for accessible navigation',
    (tester) async {
      final env = _Environment();
      await _show(tester, env);
      await _next(tester);
      await tester.pump(const Duration(seconds: 11));
      await tester.pumpAndSettle();
      expect(find.text('撤销'), findsNothing);
      expect(env.session.pendingEpisodeUndo, isNull);
      await _show(tester, _Environment(), accessible: true);
      await _next(tester);
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(find.text('撤销'), findsOneWidget);
    },
  );

  testWidgets(
    'episode grid renders undo above its modal and updates its cell',
    (tester) async {
      final env = _Environment();
      await _show(tester, env, grid: true);
      await tester.tap(find.text('1').last);
      await tester.pumpAndSettle();
      final undo = find.text('撤销');
      expect(undo, findsOneWidget);
      expect(tester.getRect(undo).bottom, lessThanOrEqualTo(1000));
      expect(find.text('看过 1 / 12'), findsOneWidget);
      await tester.tap(undo);
      await tester.pumpAndSettle();
      expect(find.text('看过 0 / 12'), findsOneWidget);
      env.session.switchUser(2);
      await tester.pumpAndSettle();
      expect(find.text('登录已变化，请重新打开章节'), findsOneWidget);
    },
  );

  for (final width in [320.0, 390.0, 1200.0]) {
    for (final scale in [1.0, 1.8]) {
      for (final dark in [false, true]) {
        testWidgets('progress UI $width scale $scale dark $dark', (
          tester,
        ) async {
          final env = _Environment()..pins.data[1] = [2, 1];
          await _show(tester, env, width: width, scale: scale, dark: dark);
          await captureUx(tester, _boundary, 'm2_home_${width}_${scale}_$dark');
          expect(tester.takeException(), isNull);
          await tester.tap(find.byTooltip('管理首页置顶'));
          await tester.pumpAndSettle();
          await captureUx(tester, _boundary, 'm2_pins_${width}_${scale}_$dark');
          expect(tester.takeException(), isNull);
          await tester.tap(find.byTooltip('关闭'));
          await tester.pumpAndSettle();
          // Open a real grid through the home card action.
          await tester.ensureVisible(find.byTooltip('选择集数').first);
          await tester.tap(find.byTooltip('选择集数').first);
          await tester.pumpAndSettle();
          await tester.tap(find.text('1').last);
          await tester.pumpAndSettle();
          await captureUx(tester, _boundary, 'm2_grid_${width}_${scale}_$dark');
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}

List<int> _homeIds(WidgetTester tester) => tester
    .widgetList<ContinueWatchingTile>(find.byType(ContinueWatchingTile))
    .map((card) => card.collection.subject.id)
    .toList();
Future<void> _next(WidgetTester tester) async {
  await tester.ensureVisible(find.text('看完下一集').first);
  await tester.tap(find.text('看完下一集').first);
  await tester.pumpAndSettle();
}

class _Environment {
  final api = ProgressApi();
  final cache = ProgressCache();
  final pins = MemoryHomePins();
  late final session = ProgressSession(api, cache);
}

Future<void> _show(
  WidgetTester tester,
  _Environment env, {
  bool grid = false,
  double width = 390,
  double scale = 1,
  bool dark = false,
  bool accessible = false,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final theme = await uxTheme(tester, dark: dark);
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        sessionProvider.overrideWith((ref) => env.session),
        bangumiApiProvider.overrideWithValue(env.api),
        snapshotCacheProvider.overrideWithValue(env.cache),
        homePinsRepositoryProvider.overrideWithValue(env.pins),
        notifyBadgeProvider.overrideWith(
          (ref) => NotifyBadgeController(
            isAuthenticated: () => false,
            initiallyForeground: false,
          ),
        ),
      ],
      child: MaterialApp(
        theme: theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            accessibleNavigation: accessible,
          ),
          child: RepaintBoundary(key: _boundary, child: child!),
        ),
        home: Scaffold(
          body: grid
              ? Consumer(
                  builder: (context, ref, _) => TextButton(
                    onPressed: () => showEpisodeGridSheet(
                      context,
                      ref,
                      progressCollection(1),
                    ),
                    child: const Text('打开格子'),
                  ),
                )
              : HomePage(onDiscover: () {}, onSchedule: () {}),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (grid) {
    await tester.tap(find.text('打开格子'));
    await tester.pumpAndSettle();
  }
}
