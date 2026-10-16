import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/theme/anime_icon.dart';
import '../models/netaba_models.dart';

class ScoreChartAxes {
  const ScoreChartAxes({this.minimum, this.maximum, this.start, this.end});
  final double? minimum, maximum;
  final DateTime? start, end;
  bool includes(NetabaChartPoint point) =>
      (start == null || !point.at.isBefore(start!)) &&
      (end == null ||
          point.at.isBefore(DateTime(end!.year, end!.month, end!.day + 1)));
}

String scoreChartDate(DateTime date) =>
    '${date.year}/${date.month}/${date.day}';

class ScoreChartControls extends StatelessWidget {
  const ScoreChartControls({
    super.key,
    required this.axes,
    required this.points,
    required this.onChanged,
  });
  final ScoreChartAxes axes;
  final List<NetabaChartPoint> points;
  final ValueChanged<ScoreChartAxes> onChanged;
  Future<void> _edit(BuildContext context) async {
    final result = await showDialog<ScoreChartAxes>(
      context: context,
      builder: (_) => _AxesDialog(axes: axes),
    );
    if (result != null) onChanged(result);
  }

  void _zoom(double factor) {
    final visible = points.where(axes.includes).map((p) => p.value).toList();
    if (visible.isEmpty) return;
    final low =
        axes.minimum ??
        (visible.reduce(math.min) - .3).floorToDouble().clamp(0, 9);
    final high =
        axes.maximum ??
        (visible.reduce(math.max) + .3).ceilToDouble().clamp(low + 1, 10);
    final center = (low + high) / 2;
    final half = ((high - low) * factor / 2).clamp(.025, 5.0);
    onChanged(
      ScoreChartAxes(
        minimum: (center - half).clamp(0, 9.95),
        maximum: (center + half).clamp(.05, 10),
        start: axes.start,
        end: axes.end,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      OutlinedButton.icon(
        onPressed: () => _edit(context),
        icon: const AnimeIcon(Icons.tune_rounded),
        label: const Text('坐标轴与日期'),
      ),
      IconButton(
        tooltip: '放大评分尺度',
        onPressed: points.isEmpty ? null : () => _zoom(.5),
        icon: const AnimeIcon(Icons.add_rounded),
      ),
      IconButton(
        tooltip: '缩小评分尺度',
        onPressed: points.isEmpty ? null : () => _zoom(2),
        icon: const AnimeIcon(Icons.remove_rounded),
      ),
      TextButton(
        onPressed: () => onChanged(const ScoreChartAxes()),
        child: const Text('自动尺度'),
      ),
      if (axes.minimum != null)
        Text(
          '评分 ${axes.minimum!.toStringAsFixed(2)}–${axes.maximum!.toStringAsFixed(2)}',
        ),
      if (axes.start != null)
        Text('${scoreChartDate(axes.start!)} – ${scoreChartDate(axes.end!)}'),
    ],
  );
}

class _AxesDialog extends StatefulWidget {
  const _AxesDialog({required this.axes});
  final ScoreChartAxes axes;
  @override
  State<_AxesDialog> createState() => _AxesDialogState();
}

class _AxesDialogState extends State<_AxesDialog> {
  final _form = GlobalKey<FormState>();
  late final _minimum = TextEditingController(
    text: widget.axes.minimum?.toStringAsFixed(2) ?? '',
  );
  late final _maximum = TextEditingController(
    text: widget.axes.maximum?.toStringAsFixed(2) ?? '',
  );
  late final _startDate = TextEditingController(
    text: widget.axes.start == null ? '' : scoreChartDate(widget.axes.start!),
  );
  late final _endDate = TextEditingController(
    text: widget.axes.end == null ? '' : scoreChartDate(widget.axes.end!),
  );
  @override
  void dispose() {
    _minimum.dispose();
    _maximum.dispose();
    _startDate.dispose();
    _endDate.dispose();
    super.dispose();
  }

  String? _validate(String? _) {
    if (_minimum.text.trim().isEmpty && _maximum.text.trim().isEmpty) {
      return null;
    }
    final low = double.tryParse(_minimum.text.trim()),
        high = double.tryParse(_maximum.text.trim());
    return low == null ||
            high == null ||
            !low.isFinite ||
            !high.isFinite ||
            low < 0 ||
            high > 10 ||
            high - low < .01
        ? '请输入 0–10，上限须大于下限至少 0.01'
        : null;
  }

  DateTime? _parseDate(String text) {
    final parts = RegExp(
      r'^(\d{4})[-/](\d{1,2})[-/](\d{1,2})$',
    ).firstMatch(text.trim());
    if (parts == null) return null;
    final year = int.parse(parts[1]!);
    final month = int.parse(parts[2]!);
    final day = int.parse(parts[3]!);
    final date = DateTime(year, month, day);
    return date.year == year && date.month == month && date.day == day
        ? date
        : null;
  }

  String? _validateDates(String? _) {
    if (_startDate.text.trim().isEmpty && _endDate.text.trim().isEmpty) {
      return null;
    }
    final start = _parseDate(_startDate.text), end = _parseDate(_endDate.text);
    if (start == null || end == null) return '请填写有效的起止日期，如 2026/10/16';
    if (start.isBefore(DateTime(1900)) ||
        end.isAfter(DateTime.now()) ||
        end.isBefore(start)) {
      return '日期须在 1900 年至今天之间，结束日期不得早于开始日期';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('坐标轴与日期'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('评分上下限留空时自动适配'),
              const SizedBox(height: 16),
              TextFormField(
                controller: _minimum,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: '评分下限'),
                validator: _validate,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _maximum,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: '评分上限'),
                validator: _validate,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _startDate,
                keyboardType: TextInputType.datetime,
                decoration: const InputDecoration(
                  labelText: '开始日期',
                  hintText: 'YYYY/MM/DD，留空时显示全部日期',
                ),
                validator: _validateDates,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _endDate,
                keyboardType: TextInputType.datetime,
                decoration: const InputDecoration(
                  labelText: '结束日期',
                  hintText: 'YYYY/MM/DD',
                ),
                validator: _validateDates,
              ),
              TextButton(
                onPressed: () {
                  _startDate.clear();
                  _endDate.clear();
                },
                child: const Text('全部日期'),
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          if (_form.currentState!.validate()) {
            Navigator.pop(
              context,
              ScoreChartAxes(
                minimum: double.tryParse(_minimum.text.trim()),
                maximum: double.tryParse(_maximum.text.trim()),
                start: _parseDate(_startDate.text),
                end: _parseDate(_endDate.text),
              ),
            );
          }
        },
        child: const Text('应用'),
      ),
    ],
  );
}
