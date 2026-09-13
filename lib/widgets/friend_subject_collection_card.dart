import 'package:flutter/material.dart';

import '../models/bangumi_models.dart';
import 'community_widgets.dart';

/// Keeps a friend's identity, collection and comment in one readable entry.
class FriendSubjectCollectionCard extends StatefulWidget {
  const FriendSubjectCollectionCard({
    super.key,
    required this.status,
    required this.subjectType,
    required this.onOpenUser,
  });

  final FriendSubjectStatus status;
  final SubjectType subjectType;
  final VoidCallback onOpenUser;

  @override
  State<FriendSubjectCollectionCard> createState() =>
      _FriendSubjectCollectionCardState();
}

class _FriendSubjectCollectionCardState
    extends State<FriendSubjectCollectionCard> {
  bool _expanded = false;

  @override
  void didUpdateWidget(covariant FriendSubjectCollectionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status.user.id != widget.status.user.id ||
        oldWidget.status.comment != widget.status.comment) {
      _expanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.status;
    final theme = Theme.of(context);
    final comment = status.comment.trim();
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: widget.onOpenUser,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    CommunityAvatar(
                      imageUrl: status.user.avatarUrl,
                      radius: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            status.user.displayName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 12,
                            runSpacing: 4,
                            children: [
                              Text(
                                status.type.labelFor(widget.subjectType),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              if (status.rate > 0)
                                Text(
                                  '${status.rate} / 10 分',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (comment.isEmpty)
              Text(
                '暂未写评论',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final style = theme.textTheme.bodyMedium!;
                  final painter = TextPainter(
                    text: TextSpan(text: comment, style: style),
                    textDirection: Directionality.of(context),
                    textScaler: MediaQuery.textScalerOf(context),
                    locale: Localizations.maybeLocaleOf(context),
                    maxLines: 4,
                    ellipsis: '…',
                  )..layout(maxWidth: constraints.maxWidth);
                  final overflows = painter.didExceedMaxLines;
                  painter.dispose();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectionArea(
                        child: Text(
                          comment,
                          style: style,
                          maxLines: _expanded ? null : 4,
                          overflow: _expanded
                              ? TextOverflow.visible
                              : TextOverflow.ellipsis,
                        ),
                      ),
                      if (overflows)
                        TextButton(
                          onPressed: () =>
                              setState(() => _expanded = !_expanded),
                          child: Text(_expanded ? '收起评论' : '展开评论'),
                        ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
