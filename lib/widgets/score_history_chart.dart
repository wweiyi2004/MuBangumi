import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/netaba_models.dart';

/// Compact sparkline used in trending lists.
class ScoreSparkline extends StatelessWidget {
  const ScoreSparkline({
    super.key,
    required this.points,
    this.color = const Color(0xFFF3A646),
    this.height = 36,
    this.width = 88,
  });

  final List<NetabaChartPoint> points;
  final Color color;
  final double height;
  final double width;

  @override
  Widget build(BuildContext context) {
    if (points.length < 2) {
      return SizedBox(width: width, height: height);
    }
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _LineChartPainter(
          points: points,
          lineColor: color,
          fillColor: color.withValues(alpha: 0.18),
          showDots: false,
          showGrid: false,
          showLabels: false,
          strokeWidth: 1.8,
          reverseY: false,
        ),
      ),
    );
  }
}

/// Interactive-ish history chart for score / rank / collection series.
class ScoreHistoryChart extends StatelessWidget {
  const ScoreHistoryChart({
    super.key,
    required this.points,
    required this.lineColor,
    this.height = 180,
    this.reverseY = false,
    this.valueLabel,
    this.emptyLabel = '暂无数据',
  });

  final List<NetabaChartPoint> points;
  final Color lineColor;
  final double height;
  final bool reverseY;
  final String Function(double value)? valueLabel;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (points.length < 2) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            emptyLabel,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ),
      );
    }

    final first = points.first;
    final last = points.last;
    final minV = points.map((p) => p.value).reduce(math.min);
    final maxV = points.map((p) => p.value).reduce(math.max);
    final label = valueLabel ?? (v) => v.toStringAsFixed(v >= 100 ? 0 : 2);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: height,
          child: CustomPaint(
            painter: _LineChartPainter(
              points: points,
              lineColor: lineColor,
              fillColor: lineColor.withValues(alpha: 0.14),
              gridColor: scheme.outlineVariant.withValues(alpha: 0.55),
              labelColor: scheme.onSurfaceVariant,
              showDots: false,
              showGrid: true,
              showLabels: true,
              reverseY: reverseY,
              valueLabel: label,
              strokeWidth: 2.2,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              _formatDate(first.at),
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const Spacer(),
            Text(
              '${label(minV)} – ${label(maxV)}',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const Spacer(),
            Text(
              _formatDate(last.at),
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ],
    );
  }
}

class ScoreHistoryPanel extends StatefulWidget {
  const ScoreHistoryPanel({
    super.key,
    required this.loading,
    required this.error,
    required this.history,
    required this.onRetry,
    this.subjectId,
    this.compact = false,
    this.initiallyExpanded = true,
  });

  final bool loading;
  final String? error;
  final NetabaSubjectHistory? history;
  final VoidCallback onRetry;
  final int? subjectId;
  final bool compact;
  final bool initiallyExpanded;

  @override
  State<ScoreHistoryPanel> createState() => _ScoreHistoryPanelState();
}

class _ScoreHistoryPanelState extends State<ScoreHistoryPanel> {
  NetabaHistoryMetric _metric = NetabaHistoryMetric.score;
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final history = widget.history;
    final delta = history?.delta(days: 30);
    final compact = widget.compact;
    final hasBody =
        widget.error != null ||
        (widget.loading && history == null) ||
        (history != null && history.history.isNotEmpty) ||
        (!widget.loading && (history == null || history.history.isEmpty));

