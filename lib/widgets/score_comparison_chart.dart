import 'chart_viewport.dart';
import 'score_chart_controls.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/netaba_models.dart';

class ScoreComparisonLine {
  const ScoreComparisonLine(this.label, this.points, this.color);
  final String label;
  final List<NetabaChartPoint> points;
  final Color color;
}

class ScoreComparisonChart extends StatefulWidget {
  const ScoreComparisonChart({
    super.key,
    required this.lines,
    this.axes = const ScoreChartAxes(),
    this.markKeyPoints = false,
    this.interactive = true,
  });
  final List<ScoreComparisonLine> lines;
  final ScoreChartAxes axes;
  final bool markKeyPoints;
  final bool interactive;
  @override
  State<ScoreComparisonChart> createState() => _ScoreComparisonChartState();
}

class _ScoreComparisonChartState extends State<ScoreComparisonChart> {
  double? _position;
  @override
  Widget build(BuildContext context) {
    final points = widget.lines
        .expand((line) => line.points)
        .where(widget.axes.includes)
        .toList();
    if (points.isEmpty) {
      return SizedBox(
        height: 260,
        child: Center(
          child: Text(
            widget.lines.any((line) => line.points.isNotEmpty)
                ? '当前日期范围内暂无历史评分，可拖动日期指针调整'
                : '选择作品后显示历史折线；暂无数据的作品会单独说明',
          ),
        ),
      );
    }
    final baseMinTime =
        widget.axes.start?.millisecondsSinceEpoch ??
        points.map((point) => point.at.millisecondsSinceEpoch).reduce(math.min);
    final baseMaxTime =
        (widget.axes.end == null
            ? null
            : DateTime(
                    widget.axes.end!.year,
                    widget.axes.end!.month,
                    widget.axes.end!.day + 1,
                  ).millisecondsSinceEpoch -
                  1) ??
        points.map((point) => point.at.millisecondsSinceEpoch).reduce(math.max);
    String date(int time) {
      final at = DateTime.fromMillisecondsSinceEpoch(time);
      return '${at.year}/${at.month}/${at.day}';
    }

    final baseMinimum =
        widget.axes.minimum ??
        (points.map((p) => p.value).reduce(math.min) - .3)
            .floorToDouble()
            .clamp(0.0, 9.0);
    final baseMaximum =
        widget.axes.maximum ??
        (points.map((p) => p.value).reduce(math.max) + .3).ceilToDouble().clamp(
          baseMinimum + 1,
          10.0,
        );
    return ChartViewport(
      enabled: widget.interactive,
      resetKey: (widget.axes, widget.lines),
      builder: (context, viewport) {
        final minTime =
            (baseMinTime + (baseMaxTime - baseMinTime) * viewport.left).round();
        final maxTime =
            (baseMinTime + (baseMaxTime - baseMinTime) * viewport.right)
                .round();
        final minimum =
            baseMaximum - (baseMaximum - baseMinimum) * viewport.bottom;
        final maximum =
            baseMaximum - (baseMaximum - baseMinimum) * viewport.top;
        final time = _position == null
            ? null
            : (minTime + (maxTime - minTime) * _position!).round();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                void inspect(double x) => setState(
                  () => _position = ((x - 40) / (constraints.maxWidth - 52))
                      .clamp(0.0, 1.0),
                );
                return Semantics(
                  label: '作品评分历史对比，同一日期轴、同一评分轴。点击图表查看附近的实际记录。',
                  value:
                      '${date(minTime)} 至 ${date(maxTime)}，评分 ${minimum.toStringAsFixed(2)} 至 ${maximum.toStringAsFixed(2)}',
                  child: MouseRegion(
                    onHover: (event) => inspect(event.localPosition.dx),
                    child: GestureDetector(
                      onTapDown: (event) => inspect(event.localPosition.dx),
                      child: SizedBox(
                        height: 260,
                        child: CustomPaint(
                          key: const ValueKey('score-comparison-plot'),
                          painter: _ComparisonPainter(
                            [
                              for (final line in widget.lines)
                                ScoreComparisonLine(
                                  line.label,
                                  line.points
                                      .where(widget.axes.includes)
                                      .toList(),
                                  line.color,
                                ),
                            ],
                            minimum,
                            maximum,
                            widget.markKeyPoints,
                            Theme.of(context).colorScheme,
                            minTime,
                            maxTime,
                            _position,
                            Theme.of(context).textTheme.labelSmall ??
                                const TextStyle(),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            Row(
              children: [
                Text(
                  date(minTime),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const Spacer(),
                Text(
                  date(maxTime),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
            if (time != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    for (final line in widget.lines.where(
                      (line) => line.points.any(widget.axes.includes),
                    ))
                      Builder(
                        builder: (_) {
                          final closest = line.points
                              .where(widget.axes.includes)
                              .reduce(
                                (a, b) =>
                                    (a.at.millisecondsSinceEpoch - time)
                                            .abs() <=
                                        (b.at.millisecondsSinceEpoch - time)
                                            .abs()
                                    ? a
                                    : b,
                              );
                          return Text(
                            '${line.label} ${closest.value.toStringAsFixed(2)} · ${date(closest.at.millisecondsSinceEpoch)}',
                            style: TextStyle(color: line.color, fontSize: 13),
                          );
                        },
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ComparisonPainter extends CustomPainter {
  _ComparisonPainter(
    this.lines,
    this.minimum,
    this.maximum,
    this.markKeyPoints,
    this.scheme,
    this.minTime,
    this.maxTime,
    this.position,
    this.labelStyle,
  );
  final List<ScoreComparisonLine> lines;
  final double? minimum, maximum;
  final bool markKeyPoints;
  final ColorScheme scheme;
  final int minTime, maxTime;
  final double? position;
  final TextStyle labelStyle;
  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTRB(40, 12, size.width - 12, size.height - 12);
    final values = lines
        .expand((line) => line.points.map((point) => point.value))
        .toList();
    if (values.isEmpty || plot.width <= 0) return;
    final minValue =
        minimum ??
        (values.reduce(math.min) - .3).floorToDouble().clamp(0.0, 9.0);
    final maxValue =
        maximum ??
        (values.reduce(math.max) + .3).ceilToDouble().clamp(minValue + 1, 10.0);
    final decimals = maxValue - minValue < .2
        ? 3
        : maxValue - minValue < 2
        ? 2
        : 1;
    double x(NetabaChartPoint point) =>
        plot.left +
        plot.width *
            (point.at.millisecondsSinceEpoch - minTime) /
            math.max(1, maxTime - minTime);
    double y(double value) =>
        plot.bottom - plot.height * (value - minValue) / (maxValue - minValue);
    for (var i = 0; i <= 4; i++) {
      final value = minValue + (maxValue - minValue) * i / 4;
      final at = y(value);
      canvas.drawLine(
        Offset(plot.left, at),
        Offset(plot.right, at),
        Paint()..color = scheme.outlineVariant.withValues(alpha: .5),
      );
      final text = TextPainter(
        text: TextSpan(
          text: value.toStringAsFixed(decimals),
          style: labelStyle.copyWith(
            fontSize: 11,
            color: scheme.onSurfaceVariant,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(canvas, Offset(2, at - text.height / 2));
    }
    if (position != null) {
      canvas.drawLine(
        Offset(plot.left + plot.width * position!, plot.top),
        Offset(plot.left + plot.width * position!, plot.bottom),
        Paint()
          ..color = scheme.outlineVariant
          ..strokeWidth = 1,
      );
    }
    canvas.save();
    canvas.clipRect(plot.inflate(4));
    for (final line in lines) {
      final ordered = [...line.points]..sort((a, b) => a.at.compareTo(b.at));
      if (ordered.isEmpty) continue;
      final path = Path()..moveTo(x(ordered.first), y(ordered.first.value));
      for (final point in ordered.skip(1)) {
        path.lineTo(x(point), y(point.value));
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = line.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..strokeJoin = StrokeJoin.round,
      );
      if (markKeyPoints) {
        final keys = {
          ordered.first,
          ordered.last,
          ordered.reduce((a, b) => a.value < b.value ? a : b),
          ordered.reduce((a, b) => a.value > b.value ? a : b),
        };
        for (final point in keys) {
          canvas.drawCircle(
            Offset(x(point), y(point.value)),
            5,
            Paint()..color = scheme.surface,
          );
          canvas.drawCircle(
            Offset(x(point), y(point.value)),
            3.5,
            Paint()..color = line.color,
          );
        }
      }
      canvas.drawCircle(
        Offset(x(ordered.last), y(ordered.last.value)),
        3,
        Paint()..color = line.color,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ComparisonPainter old) =>
      old.lines != lines ||
      old.position != position ||
      old.scheme != scheme ||
      old.minimum != minimum ||
      old.maximum != maximum ||
      old.minTime != minTime ||
      old.maxTime != maxTime ||
      old.markKeyPoints != markKeyPoints;
}

/// Actual samples, including dates, keep exported annotations auditable.
class ScoreChartKeyPoints extends StatelessWidget {
  const ScoreChartKeyPoints({
    super.key,
    required this.lines,
    this.axes = const ScoreChartAxes(),
  });
  final List<ScoreComparisonLine> lines;
  final ScoreChartAxes axes;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final line in lines.where((line) => line.points.any(axes.includes)))
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Builder(
            builder: (_) {
              final ordered = line.points.where(axes.includes).toList()
                ..sort((a, b) => a.at.compareTo(b.at));
              final low = ordered.reduce((a, b) => a.value <= b.value ? a : b);
              final high = ordered.reduce((a, b) => a.value >= b.value ? a : b);
              String mark(String name, NetabaChartPoint p) =>
                  '$name ${p.value.toStringAsFixed(2)} · ${scoreChartDate(p.at)}';
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '● ${line.label}',
                    style: TextStyle(
                      color: line.color,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 18,
                    runSpacing: 6,
                    children: [
                      Text(mark('起点', ordered.first)),
                      Text(mark('最新', ordered.last)),
                      Text(mark('最低', low)),
                      Text(mark('最高', high)),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
    ],
  );
}
