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
        icon: const AnimeIcon(Icons.zoom_in_rounded),
      ),
      IconButton(
        tooltip: '缩小评分尺度',
        onPressed: points.isEmpty ? null : () => _zoom(2),
        icon: const AnimeIcon(Icons.zoom_out_rounded),
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
  late DateTime? _start = widget.axes.start, _end = widget.axes.end;
  @override
  void dispose() {
    _minimum.dispose();
    _maximum.dispose();
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
              OutlinedButton.icon(
                onPressed: () async {
                  final range = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(1900),
                    lastDate: DateTime.now(),
                    initialDateRange: _start == null
                        ? null
                        : DateTimeRange(start: _start!, end: _end!),
                  );
                  if (mounted && range != null) {
                    setState(() {
                      _start = range.start;
                      _end = range.end;
                    });
                  }
                },
                icon: const AnimeIcon(Icons.date_range_rounded),
                label: Text(
                  _start == null
                      ? '选择日期范围'
                      : '${scoreChartDate(_start!)} – ${scoreChartDate(_end!)}',
                ),
              ),
              if (_start != null)
                TextButton(
                  onPressed: () => setState(() {
                    _start = null;
                    _end = null;
                  }),
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
                start: _start,
                end: _end,
              ),
            );
          }
        },
        child: const Text('应用'),
      ),
    ],
  );
}
