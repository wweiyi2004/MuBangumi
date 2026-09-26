import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../models/community_models.dart';
import 'community_widgets.dart';
import 'social_chat_style.dart';
import '../core/theme/app_tokens.dart';

class GroupConversationTile extends StatelessWidget {
  const GroupConversationTile({
    super.key,
    required this.group,
    required this.onTap,
  });
  final CommunityGroup group;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
      child: Row(
        children: [
          CommunityAvatar(
            imageUrl: group.imageUrl,
            radius: 26,
            fallbackIcon: CupertinoIcons.person_3,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  group.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${group.memberCount} 位成员 · ${group.topicCount} 个讨论${group.nsfw ? ' · NSFW' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppText.caption,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Icon(
            CupertinoIcons.chevron_right,
            size: 15,
            color: Theme.of(context).colorScheme.outline,
          ),
        ],
      ),
    ),
  );
}

class GroupDiscussionTile extends StatelessWidget {
  const GroupDiscussionTile({
    super.key,
    required this.topic,
    required this.onTap,
  });
  final CommunityTopic topic;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: SocialChatStyle.paper(context),
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CommunityAvatar(
              imageUrl: topic.avatarUrl,
              radius: 23,
              fallbackIcon: CupertinoIcons.chat_bubble_2,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    topic.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    [
                      if (topic.author.isNotEmpty) topic.author,
                      '${topic.replyCount} 条回复',
                      if (topic.updatedText.isNotEmpty) topic.updatedText,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppText.caption,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
