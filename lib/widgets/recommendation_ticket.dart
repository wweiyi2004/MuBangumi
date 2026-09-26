import 'package:flutter/material.dart';
import '../core/recommend/fan_recommend_engine.dart';
import 'readable_subject_title.dart';
import 'subject_widgets.dart';

/// A compact recommendation ticket: information in the main portion, the
/// numbered stub below. The perforation is decorative, never a gesture target.
class RecommendationTicket extends StatelessWidget {
  const RecommendationTicket({
    super.key,
    required this.item,
    required this.index,
    required this.onTap,
    this.onHide,
    this.onWish,
    this.compact = false,
  });
  final FanRecommendItem item;
  final int index;
  final VoidCallback onTap;
  final VoidCallback? onHide;
  final VoidCallback? onWish;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final subject = item.subject;
    final radius = BorderRadius.circular(16);
    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SubjectCover(
                    subject: subject,
                    width: compact ? 56 : 60,
                    height: compact ? 78 : 84,
                    borderRadius: 8,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: ReadableSubjectTitle(
                                subject.displayName,
                                maxLines: 2,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Semantics(
                              label: '推荐顺序 $index',
                              child: ExcludeSemantics(
                                child: Text(
                                  index.toString().padLeft(2, '0'),
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(color: colors.outline),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          [
                            if (subject.score > 0)
                              '★ ${subject.score.toStringAsFixed(1)}',
                            if (subject.rank > 0) '#${subject.rank}',
                            if (subject.date.isNotEmpty) subject.date,
                          ].join(' · '),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          item.reasons.take(2).join(' / '),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: colors.onSurfaceVariant,
                                height: 1.35,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
            height: 4,
            child: CustomPaint(painter: _TicketPerforation(colors)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 6, 2),
            child: Wrap(
              spacing: 2,
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton(onPressed: onHide, child: const Text('不感兴趣')),
                FilledButton.tonalIcon(
                  onPressed: onWish,
                  icon: const Icon(Icons.bookmark_add_outlined, size: 17),
                  label: const Text('加入想看'),
                ),
                IconButton(
                  tooltip: '查看作品',
                  onPressed: onTap,
                  icon: const Icon(Icons.arrow_forward_rounded, size: 19),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TicketPerforation extends CustomPainter {
  _TicketPerforation(this.colors);
  final ColorScheme colors;
  @override
  void paint(Canvas canvas, Size size) {
    final ink = Paint()
      ..color = colors.outlineVariant
      ..strokeWidth = 1;
    for (double x = 14; x < size.width - 14; x += 9) {
      canvas.drawLine(
        Offset(x, 2),
        Offset((x + 4).clamp(0, size.width - 14), 2),
        ink,
      );
    }
    final fill = Paint()..color = colors.surfaceContainerLow;
    for (final x in [0.0, size.width]) {
      canvas.drawCircle(Offset(x, 2), 2.5, fill);
      canvas.drawCircle(Offset(x, 2), 2.5, ink..style = PaintingStyle.stroke);
    }
  }

  @override
  bool shouldRepaint(_TicketPerforation old) => old.colors != colors;
}
