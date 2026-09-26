import 'package:flutter/material.dart';
import '../core/theme/app_tokens.dart';

class ProfileCollectionSummary extends StatelessWidget {
  const ProfileCollectionSummary({
    super.key,
    required this.doing,
    required this.done,
    required this.total,
    this.onDoingTap,
    this.onDoneTap,
    this.onTotalTap,
  });

  final int doing;
  final int done;
  final int total;
  final VoidCallback? onDoingTap;
  final VoidCallback? onDoneTap;
  final VoidCallback? onTotalTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: AppRadius.large,
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SummaryAction(
            onTap: onTotalTap,
            label: '总收藏：$total 项，查看全部收藏',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '总收藏',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                    const Spacer(),
                    Icon(
                      onTotalTap == null
                          ? Icons.auto_stories_rounded
                          : Icons.arrow_forward_rounded,
                      color: scheme.primary,
                      size: 24,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                _Number(total, size: 52, color: scheme.onSurface),
              ],
            ),
          ),
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
                    onTap: onDoingTap,
                  ),
                  _Metric(
                    width: width,
                    value: done,
                    label: '已完成',
                    color: scheme.tertiary,
                    onTap: onDoneTap,
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
    this.onTap,
  });
  final double width;
  final int value;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: _SummaryAction(
      onTap: onTap,
      label: '$label：$value 项，查看收藏',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Number(value, size: 36, color: color),
          const SizedBox(height: 5),
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (onTap != null)
                Icon(Icons.chevron_right_rounded, size: 18, color: color),
            ],
          ),
        ],
      ),
    ),
  );
}

class _SummaryAction extends StatelessWidget {
  const _SummaryAction({required this.label, required this.child, this.onTap});
  final String label;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (onTap == null) return child;
    return Semantics(
      button: true,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: AppRadius.medium,
            child: child,
          ),
        ),
      ),
    );
  }
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
