import 'community_post_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

import '../../../models/community_models.dart';
import '../../../widgets/community_rich_content.dart';
import '../../../widgets/social_chat_style.dart';

import 'community_primitives.dart';

class CommunityTopicCard extends StatelessWidget {
  const CommunityTopicCard({
    super.key,
    required this.topic,
    required this.onTap,
    this.compact = false,
  });

  final CommunityTopic topic;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(compact ? 12 : 15),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CommunityAvatar(imageUrl: topic.avatarUrl, radius: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      topic.title,
                      maxLines: compact ? 2 : 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                    if (topic.sourceTitle.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        topic.sourceTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: colors.primary),
                      ),
                    ],
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        CommunityMeta(
                          icon: Icons.person_outline,
                          text: topic.author,
                        ),
                        CommunityMeta(
                          icon: Icons.chat_bubble_outline_rounded,
                          text: '${topic.replyCount}',
                        ),
                        CommunityMeta(
                          icon: Icons.schedule_rounded,
                          text: topic.updatedText,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right_rounded, color: colors.outlineVariant),
            ],
          ),
        ),
      ),
    );
  }
}

double communityGroupCardHeight(BuildContext context) {
  final theme = Theme.of(context).textTheme;
  final scaler = MediaQuery.textScalerOf(context);
  final title = theme.bodyMedium;
  final meta = theme.bodySmall;
  final height =
      34 +
      scaler.scale(title?.fontSize ?? 14) * (title?.height ?? 1.5) +
      scaler.scale(meta?.fontSize ?? 12) * (meta?.height ?? 1.5);
  return height < 82 ? 82 : height.ceilToDouble();
}

class CommunityGroupCard extends StatelessWidget {
  const CommunityGroupCard({
    super.key,
    required this.group,
    required this.onTap,
  });

  final CommunityGroup group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CommunityAvatar(
              imageUrl: group.imageUrl,
              radius: 25,
              fallbackIcon: Icons.groups_rounded,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          group.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (group.nsfw) ...[
                        const SizedBox(width: 6),
                        const CommunityBadge(label: 'NSFW'),
                      ],
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    [
                      if (group.memberCount > 0) '${group.memberCount} 成员',
                      if (group.topicCount > 0) '${group.topicCount} 话题',
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    ),
  );
}

class CommunityPostCard extends StatelessWidget {
  const CommunityPostCard({
    super.key,
    required this.post,
    this.onReply,
    this.onOpenUser,
    this.currentUsername,
    this.onReactionChanged,
    this.reactionBusy = false,
    this.isFriend = false,
    this.onEdit,
    this.onDelete,
    this.onDeleteTopicOnWeb,
    this.discussionStyle = false,
  });

  final CommunityPost post;
  final bool discussionStyle;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onDeleteTopicOnWeb;
  final VoidCallback? onReply;
  final VoidCallback? onOpenUser;
  final String? currentUsername;
  final Future<void> Function(int? value)? onReactionChanged;
  final bool reactionBusy;

  /// Garage #14 / #1075: highlight friends in discussion threads.
  final bool isFriend;

