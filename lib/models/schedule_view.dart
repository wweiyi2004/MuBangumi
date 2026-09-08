import 'package:flutter/foundation.dart';

import 'schedule_models.dart';

enum ScheduleView {
  today('今日'),
  week('本周'),
  board('周表');

  const ScheduleView(this.label);
  final String label;
}

ScheduleView defaultScheduleView(TargetPlatform platform) =>
    platform == TargetPlatform.android || platform == TargetPlatform.iOS
    ? ScheduleView.today
    : ScheduleView.board;

class ScheduleDaySection {
  const ScheduleDaySection({
    required this.weekday,
    required this.items,
    this.date,
  });
  final int? weekday;
  final DateTime? date;
  final List<ScheduleItem> items;
}

List<ScheduleDaySection> scheduleSections(
  SeasonSchedule schedule,
  ScheduleView view,
  DateTime now,
) {
  final currentSeason = schedule.season == SeasonKey.current(now);
  final days = view == ScheduleView.today
      ? [now.weekday]
      : [for (var day = 1; day <= 7; day++) day];
  return [
    for (final day in days)
      ScheduleDaySection(
        weekday: day,
        date: currentSeason
            ? DateTime(now.year, now.month, now.day - now.weekday + day)
            : null,
        items: schedule.itemsOn(day),
      ),
    if (schedule.unscheduled.isNotEmpty)
      ScheduleDaySection(weekday: null, items: schedule.unscheduled),
  ];
}
