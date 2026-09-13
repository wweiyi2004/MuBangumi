import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/models/schedule_models.dart';
import 'package:mubangumi/models/schedule_view.dart';
import 'package:mubangumi/state/schedule_view_controller.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'support/memory_schedule_views.dart';

void main() {
  test('all platforms default to today', () {
    expect(defaultScheduleView(TargetPlatform.android), ScheduleView.today);
    expect(defaultScheduleView(TargetPlatform.iOS), ScheduleView.today);
    expect(defaultScheduleView(TargetPlatform.windows), ScheduleView.today);
  });

  test(
    'today and week share sorted schedule items and retain the unscheduled pool',
    () {
      final now = DateTime(2026, 9, 8);
      final schedule = SeasonSchedule(
        season: SeasonKey.current(now),
        items: [
          _item(1, weekday: 2, order: 2),
          _item(2, weekday: 2, order: 0),
          _item(3, weekday: 3),
          _item(4),
        ],
      );
      final today = scheduleSections(schedule, ScheduleView.today, now);
      expect(today.map((section) => section.weekday), [2, null]);
      expect(today.first.items.map((item) => item.subjectId), [2, 1]);
      final week = scheduleSections(schedule, ScheduleView.week, now);
      expect(week.where((section) => section.weekday != null), hasLength(7));
      expect(week.first.date, DateTime(2026, 9, 7));
      expect(week[6].date, DateTime(2026, 9, 13));
      expect(
        week
            .expand((section) => section.items)
            .map((item) => item.subjectId)
            .toSet(),
        {1, 2, 3, 4},
      );
    },
  );

  test(
    'historic seasons show their own weekday arrangement without current dates',
    () {
      final schedule = SeasonSchedule(
        season: const SeasonKey(year: 2025, quarter: 0),
        items: [_item(9, weekday: 2)],
      );
      final sections = scheduleSections(
        schedule,
        ScheduleView.today,
        DateTime(2026, 9, 8),
      );
      expect(sections.single.date, isNull);
      expect(sections.single.items.single.subjectId, 9);
    },
  );

  test('week dates cross month and year boundaries as calendar dates', () {
    final now = DateTime(2027, 1, 1);
    final sections = scheduleSections(
      SeasonSchedule.empty(SeasonKey.current(now)),
      ScheduleView.week,
      now,
    );
    expect(sections.first.date, DateTime(2026, 12, 28));
    expect(sections.last.date, DateTime(2027, 1, 3));
  });

  test(
    'late preferences never override a selection made while loading',
    () async {
      final gate = Completer<ScheduleView?>();
      final repo = MemoryScheduleViews()..pendingRead = gate.future;
      final controller = ScheduleViewController(repo, 1);
      addTearDown(controller.dispose);
      await controller.select(ScheduleView.week);
      gate.complete(ScheduleView.board);
      await pumpEventQueue();
      expect(controller.state.selected, ScheduleView.week);
      expect(repo.views[1], ScheduleView.week);
    },
  );

  test(
    'failed view preference writes keep the chosen mode and can retry',
    () async {
      final repo = MemoryScheduleViews()..failSave = true;
      final controller = ScheduleViewController(repo, 1);
      addTearDown(controller.dispose);
      await pumpEventQueue();
      await controller.select(ScheduleView.week);
      expect(controller.state.selected, ScheduleView.week);
      expect(controller.state.error, contains('未能保存'));
      repo.failSave = false;
      await controller.retry();
      expect(repo.views[1], ScheduleView.week);
      expect(controller.state.error, isNull);
      final other = ScheduleViewController(repo, 2);
      addTearDown(other.dispose);
      await pumpEventQueue();
      expect(other.state.selected, isNull);
    },
  );

  testWidgets(
    'local date updates across midnight and immediately after resume',
    (tester) async {
      var now = DateTime(2026, 9, 8, 23, 59, 59);
      final controller = ScheduleDayController(() => now);
      try {
        now = DateTime(2026, 9, 9, 0, 0, 1);
        await tester.pump(const Duration(seconds: 2));
        expect(controller.state.day, 9);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        now = DateTime(2026, 9, 10, 8);
        await tester.pump(const Duration(hours: 8));
        expect(controller.state.day, 9);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        expect(controller.state.day, 10);
      } finally {
        controller.dispose();
      }
    },
  );

  testWidgets(
    'a changed timezone refreshes the day state even on the same date',
    (tester) async {
      tzdata.initializeTimeZones();
      DateTime now = tz.TZDateTime(
        tz.getLocation('Asia/Shanghai'),
        2026,
        9,
        8,
        10,
      );
      final controller = ScheduleDayController(() => now);
      try {
        final previousOffset = controller.state.timeZoneOffset;
        now = tz.TZDateTime(tz.getLocation('Asia/Tokyo'), 2026, 9, 8, 10);
        controller.refresh();
        expect(controller.state.day, 8);
        expect(controller.state.timeZoneOffset, isNot(previousOffset));
      } finally {
        controller.dispose();
      }
    },
  );
}

ScheduleItem _item(int id, {int? weekday, int order = 0}) => ScheduleItem(
  subjectId: id,
  name: '作品$id',
  nameCn: '',
  imageUrl: '',
  weekday: weekday,
  sortOrder: order,
);