  @override
  Widget build(BuildContext context) {
    if (discussionStyle) return _discussionMessage(context);
    final colors = Theme.of(context).colorScheme;
    final highlight = post.isOriginal || isFriend;
    return Padding(
      padding: EdgeInsets.only(
        left: post.isNested
            ? (MediaQuery.sizeOf(context).width < 420 ? 18 : 38)
            : 0,
        bottom: 10,
      ),
      child: Card(
        margin: EdgeInsets.zero,
        color: post.isOriginal
            ? colors.primaryContainer.withValues(alpha: .32)
            : isFriend
            ? colors.secondaryContainer.withValues(alpha: .28)
            : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 13, 10, 13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CommunityAvatar(
                imageUrl: post.avatarUrl,
                radius: 19,
                onTap: onOpenUser,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              GestureDetector(
                                onTap: onOpenUser,
                                child: Text(
                                  post.author,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: highlight
                                        ? colors.primary
                                        : onOpenUser == null
                                        ? null
                                        : colors.primary,
                                  ),
                                ),
                              ),
                              if (post.isOriginal)
                                const CommunityBadge(label: '楼主'),
                              if (isFriend) const CommunityBadge(label: '好友'),
                            ],
                          ),
                        ),
                        if (post.meta.isNotEmpty)
                          Flexible(
                            child: Text(
                              post.meta,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ),
                        if (onEdit != null ||
                            onDelete != null ||
                            onDeleteTopicOnWeb != null)
                          PopupMenuButton<String>(
                            tooltip: '管理我的内容',
                            onSelected: (value) {
                              if (value == 'edit') onEdit?.call();
                              if (value == 'delete') onDelete?.call();
                              if (value == 'web') onDeleteTopicOnWeb?.call();
                            },
                            itemBuilder: (_) => [
                              if (onEdit != null)
                                PopupMenuItem(
                                  value: 'edit',
                                  child: Text(
                                    post.isOriginal ? '编辑话题' : '编辑回复',
                                  ),
                                ),
                              if (onDelete != null)
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Text('删除回复'),
                                ),
                              if (onDeleteTopicOnWeb != null)
                                const PopupMenuItem(
                                  value: 'web',
                                  child: Text('在官网删除话题'),
                                ),
                            ],
                          ),
                      ],
                    ),
                    if (post.rawBody.isNotEmpty || post.body.isNotEmpty) ...[
                      const SizedBox(height: 9),
                      if (post.rawBody.isNotEmpty)
                        CommunityRichContent(post.rawBody)
                      else
                        CollapsibleCommunityText(post.body),
                    ],
                    if (post.rawBody.isEmpty && post.images.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      CommunityImageStrip(urls: post.images),
                    ],
                    if (post.reactions.isNotEmpty ||
                        onReply != null ||
                        onReactionChanged != null) ...[
                      const SizedBox(height: 10),
                      CommunityPostActions(
                        reactions: post.reactions,
                        currentUsername: currentUsername,
                        onReply: onReply,
                        onReactionChanged: onReactionChanged,
                        reactionBusy: reactionBusy,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _discussionMessage(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final authorPath = Uri.tryParse(post.userUrl)?.pathSegments;
    final self =
        currentUsername?.isNotEmpty == true &&
        authorPath?.lastOrNull?.toLowerCase() == currentUsername!.toLowerCase();
    final avatar = CommunityAvatar(
      imageUrl: post.avatarUrl,
      radius: 20,
      onTap: onOpenUser,
    );
    return Padding(
      padding: EdgeInsets.only(
        left: post.isNested && !self ? 16 : 0,
        right: post.isNested && self ? 16 : 0,
        bottom: 20,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: self
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (!self) ...[avatar, const SizedBox(width: 10)],
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: self
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 7,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      InkWell(
                        onTap: onOpenUser,
                        child: Text(
                          post.author,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: SocialChatStyle.accent(context),
                          ),
                        ),
                      ),
                      if (post.isOriginal)
                        const Text('楼主', style: TextStyle(fontSize: 11)),
                      if (isFriend)
                        const Text('好友', style: TextStyle(fontSize: 11)),
                      if (post.isNested)
                        const Icon(
                          CupertinoIcons.arrow_turn_down_right,
                          size: 12,
                        ),
                      if (post.meta.isNotEmpty)
                        Text(
                          post.meta,
                          style: TextStyle(
                            fontSize: 11,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      if (onEdit != null ||
                          onDelete != null ||
                          onDeleteTopicOnWeb != null)
                        PopupMenuButton<String>(
                          tooltip: '管理我的内容',
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.more_horiz, size: 18),
                          onSelected: (value) {
                            if (value == 'edit') onEdit?.call();
                            if (value == 'delete') onDelete?.call();
                            if (value == 'web') onDeleteTopicOnWeb?.call();
                          },
                          itemBuilder: (_) => [
                            if (onEdit != null)
                              PopupMenuItem(
                                value: 'edit',
                                child: Text(post.isOriginal ? '编辑话题' : '编辑回复'),
                              ),
                            if (onDelete != null)
                              const PopupMenuItem(
                                value: 'delete',
                                child: Text('删除回复'),
                              ),
                            if (onDeleteTopicOnWeb != null)
                              const PopupMenuItem(
                                value: 'web',
                                child: Text('在官网删除话题'),
                              ),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: self
                          ? SocialChatStyle.ownBubble(context)
                          : SocialChatStyle.paper(context),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(self ? 16 : 4),
                        topRight: Radius.circular(self ? 4 : 16),
                        bottomLeft: const Radius.circular(16),
                        bottomRight: const Radius.circular(16),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        DefaultTextStyle.merge(
                          style: const TextStyle(fontSize: 15, height: 1.6),
                          child: post.rawBody.isNotEmpty
                              ? CommunityRichContent(post.rawBody)
                              : CollapsibleCommunityText(post.body),
                        ),
                        if (post.rawBody.isEmpty && post.images.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          CommunityImageStrip(urls: post.images),
                        ],
                      ],
                    ),
                  ),
                  if (post.reactions.isNotEmpty ||
                      onReply != null ||
                      onReactionChanged != null)
                    CommunityPostActions(
                      reactions: post.reactions,
                      currentUsername: currentUsername,
                      onReply: null,
                      onReactionChanged: onReactionChanged,
                      reactionBusy: reactionBusy,
                      feedStyle: true,
                      trailing: onReply == null
                          ? null
                          : IconButton(
                              tooltip: '回复',
                              onPressed: onReply,
                              icon: const Icon(CupertinoIcons.reply, size: 20),
                            ),
                    ),
                ],
              ),
            ),
          ),
          if (self) ...[const SizedBox(width: 10), avatar],
        ],
      ),
    );
  }
}
