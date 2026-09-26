import 'package:flutter/material.dart';
import '../../core/theme/app_tokens.dart';

/// Round state as a small pill: green while scoring, amber when paused and
/// grey otherwise. Pink stays reserved for actions and selection.
class RoomStatusChip extends StatelessWidget {
  const RoomStatusChip({super.key, required this.status, this.ended = false});
  final Object? status;
  final bool ended;

  static String label(Object? status, {bool ended = false}) => ended
      ? '活动已结束'
      : switch (status) {
          'open' => '评分进行中',
          'paused' => '已暂停',
          'closed' => '已截止',
          _ => '等待开始',
        };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tone = ended
        ? scheme.onSurfaceVariant
        : switch (status) {
            'open' => AppPalette.live,
            'paused' => scheme.tertiary,
            _ => scheme.onSurfaceVariant,
          };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tone.withValues(alpha: .12),
        borderRadius: AppRadius.round,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.circle, size: 7, color: tone),
            const SizedBox(width: 6),
            Text(
              label(status, ended: ended),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: scheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
