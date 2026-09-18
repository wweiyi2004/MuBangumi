import 'package:flutter/material.dart';
import '../../../models/bangumi_models.dart';
import '../../../widgets/friend_subject_collection_card.dart';

class SubjectFriendsPanel extends StatelessWidget {
  const SubjectFriendsPanel({
    super.key,
    required this.loading,
    required this.expanded,
    required this.loaded,
    required this.statuses,
    required this.subjectType,
    required this.onExpand,
    required this.onCollapse,
    required this.onOpenUser,
    this.error,
  });

  final bool loading;
  final bool expanded;
  final bool loaded;
  final List<FriendSubjectStatus> statuses;
  final SubjectType subjectType;
  final VoidCallback onExpand;
  final VoidCallback onCollapse;
  final ValueChanged<BangumiUser> onOpenUser;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.symmetric(
          horizontal: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '好友收藏与评论',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(width: 8),
                if (loading)
                  const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (!expanded)
                  TextButton.icon(
                    onPressed: onExpand,
                    icon: const Icon(Icons.people_outline_rounded, size: 18),
                    label: const Text('查看好友'),
                  )
                else if (error != null)
                  TextButton.icon(
                    onPressed: onExpand,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('重试'),
                  )
                else
                  Text(
                    statuses.isEmpty ? '暂无好友收藏' : '${statuses.length} 位好友',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                if (expanded && !loading)
                  IconButton(
                    tooltip: '收起好友收藏与评论',
                    onPressed: onCollapse,
                    icon: const Icon(Icons.expand_less_rounded),
                  ),
              ],
            ),
            if (expanded && error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (expanded && loaded && statuses.isNotEmpty) ...[
              const SizedBox(height: 12),
              Column(
                children: [
                  for (final status in statuses.take(12))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: FriendSubjectCollectionCard(
                        key: ValueKey(status.user.id),
                        status: status,
                        subjectType: subjectType,
                        onOpenUser: () => onOpenUser(status.user),
                      ),
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
