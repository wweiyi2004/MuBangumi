import 'package:flutter/material.dart';

class ProfileCollectionSummary extends StatelessWidget {
  const ProfileCollectionSummary({
    super.key,
    required this.doing,
    required this.done,
    required this.total,
  });

  final int doing;
  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('总收藏', style: TextStyle(color: scheme.onSurfaceVariant)),
              const Spacer(),
              Icon(Icons.auto_stories_rounded, color: scheme.primary, size: 24),
            ],
          ),
          const SizedBox(height: 6),
          _Number(total, size: 52, color: scheme.onSurface),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Divider(
              height: 1,
              color: scheme.outlineVariant.withValues(alpha: .6),
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final scaler = MediaQuery.textScalerOf(context);
              final digits = doing.toString().length > done.toString().length
                  ? doing.toString().length
                  : done.toString().length;
              final minimum = scaler.scale(36) * digits * .65 + 16;
              final stacked =
                  constraints.maxWidth < minimum * 2 + 24 ||
                  constraints.maxWidth < scaler.scale(96) * 2 + 24;
              final width = stacked
                  ? constraints.maxWidth
                  : (constraints.maxWidth - 24) / 2;
              return Wrap(
                spacing: 24,
                runSpacing: 20,
                children: [
                  _Metric(
                    width: width,
                    value: doing,
                    label: '进行中',
                    color: scheme.primary,
                  ),
                  _Metric(
                    width: width,
                    value: done,
                    label: '已完成',
                    color: scheme.tertiary,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.width,
    required this.value,
    required this.label,
    required this.color,
  });
  final double width;
  final int value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Number(value, size: 36, color: color),
        const SizedBox(height: 5),
        Text(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
}

class _Number extends StatelessWidget {
  const _Number(this.value, {required this.size, required this.color});
  final int value;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    alignment: Alignment.centerLeft,
    child: Text(
      '$value',
      maxLines: 1,
      style: TextStyle(
        fontSize: size,
        height: 1.08,
        fontWeight: FontWeight.w800,
        letterSpacing: -1,
        fontFeatures: const [FontFeature.tabularFigures()],
        color: color,
      ),
    ),
  );
}
