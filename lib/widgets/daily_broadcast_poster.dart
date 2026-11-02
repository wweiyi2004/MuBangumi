import 'package:flutter/material.dart';
import '../models/bangumi_models.dart';
import 'subject_widgets.dart';

class DailyBroadcastPoster extends StatelessWidget {
  const DailyBroadcastPoster({super.key, required this.subjects});
  final List<Subject> subjects;
  @override
  Widget build(BuildContext context) => MediaQuery.withNoTextScaling(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < subjects.length; i += 2)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _BroadcastSubject(subject: subjects[i], number: i + 1),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: i + 1 < subjects.length
                      ? _BroadcastSubject(
                          subject: subjects[i + 1],
                          number: i + 2,
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

class _BroadcastSubject extends StatelessWidget {
  const _BroadcastSubject({required this.subject, required this.number});
  final Subject subject;
  final int number;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 112,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .5)),
      ),
      child: Row(
        children: [
          SubjectCover(
            subject: subject,
            width: 60,
            height: 84,
            borderRadius: 8,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${number.toString().padLeft(2, '0')}  ${subject.type.label}',
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: scheme.primary),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: Text(
                    subject.displayName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  subject.score > 0
                      ? '★ ${subject.score.toStringAsFixed(1)}${subject.rank > 0 ? '  ·  #${subject.rank}' : ''}'
                      : '暂无评分',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
