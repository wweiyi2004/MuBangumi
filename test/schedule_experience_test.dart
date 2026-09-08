import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/network/rss_fetcher.dart';
import 'package:mubangumi/core/storage/browsing_store.dart';
import 'package:mubangumi/models/schedule_models.dart';
import 'package:mubangumi/models/schedule_view.dart';
import 'package:mubangumi/screens/schedule_page.dart';
import 'package:mubangumi/state/rss_controller.dart';
import 'package:mubangumi/state/schedule_controller.dart';
import 'package:mubangumi/state/schedule_view_controller.dart';
import 'package:mubangumi/state/session_controller.dart';
import 'package:mubangumi/widgets/schedule_export_poster.dart';
import 'package:mubangumi/widgets/schedule_list_view.dart';

import 'support/memory_schedule_views.dart';
import 'support/progress_fixtures.dart';
import 'support/schedule_fixtures.dart';
import 'support/ux_visuals.dart';

final _boundary = GlobalKey();
const _todayName = '葬送的芙莉莲：旅途中还没有说完的故事与新的约定';

void main() {
  testWidgets(
    'board dragging still moves items and an old quarter drag cannot change a new table',
    (tester) async {
      final env = _Environment();
      await _show(tester, env, width: 1200, platform: TargetPlatform.windows);
      Finder draggable() => find
          .ancestor(
            of: find.text(_todayName).first,
            matching: find.byWidgetPredicate(
              (widget) => widget is LongPressDraggable,
            ),
          )
          .first;
      final first = await tester.startGesture(tester.getCenter(draggable()));
      await tester.pump(const Duration(milliseconds: 700));
      await first.moveTo(tester.getCenter(find.text('周三')));
      await tester.pump();
      await first.up();
      await tester.pumpAndSettle();
      expect(
        env.schedule.state.schedule.items
            .firstWhere((item) => item.subjectId == 1)
            .weekday,
        3,
      );
      final old = await tester.startGesture(tester.getCenter(draggable()));
      await tester.pump(const Duration(milliseconds: 700));
      const other = SeasonKey(year: 2025, quarter: 1);
      env.store.schedules[other.id] = SeasonSchedule(
        season: other,
        items: [_scheduleItem(1, '另一个季度', 5)],
      );
      await env.schedule.setSeason(other);
      await tester.pump();
      await old.moveTo(tester.getCenter(find.text('周一')));
      await tester.pump();
      await old.up();
      await tester.pumpAndSettle();
      expect(env.schedule.state.schedule.items.single.weekday, 5);
    },
  );
  testWidgets(
    'the phone quarter picker shows its selection and loads the chosen table',
    (tester) async {
      final env = _Environment();
      const other = SeasonKey(year: 2026, quarter: 1);
      env.store.schedules[other.id] = SeasonSchedule(
        season: other,
        items: [_scheduleItem(9, '春季作品', 2)],
      );
      await _show(tester, env);
      expect(find.text('2026 夏季'), findsOneWidget);
      await tester.tap(find.byType(DropdownButtonFormField<SeasonKey>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2026 春季').last);
      await tester.pumpAndSettle();
      expect(env.schedule.state.season, other);
      expect(find.text('春季作品'), findsOneWidget);
      expect(find.text(_todayName), findsNothing);
    },
  );

  testWidgets(
    'reminder saving after a quarter change shows feedback inside the sheet',
    (tester) async {
      final env = _Environment();
      await _show(tester, env);
      await _action(tester, 1, '系统更新提醒');
      const other = SeasonKey(year: 2025, quarter: 1);
      env.store.schedules[other.id] = SeasonSchedule(
        season: other,
        items: [_scheduleItem(1, '另一个季度', 4).copyWith(reminderEnabled: true)],
      );
      await env.schedule.setSeason(other);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SwitchListTile));
      await tester.ensureVisible(find.text('保存'));
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(env.schedule.state.schedule.items.single.reminderEnabled, isTrue);
      expect(find.text('季度已变化，请重新打开提醒设置'), findsWidgets);
      expect(find.byType(SwitchListTile), findsOneWidget);
    },
  );

  testWidgets(
    'a short phone screen with large text can scroll to list actions and reminder controls',
    (tester) async {
      final env = _Environment();
      await _show(tester, env, width: 320, height: 640, scale: 1.8);
      await _action(tester, 1, '系统更新提醒');
      await tester.ensureVisible(find.text('保存'));
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.byType(SwitchListTile), findsNothing);
    },
  );
  testWidgets(
    'phone defaults to today with readable progress and separate RSS status',
    (tester) async {
      final env = _Environment();
      await _show(tester, env);
      expect(
        tester.widget<ScheduleListView>(find.byType(ScheduleListView)).view,
        ScheduleView.today,
      );
      expect(find.text(_todayName), findsOneWidget);
      expect(find.text('明天的作品'), findsNothing);
      expect(find.text('看过 0 / 12 话'), findsWidgets);
      expect(find.text('每周 20:30 提醒'), findsOneWidget);
      expect(find.text('RSS 已发现 2 条未读更新'), findsOneWidget);
      expect(find.textContaining('今天 · 周二'), findsOneWidget);
      final title = tester.widget<Text>(find.text(_todayName));
      expect(title.maxLines, isNull);
    },
  );

  testWidgets(
    'Windows defaults to the board and a saved list view survives rebuilding',
    (tester) async {
      final env = _Environment();
      await _show(tester, env, platform: TargetPlatform.windows);
      expect(find.byType(ScheduleListView), findsNothing);
      await tester.tap(find.text('本周'));
      await tester.pumpAndSettle();
      expect(env.views.views[1], ScheduleView.week);
      await tester.pumpWidget(const SizedBox.shrink());
      final restarted = _Environment(views: env.views);
      await _show(tester, restarted, platform: TargetPlatform.windows);
      expect(
        tester.widget<ScheduleListView>(find.byType(ScheduleListView)).view,
        ScheduleView.week,
      );
    },
  );

  testWidgets(
    'moving, disabling and removing an arrangement updates lists board and reminders',
    (tester) async {
      final env = _Environment();
      await _show(tester, env);
      await _action(tester, 1, '系统更新提醒');
      await tester.tap(find.byType(SwitchListTile));
      await tester.ensureVisible(find.text('保存'));
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(env.schedule.state.schedule.items.first.reminderEnabled, isFalse);
      expect(find.text('系统提醒已关闭'), findsOneWidget);
      await _action(tester, 1, '安排到周三');
      expect(find.text(_todayName), findsNothing);
      expect(find.text('今天没有安排，轻松休息一下。'), findsOneWidget);
      await tester.tap(find.text('本周'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text(_todayName),
        220,
        scrollable: find.byType(Scrollable).last,
      );
      expect(
        env.schedule.state.schedule.items
            .firstWhere((item) => item.subjectId == 1)
            .weekday,
        3,
      );
      await tester.tap(find.text('周表'));
      await tester.pumpAndSettle();
      expect(find.byType(ScheduleListView), findsNothing);
      expect(find.text(_todayName), findsWidgets);
      await tester.tap(find.text('本周'));
      await tester.pumpAndSettle();
      await _action(tester, 1, '删除安排');
      expect(env.schedule.state.schedule.containsSubject(1), isFalse);
      expect(
        env.reminders.syncs.last
            .expand((schedule) => schedule.items)
            .any((item) => item.subjectId == 1),
        isFalse,
      );
    },
  );

  testWidgets(
    'a menu opened in another season cannot remove the new seasons item',
    (tester) async {
      final env = _Environment();
      await _show(tester, env);
      await _openActions(tester, 1);
      final other = SeasonKey(
        year: env.season.year - 1,
        quarter: env.season.quarter,
      );
      env.store.schedules[other.id] = SeasonSchedule(
        season: other,
        items: [_scheduleItem(1, '另一个季度', 2)],
      );
      await env.schedule.setSeason(other);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('删除安排'));
      await tester.tap(find.text('删除安排'));
      await tester.pumpAndSettle();
      expect(env.schedule.state.schedule.items.single.name, '另一个季度');
      expect(find.text('安排已变化，请重新打开操作菜单'), findsOneWidget);
    },
  );

  testWidgets(
    'switching seasons keeps the mode and account changes restore that accounts preference',
    (tester) async {
      final env = _Environment()..views.views[2] = ScheduleView.board;
      await _show(tester, env);
      await tester.tap(find.text('本周'));
      await tester.pumpAndSettle();
      final other = SeasonKey(
        year: env.season.year - 1,
        quarter: env.season.quarter,
      );
      env.store.schedules[other.id] = SeasonSchedule(
        season: other,
        items: [_scheduleItem(9, '旧季度作品', 1)],
      );
      await env.schedule.setSeason(other);
      await tester.pumpAndSettle();
      expect(
        tester.widget<ScheduleListView>(find.byType(ScheduleListView)).view,
        ScheduleView.week,
      );
      expect(find.text('旧季度作品'), findsOneWidget);
      expect(find.text(_todayName), findsNothing);
      expect(find.textContaining('日期标记仅用于当前季度'), findsOneWidget);
      env.session.switchUser(2);
      await tester.pumpAndSettle();
      expect(find.byType(ScheduleListView), findsNothing);
      expect(env.views.views[1], ScheduleView.week);
    },
  );

  testWidgets(
    'today changes across midnight and after returning from background',
    (tester) async {
      final env = _Environment()..now = DateTime(2026, 9, 8, 23, 59, 59);
      await _show(tester, env);
      expect(find.text(_todayName), findsOneWidget);
      env.now = DateTime(2026, 9, 9, 0, 0, 1);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('明天的作品'), findsOneWidget);
      expect(find.text(_todayName), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      env.now = DateTime(2026, 9, 10, 8);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('今天没有安排，轻松休息一下。'), findsOneWidget);
      expect(find.text('明天的作品'), findsNothing);
    },
  );

  testWidgets('export from list mode still uses the existing weekly poster', (
    tester,
  ) async {
    final env = _Environment();
    await _show(tester, env);
    await tester.tap(find.byTooltip('新番表更多操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('导出图片'));
    await tester.pumpAndSettle();
    expect(find.byType(ScheduleExportPoster), findsOneWidget);
    expect(
      tester
          .widget<ScheduleExportPoster>(find.byType(ScheduleExportPoster))
          .schedule
          .items,
      hasLength(3),
    );
  });

  for (final width in [320.0, 390.0, 1200.0]) {
    for (final scale in [1.0, 1.8]) {
      for (final dark in [false, true]) {
        testWidgets('schedule views $width scale $scale dark $dark', (
          tester,
        ) async {
          final env = _Environment();
          await _show(
            tester,
            env,
            width: width,
            scale: scale,
            dark: dark,
            platform: width >= 720
                ? TargetPlatform.windows
                : TargetPlatform.android,
          );
          for (final mode in ScheduleView.values) {
            await tester.tap(find.text(mode.label));
            await tester.pumpAndSettle();
            await captureUx(
              tester,
              _boundary,
              'm3_${mode.name}_${width}_${scale}_$dark',
            );
          }
          final empty = SeasonKey(
            year: env.season.year + 1,
            quarter: env.season.quarter,
          );
          await env.schedule.setSeason(empty);
          await tester.tap(find.text('今日'));
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('本季还没有安排'));
        });
      }
    }
  }
}

