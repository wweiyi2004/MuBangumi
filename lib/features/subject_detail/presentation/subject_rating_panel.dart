import 'package:flutter/material.dart';
import '../../../models/bangumi_models.dart';

class SubjectRatingPanel extends StatelessWidget {
  const SubjectRatingPanel({super.key, required this.subject});

  final Subject subject;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final narrow = MediaQuery.sizeOf(context).width < 600;
    final maxCount = subject.ratingCount.values.fold<int>(
      0,
      (max, value) => value > max ? value : max,
    );
    return Container(
      decoration: BoxDecoration(
        border: Border.symmetric(
          horizontal: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: narrow ? 12 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '评分详情',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Flexible(
                  child: Text(
                    '争议度 ${subject.controversyLabel}',
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: narrow ? 12.5 : null,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 14,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (subject.score > 0)
                  Text(
                    subject.score.toStringAsFixed(2),
                    style:
                        (narrow
                                ? Theme.of(context).textTheme.headlineSmall
                                : Theme.of(context).textTheme.headlineMedium)
                            ?.copyWith(
                              color: const Color(0xFFF3A646),
                              fontWeight: FontWeight.w700,
                            ),
                  ),
                if (subject.ratingTotal > 0) Text('${subject.ratingTotal} 人评分'),
                if (subject.ratingStdDev > 0)
                  Text('σ ${subject.ratingStdDev.toStringAsFixed(2)}'),
                if (subject.rank > 0) Text('排名 #${subject.rank}'),
              ],
            ),
            if (maxCount > 0) ...[
              const SizedBox(height: 14),
              for (var score = 10; score >= 1; score--)
                Padding(
                  padding: EdgeInsets.only(bottom: narrow ? 4 : 5),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 20,
                        child: Text(
                          '$score',
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: (subject.ratingCount[score] ?? 0) / maxCount,
                            minHeight: narrow ? 7 : 8,
                            backgroundColor: scheme.surfaceContainerHighest,
                            color: const Color(0xFFF3A646),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: narrow ? 36 : 42,
                        child: Text(
                          '${subject.ratingCount[score] ?? 0}',
                          textAlign: TextAlign.end,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            if (subject.collectionTotal > 0 ||
                subject.wishCount + subject.collectCount + subject.doingCount >
                    0) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (subject.wishCount > 0)
                    Chip(
                      label: Text(
                        '${CollectionType.wish.labelFor(subject.type)} ${subject.wishCount}',
                      ),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  if (subject.doingCount > 0)
                    Chip(
                      label: Text(
                        '${CollectionType.doing.labelFor(subject.type)} ${subject.doingCount}',
                      ),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  if (subject.collectCount > 0)
                    Chip(
                      label: Text(
                        '${CollectionType.done.labelFor(subject.type)} ${subject.collectCount}',
                      ),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  if (subject.onHoldCount > 0)
                    Chip(
                      label: Text('搁置 ${subject.onHoldCount}'),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  if (subject.droppedCount > 0)
                    Chip(
                      label: Text('抛弃 ${subject.droppedCount}'),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
