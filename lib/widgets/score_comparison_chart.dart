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
  const ScoreComparisonChart({super.key, required this.lines});
  final List<ScoreComparisonLine> lines;
  @override
  State<ScoreComparisonChart> createState() => _ScoreComparisonChartState();
}

class _ScoreComparisonChartState extends State<ScoreComparisonChart> {
  double? _position;
  @override
  Widget build(BuildContext context) {
    final points = widget.lines.expand((line) => line.points).toList();
    if (points.isEmpty) {
      return const SizedBox(
        height: 260,
        child: Center(child: Text('选择作品后显示历史折线；暂无数据的作品会单独说明')),
      );
    }
    final minTime = points
        .map((point) => point.at.millisecondsSinceEpoch)
        .reduce(math.min);
    final maxTime = points
        .map((point) => point.at.millisecondsSinceEpoch)
        .reduce(math.max);
    String date(int time) {
      final at = DateTime.fromMillisecondsSinceEpoch(time);
      return '${at.year}/${at.month}/${at.day}';
    }

    final time = _position == null
        ? null
        : (minTime + (maxTime - minTime) * _position!).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            void inspect(double x) => setState(
              () => _position = ((x - 40) / (constraints.maxWidth - 52)).clamp(
                0.0,
                1.0,
              ),
            );
            return Semantics(
              label: '作品评分历史对比，同一日期轴、同一评分轴。点击图表查看附近的实际记录。',
              child: MouseRegion(
                onHover: (event) => inspect(event.localPosition.dx),
                child: GestureDetector(
                  onTapDown: (event) => inspect(event.localPosition.dx),
                  child: SizedBox(
                    height: 260,
                    child: CustomPaint(
                      key: const ValueKey('score-comparison-plot'),
                      painter: _ComparisonPainter(
                        widget.lines,
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
            Text(date(minTime), style: Theme.of(context).textTheme.labelSmall),
            const Spacer(),
            Text(date(maxTime), style: Theme.of(context).textTheme.labelSmall),
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
                  (line) => line.points.isNotEmpty,
                ))
                  Builder(
                    builder: (_) {
                      final closest = line.points.reduce(
                        (a, b) =>
                            (a.at.millisecondsSinceEpoch - time).abs() <=
                                (b.at.millisecondsSinceEpoch - time).abs()
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
  }
}

class _ComparisonPainter extends CustomPainter {
  _ComparisonPainter(
    this.lines,
    this.scheme,
    this.minTime,
    this.maxTime,
    this.position,
    this.labelStyle,
  );
  final List<ScoreComparisonLine> lines;
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
    final minValue = (values.reduce(math.min) - .3).floorToDouble().clamp(
      0.0,
      9.0,
    );
    final maxValue = (values.reduce(math.max) + .3).ceilToDouble().clamp(
      minValue + 1,
      10.0,
    );
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
          text: value.toStringAsFixed(1),
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
      canvas.drawCircle(
        Offset(x(ordered.last), y(ordered.last.value)),
        3,
        Paint()..color = line.color,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ComparisonPainter old) =>
      old.lines != lines || old.position != position || old.scheme != scheme;
}