Future<void> _openActions(WidgetTester tester, int id) async {
  final card = find.byKey(ValueKey('schedule-list-$id'));
  await tester.scrollUntilVisible(
    card,
    200,
    scrollable: find.byType(Scrollable).last,
  );
  final button = find.descendant(of: card, matching: find.byTooltip('安排操作'));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> _action(WidgetTester tester, int id, String label) async {
  await _openActions(tester, id);
  await tester.ensureVisible(find.text(label));
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

class _Environment {
  _Environment({MemoryScheduleViews? views})
    : views = views ?? MemoryScheduleViews() {
    store.schedules[season.id] = SeasonSchedule(
      season: season,
      items: [
        _scheduleItem(
          1,
          _todayName,
          2,
        ).copyWith(reminderEnabled: true, reminderHour: 20, reminderMinute: 30),
        _scheduleItem(2, '明天的作品', 3),
        _scheduleItem(3, '还没安排的作品', null),
      ],
    );
  }
  DateTime now = DateTime(2026, 9, 8, 10);
  final season = const SeasonKey(year: 2026, quarter: 2);
  final store = MemorySchedules();
  final reminders = MemoryScheduleReminders();
  final MemoryScheduleViews views;
  late final session = ProgressSession(ProgressApi(), ProgressCache());
  late final schedule = ScheduleController(store, reminders);
  late final rss = RssController(ScheduleRssStore(), RssFetcher());
}

ScheduleItem _scheduleItem(int id, String name, int? day) => ScheduleItem(
  subjectId: id,
  name: name,
  nameCn: '',
  imageUrl: '',
  weekday: day,
  episodeCount: 12,
);

Future<void> _show(
  WidgetTester tester,
  _Environment env, {
  double width = 390,
  double height = 1000,
  double scale = 1,
  bool dark = false,
  TargetPlatform platform = TargetPlatform.android,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final theme = (await uxTheme(
    tester,
    dark: dark,
  )).copyWith(platform: platform);
  await env.schedule.setSeason(env.season);
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        sessionProvider.overrideWith((ref) => env.session),
        scheduleProvider.overrideWith((ref) => env.schedule),
        rssProvider.overrideWith((ref) => env.rss),
        scheduleViewRepositoryProvider.overrideWithValue(env.views),
        scheduleNowProvider.overrideWithValue(() => env.now),
      ],
      child: MaterialApp(
        theme: theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: RepaintBoundary(key: _boundary, child: child!),
        ),
        home: const SchedulePage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
