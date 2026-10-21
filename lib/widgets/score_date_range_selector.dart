import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'score_chart_controls.dart';

/// Two date handles always use the complete history, so a narrowed window can
/// be expanded again without reloading data or losing either endpoint.
class ScoreDateRangeSelector extends StatelessWidget {
  const ScoreDateRangeSelector({
    super.key,
    required this.dates,
    required this.onChanged,
    this.start,
    this.end,
  });
  final List<DateTime> dates;
  final DateTime? start, end;
  final ValueChanged<DateTimeRange> onChanged;

  static int _day(DateTime value) {
    final local = value.toLocal();
    return DateTime.utc(
          local.year,
          local.month,
          local.day,
        ).millisecondsSinceEpoch ~/
        Duration.millisecondsPerDay;
  }

  static DateTime _date(int day) {
    final utc = DateTime.fromMillisecondsSinceEpoch(
      day * Duration.millisecondsPerDay,
      isUtc: true,
    );
    return DateTime(utc.year, utc.month, utc.day);
  }

  @override
  Widget build(BuildContext context) {
    if (dates.isEmpty) return const SizedBox.shrink();
    final days = dates.map(_day);
    final first = days.reduce(math.min), last = days.reduce(math.max);
    final span = last - first;
    final lower = ((start == null ? first : _day(start!)) - first)
        .clamp(0, span)
        .toDouble();
    final upper = ((end == null ? last : _day(end!)) - first)
        .clamp(0, span)
        .toDouble();
    final values = RangeValues(math.min(lower, upper), math.max(lower, upper));
    String label(double offset) =>
        scoreChartDate(_date(first + offset.round()));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 12,
          runSpacing: 4,
          children: [
            Text(
              '起始日期 ${label(values.start)}',
              key: const ValueKey('score-range-start'),
            ),
            Text(
              '结束日期 ${label(values.end)}',
              key: const ValueKey('score-range-end'),
            ),
          ],
        ),
        RangeSlider(
          key: const ValueKey('score-date-range-slider'),
          min: 0,
          max: math.max(1, span).toDouble(),
          divisions: span > 0 ? span : null,
          values: values,
          labels: RangeLabels(label(values.start), label(values.end)),
          semanticFormatterCallback: label,
          onChanged: span == 0
              ? null
              : (value) => onChanged(
                  DateTimeRange(
                    start: _date(first + value.start.round()),
                    end: _date(first + value.end.round()),
                  ),
                ),
        ),
        Text(
          span == 0 ? '仅有一天的历史记录' : '拖动两端调整起止日期，评分轴自动适配',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