    return Card(
      child: Padding(
        padding: EdgeInsets.all(compact ? 12 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: compact && hasBody
                  ? () => setState(() => _expanded = !_expanded)
                  : null,
              borderRadius: BorderRadius.circular(8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '历史评分',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (widget.loading)
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else if (!compact)
                    TextButton.icon(
                      onPressed: widget.subjectId == null
                          ? null
                          : () => _openNetaba(widget.subjectId!),
                      icon: const Icon(Icons.open_in_new_rounded, size: 16),
                      label: const Text('netaba.re'),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                    ),
                  if (compact && hasBody)
                    Icon(
                      _expanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: scheme.onSurfaceVariant,
                    ),
                ],
              ),
            ),
            if (!compact)
              Text(
                '数据来源：netaba.re',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              )
            else if (!_expanded && delta != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '近 ${delta.days} 天评分 '
                  '${delta.score >= 0 ? '+' : ''}${delta.score.toStringAsFixed(2)}'
                  '${delta.rank != 0 ? ' · ${_rankDeltaText(delta.rank)}' : ''}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (!compact || _expanded) ...[
              if (widget.error != null) ...[
                const SizedBox(height: 14),
                Text(widget.error!, style: TextStyle(color: scheme.error)),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: widget.onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('重试'),
                ),
              ] else if (widget.loading && history == null) ...[
                const SizedBox(height: 24),
                const Center(child: CircularProgressIndicator()),
                const SizedBox(height: 8),
              ] else if (history == null || history.history.isEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  '暂无历史记录',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ] else ...[
                if (delta != null) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _DeltaChip(
                        label: '评分',
                        value: delta.score,
                        betterWhenPositive: true,
                        precision: 2,
                        suffix: compact ? '' : ' · ${delta.days} 天',
                      ),
                      if (delta.rank != 0)
                        _DeltaChip(
                          label: '排名',
                          value: -delta.rank.toDouble(),
                          betterWhenPositive: true,
                          precision: 0,
                          displayOverride: _rankDeltaText(delta.rank),
                        ),
                      if (delta.watching != 0)
                        _DeltaChip(
                          label: '在看',
                          value: delta.watching.toDouble(),
                          betterWhenPositive: true,
                          precision: 0,
                        ),
                      if (delta.rated != 0)
                        _DeltaChip(
                          label: '打分',
                          value: delta.rated.toDouble(),
                          betterWhenPositive: true,
                          precision: 0,
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final metric in NetabaHistoryMetric.values) ...[
                        ChoiceChip(
                          label: Text(_metricLabel(metric)),
                          selected: _metric == metric,
                          visualDensity: compact
                              ? VisualDensity.compact
                              : VisualDensity.standard,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          onSelected: (_) => setState(() => _metric = metric),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _MetricSummary(
                  history: history,
                  metric: _metric,
                  compact: compact,
                ),
                const SizedBox(height: 10),
                ScoreHistoryChart(
                  points: history.seriesFor(_metric),
                  lineColor: _metricColor(_metric),
                  height: compact ? 148 : 180,
                  reverseY: _metric == NetabaHistoryMetric.rank,
                  valueLabel: _metric == NetabaHistoryMetric.score
                      ? (v) => v.toStringAsFixed(2)
                      : (v) => v >= 1000
                            ? '${(v / 1000).toStringAsFixed(1)}k'
                            : v.toStringAsFixed(0),
                  emptyLabel: '该维度暂无足够历史点',
                ),
                if (compact && widget.subjectId != null)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => _openNetaba(widget.subjectId!),
                      icon: const Icon(Icons.open_in_new_rounded, size: 16),
                      label: const Text('在 netaba.re 查看'),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openNetaba(int subjectId) async {
    final uri = Uri.parse('https://netaba.re/subject/$subjectId');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class _MetricSummary extends StatelessWidget {
  const _MetricSummary({
    required this.history,
    required this.metric,
    this.compact = false,
  });

  final NetabaSubjectHistory history;
  final NetabaHistoryMetric metric;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final points = history.seriesFor(metric, maxPoints: 10000);
    if (points.isEmpty) return const SizedBox.shrink();
    final latest = points.last.value;
    final first = points.first.value;
    final change = latest - first;
    final scheme = Theme.of(context).colorScheme;

    String currentText;
    String changeText;
    switch (metric) {
      case NetabaHistoryMetric.score:
        currentText = latest.toStringAsFixed(2);
        changeText = '${change >= 0 ? '+' : ''}${change.toStringAsFixed(2)} 全期';
      case NetabaHistoryMetric.rank:
        currentText = '#${latest.round()}';
        // rank down is better
        final rankDelta = latest.round() - first.round();
        changeText = rankDelta == 0
            ? '全期持平'
            : rankDelta < 0
            ? '↑ 上升 ${-rankDelta}'
            : '↓ 下降 $rankDelta';
      case NetabaHistoryMetric.watching:
      case NetabaHistoryMetric.collect:
      case NetabaHistoryMetric.rated:
        currentText = latest.round().toString();
        changeText = '${change >= 0 ? '+' : ''}${change.round()} 全期';
    }

    return Row(
      children: [
        Text(
          currentText,
          style:
              (compact
                      ? Theme.of(context).textTheme.headlineSmall
                      : Theme.of(context).textTheme.headlineMedium)
                  ?.copyWith(
                    color: _metricColor(metric),
                    fontWeight: FontWeight.w800,
                  ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            changeText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: compact ? 12.5 : null,
            ),
          ),
        ),
        if (!compact)
          Text(
            '${points.length} 个采样点',
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
      ],
    );
  }
}

class _DeltaChip extends StatelessWidget {
  const _DeltaChip({
    required this.label,
    required this.value,
    required this.betterWhenPositive,
    required this.precision,
    this.suffix = '',
    this.displayOverride,
  });

  final String label;
  final double value;
  final bool betterWhenPositive;
  final int precision;
  final String suffix;
  final String? displayOverride;

  @override
  Widget build(BuildContext context) {
    final positive = value > 0;
    final neutral = value == 0;
    final good = betterWhenPositive ? positive : !positive;
    final color = neutral
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : good
        ? const Color(0xFF2E9E6B)
        : const Color(0xFFE05A5A);
    final text =
        displayOverride ??
        '$label ${value > 0 ? '+' : ''}${value.toStringAsFixed(precision)}$suffix';
    return Chip(
      avatar: Icon(
        neutral
            ? Icons.remove_rounded
            : positive
            ? Icons.trending_up_rounded
            : Icons.trending_down_rounded,
        size: 16,
        color: color,
      ),
      label: Text(text, style: TextStyle(color: color)),
      visualDensity: VisualDensity.compact,
      side: BorderSide(color: color.withValues(alpha: 0.35)),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  _LineChartPainter({
    required this.points,
    required this.lineColor,
    required this.fillColor,
    this.gridColor,
    this.labelColor,
    this.showDots = false,
    this.showGrid = true,
    this.showLabels = true,
    this.reverseY = false,
    this.strokeWidth = 2,
    this.valueLabel,
  });

  final List<NetabaChartPoint> points;
  final Color lineColor;
  final Color fillColor;
  final Color? gridColor;
  final Color? labelColor;
  final bool showDots;
  final bool showGrid;
  final bool showLabels;
  final bool reverseY;
  final double strokeWidth;
  final String Function(double value)? valueLabel;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    final leftPad = showLabels ? 36.0 : 2.0;
    final rightPad = 6.0;
    final topPad = 8.0;
    final bottomPad = showLabels ? 6.0 : 2.0;
    final chart = Rect.fromLTRB(
      leftPad,
      topPad,
      size.width - rightPad,
      size.height - bottomPad,
    );
    if (chart.width <= 0 || chart.height <= 0) return;

    var minV = points.map((p) => p.value).reduce(math.min);
    var maxV = points.map((p) => p.value).reduce(math.max);
    if ((maxV - minV).abs() < 1e-6) {
      minV -= 0.5;
      maxV += 0.5;
    }
    // padding so line isn't glued to edges
    final pad = (maxV - minV) * 0.08;
    minV -= pad;
    maxV += pad;

    final minT = points.first.at.millisecondsSinceEpoch.toDouble();
    final maxT = points.last.at.millisecondsSinceEpoch.toDouble();
    final tSpan = (maxT - minT).abs() < 1 ? 1.0 : (maxT - minT);

    Offset mapPoint(NetabaChartPoint p) {
      final x =
          chart.left +
          (p.at.millisecondsSinceEpoch - minT) / tSpan * chart.width;
      final norm = (p.value - minV) / (maxV - minV);
      final y = reverseY
          ? chart.top + norm * chart.height
          : chart.bottom - norm * chart.height;
      return Offset(x, y);
    }

    if (showGrid && gridColor != null) {
      final gridPaint = Paint()
        ..color = gridColor!
        ..strokeWidth = 1;
      for (var i = 0; i <= 3; i++) {
        final y = chart.top + chart.height * i / 3;
        canvas.drawLine(
          Offset(chart.left, y),
          Offset(chart.right, y),
          gridPaint,
        );
      }
    }

    if (showLabels && labelColor != null) {
      final labels = reverseY
          ? [maxV, (maxV + minV) / 2, minV]
          : [maxV, (maxV + minV) / 2, minV];
      final tp = TextPainter(textDirection: TextDirection.ltr);
      for (var i = 0; i < labels.length; i++) {
        final value = labels[i];
        final text = valueLabel?.call(value) ?? value.toStringAsFixed(1);
        tp.text = TextSpan(
          text: text,
          style: TextStyle(color: labelColor, fontSize: 10),
        );
        tp.layout(maxWidth: leftPad - 4);
        final y =
            chart.top + chart.height * i / (labels.length - 1) - tp.height / 2;
        tp.paint(canvas, Offset(0, y.clamp(0, size.height - tp.height)));
      }
    }

    final path = Path();
    final fill = Path();
    for (var i = 0; i < points.length; i++) {
      final o = mapPoint(points[i]);
      if (i == 0) {
        path.moveTo(o.dx, o.dy);
        fill.moveTo(o.dx, chart.bottom);
        fill.lineTo(o.dx, o.dy);
      } else {
        path.lineTo(o.dx, o.dy);
        fill.lineTo(o.dx, o.dy);
      }
    }
    fill.lineTo(mapPoint(points.last).dx, chart.bottom);
    fill.close();

    canvas.drawPath(
      fill,
      Paint()
        ..style = PaintingStyle.fill
        ..color = fillColor,
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = lineColor,
    );

    if (showDots) {
      final dot = Paint()..color = lineColor;
      for (final p in points) {
        canvas.drawCircle(mapPoint(p), 2.2, dot);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.reverseY != reverseY ||
        oldDelegate.showLabels != showLabels;
  }
}

String _metricLabel(NetabaHistoryMetric metric) => switch (metric) {
  NetabaHistoryMetric.score => '评分',
  NetabaHistoryMetric.rank => '排名',
  NetabaHistoryMetric.watching => '在看',
  NetabaHistoryMetric.collect => '看过',
  NetabaHistoryMetric.rated => '打分人数',
};

Color _metricColor(NetabaHistoryMetric metric) => switch (metric) {
  NetabaHistoryMetric.score => const Color(0xFFF3A646),
  NetabaHistoryMetric.rank => const Color(0xFF5B8DEF),
  NetabaHistoryMetric.watching => const Color(0xFF2E9E6B),
  NetabaHistoryMetric.collect => const Color(0xFF8B6CEF),
  NetabaHistoryMetric.rated => const Color(0xFFE95383),
};

String _rankDeltaText(int rankDelta) {
  // rankDelta > 0 means rank number increased (got worse)
  if (rankDelta == 0) return '排名 持平';
  if (rankDelta < 0) return '排名 ↑${-rankDelta}';
  return '排名 ↓$rankDelta';
}

String _formatDate(DateTime date) {
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '${date.year}-$m-$d';
}
