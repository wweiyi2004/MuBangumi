import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

import '../core/network/bangumi_endpoints.dart';
import '../core/network/bangumi_smiles.dart';
import '../models/community_models.dart';
import 'community_rich_content.dart';
import 'social_chat_style.dart';

class CommunityAvatar extends StatelessWidget {
  const CommunityAvatar({
    super.key,
    required this.imageUrl,
    this.radius = 22,
    this.fallbackIcon = Icons.person_rounded,
    this.onTap,
  });

  final String imageUrl;
  final double radius;
  final IconData fallbackIcon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final avatar = CircleAvatar(
      radius: radius,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      foregroundImage: imageUrl.isEmpty
          ? null
          : CachedNetworkImageProvider(BangumiEndpoints.imageUrl(imageUrl)),
      child: imageUrl.isEmpty ? Icon(fallbackIcon, size: radius) : null,
    );
    if (onTap == null) return avatar;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: avatar,
      ),
    );
  }
}

class CommunityErrorView extends StatelessWidget {
  const CommunityErrorView({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cloud_off_rounded,
            size: 44,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 14),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 14),
          FilledButton.tonalIcon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('重试'),
          ),
        ],
      ),
    ),
  );
}

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
                        _Meta(icon: Icons.person_outline, text: topic.author),
                        _Meta(
                          icon: Icons.chat_bubble_outline_rounded,
                          text: '${topic.replyCount}',
                        ),
                        _Meta(
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
                        const _Badge(label: 'NSFW'),
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
                              if (post.isOriginal) const _Badge(label: '楼主'),
                              if (isFriend) const _Badge(label: '好友'),
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
                      _ImageStrip(urls: post.images),
                    ],
                    if (post.reactions.isNotEmpty ||
                        onReply != null ||
                        onReactionChanged != null) ...[
                      const SizedBox(height: 10),
                      _CommunityPostActions(
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
                          _ImageStrip(urls: post.images),
                        ],
                      ],
                    ),
                  ),
                  if (post.reactions.isNotEmpty ||
                      onReply != null ||
                      onReactionChanged != null)
                    _CommunityPostActions(
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

class _CommunityPostActions extends StatelessWidget {
  const _CommunityPostActions({
    required this.reactions,
    required this.currentUsername,
    required this.onReply,
    required this.onReactionChanged,
    required this.reactionBusy,
    this.leading,
    this.trailing,
    this.feedStyle = false,
  });

  final List<CommunityReaction> reactions;
  final String? currentUsername;
  final VoidCallback? onReply;
  final Future<void> Function(int? value)? onReactionChanged;
  final bool reactionBusy;
  final Widget? leading, trailing;
  final bool feedStyle;

  @override
  Widget build(BuildContext context) {
    final visibleReactions = reactions
        .where(
          (reaction) =>
              reaction.count > 0 &&
              BangumiReactions.optionFor(reaction.value) != null,
        )
        .toList();
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                if (leading != null) ...[leading!, const SizedBox(width: 10)],
                for (
                  var index = 0;
                  index < visibleReactions.length;
                  index++
                ) ...[
                  if (index > 0) const SizedBox(width: 6),
                  _reactionChip(context, visibleReactions[index]),
                ],
              ],
            ),
          ),
        ),
        if (onReply != null)
          TextButton.icon(
            onPressed: onReply,
            icon: const Icon(Icons.reply_rounded, size: 18),
            label: const Text('回复'),
          ),
        if (onReactionChanged != null && feedStyle)
          IconButton(
            key: const ValueKey('post-reaction-picker'),
            tooltip: '贴贴',
            onPressed: reactionBusy ? null : () => _showPicker(context),
            color: reactions.any((r) => r.isSelectedBy(currentUsername))
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.onSurface,
            icon: reactionBusy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    reactions.any((r) => r.isSelectedBy(currentUsername))
                        ? CupertinoIcons.heart_fill
                        : CupertinoIcons.heart,
                    size: 25,
                  ),
          ),
        if (onReactionChanged != null && !feedStyle)
          TextButton.icon(
            key: const ValueKey('post-reaction-picker'),
            onPressed: reactionBusy ? null : () => _showPicker(context),
            icon: reactionBusy
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.favorite_border_rounded, size: 18),
            label: const Text('贴贴'),
          ),
        ?trailing,
      ],
    );
  }

  Widget _reactionChip(BuildContext context, CommunityReaction reaction) {
    final option = BangumiReactions.optionFor(reaction.value)!;
    final selected = reaction.isSelectedBy(currentUsername);
    final colors = Theme.of(context).colorScheme;
    final names = reaction.users
        .take(8)
        .map((user) => user.displayName)
        .join('、');
    final extra = reaction.count > 8 ? ' 等 ${reaction.count} 人' : '';
    return Tooltip(
      message: names.isEmpty ? '${reaction.count} 人贴贴' : '$names$extra',
      child: Material(
        color: selected
            ? colors.primaryContainer
            : colors.surfaceContainerHighest,
        shape: StadiumBorder(
          side: BorderSide(
            color: selected ? colors.primary : colors.outlineVariant,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('post-reaction-${reaction.value}'),
          onTap: reactionBusy || onReactionChanged == null
              ? null
              : () => onReactionChanged!(selected ? null : reaction.value),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CachedNetworkImage(
                  imageUrl: BangumiEndpoints.imageUrl(option.imageUrl),
                  width: 23,
                  height: 23,
                  fit: BoxFit.contain,
                  errorWidget: (_, _, _) =>
                      const Icon(Icons.favorite_rounded, size: 19),
                ),
                const SizedBox(width: 5),
                Text(
                  '${reaction.count}',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: selected ? colors.primary : colors.onSurfaceVariant,
                    fontWeight: selected ? FontWeight.w700 : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showPicker(BuildContext context) async {
    final value = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '选择贴贴',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 14),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 6,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                        ),
                    itemCount: BangumiReactions.options.length,
                    itemBuilder: (context, index) {
                      final option = BangumiReactions.options[index];
                      final selected = reactions.any(
                        (reaction) =>
                            reaction.value == option.value &&
                            reaction.isSelectedBy(currentUsername),
                      );
                      return Tooltip(
                        message: selected
                            ? '${option.token}（再次选择可取消）'
                            : option.token,
                        child: Material(
                          color: selected
                              ? Theme.of(context).colorScheme.primaryContainer
                              : Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            key: ValueKey('reaction-option-${option.value}'),
                            onTap: () => Navigator.pop(context, option.value),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                CachedNetworkImage(
                                  imageUrl: BangumiEndpoints.imageUrl(
                                    option.imageUrl,
                                  ),
                                  width: 34,
                                  height: 34,
                                  fit: BoxFit.contain,
                                  errorWidget: (_, _, _) => const Icon(
                                    Icons.favorite_rounded,
                                    size: 26,
                                  ),
                                ),
                                if (selected)
                                  Positioned(
                                    right: 4,
                                    top: 4,
                                    child: Icon(
                                      Icons.check_circle_rounded,
                                      size: 15,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (value == null || onReactionChanged == null) return;
    final selected = reactions.any(
      (reaction) =>
          reaction.value == value && reaction.isSelectedBy(currentUsername),
    );
    await onReactionChanged!(selected ? null : value);
  }
}

typedef CommunityTimelineReplyCallback =
    void Function(CommunityTimelineReply reply, CommunityTimelineReply? parent);

class CommunityTimelineCard extends StatelessWidget {
  const CommunityTimelineCard({
    super.key,
    required this.item,
    this.onReply,
    this.onOpenSubject,
    this.onOpenUser,
    this.replies,
    this.repliesExpanded = false,
    this.repliesLoading = false,
    this.repliesError,
    this.onToggleReplies,
    this.onReloadReplies,
    this.onReplyTo,
    this.onOpenTarget,
    this.onDelete,
    this.onReactionChanged,
    this.currentUsername,
    this.reactionBusy = false,
  });

  final CommunityTimelineItem item;
  final ValueChanged<CommunityTimelineTarget>? onOpenTarget;
  final VoidCallback? onDelete;
  final Future<void> Function(int? value)? onReactionChanged;
  final String? currentUsername;
  final bool reactionBusy;
  final VoidCallback? onReply;
  final VoidCallback? onOpenSubject;
  final ValueChanged<CommunityUser>? onOpenUser;
  final List<CommunityTimelineReply>? replies;
  final bool repliesExpanded;
  final bool repliesLoading;
  final String? repliesError;
  final VoidCallback? onToggleReplies;
  final VoidCallback? onReloadReplies;
  final CommunityTimelineReplyCallback? onReplyTo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final inset = Color.alphaBlend(
      colors.onSurface.withValues(alpha: .035),
      colors.surface,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CommunityAvatar(
                imageUrl: item.user.avatarUrl,
                radius: 22,
                onTap: onOpenUser == null ? null : () => onOpenUser!(item.user),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: onOpenUser == null
                          ? null
                          : () => onOpenUser!(item.user),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Text(
                          item.user.displayName,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                            color: theme.brightness == Brightness.dark
                                ? const Color(0xFFB2C9E5)
                                : const Color(0xFF385675),
                          ),
                        ),
                      ),
                    ),
                    if (!item.isStatus && item.description.isNotEmpty)
                      Text(
                        item.description,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (onDelete != null || onOpenUser != null)
                PopupMenuButton<String>(
                  tooltip: '更多动态操作',
                  icon: const Icon(Icons.more_horiz),
                  onSelected: (action) {
                    if (action == 'delete') onDelete?.call();
                    if (action == 'profile') onOpenUser?.call(item.user);
                  },
                  itemBuilder: (_) => [
                    if (onOpenUser != null)
                      const PopupMenuItem(
                        value: 'profile',
                        child: Text('查看主页'),
                      ),
                    if (onDelete != null)
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('删除这条动态'),
                      ),
                  ],
                ),
            ],
          ),
          if (item.content.isNotEmpty || item.rawContent.isNotEmpty) ...[
            const SizedBox(height: 14),
            DefaultTextStyle.merge(
              style: theme.textTheme.bodyLarge?.copyWith(
                fontSize: 17,
                height: 1.65,
              ),
              child: item.rawContent.isNotEmpty
                  ? CommunityRichContent(item.rawContent)
                  : CollapsibleCommunityText(item.content),
            ),
          ],
          if (item.targets.isNotEmpty) ...[
            const SizedBox(height: 14),
            _TimelineTargets(targets: item.targets, onOpen: onOpenTarget),
          ],
          if (item.targets.isEmpty && item.imageUrls.isNotEmpty) ...[
            const SizedBox(height: 14),
            _TimelineImages(urls: item.imageUrls),
          ],
          if (item.progress case final progress?) ...[
            const SizedBox(height: 14),
            _TimelineProgressPanel(
              progress: progress,
              onOpenSubject: onOpenSubject,
            ),
          ],
          const SizedBox(height: 8),
          _CommunityPostActions(
            feedStyle: true,
            leading: Text(
              communityRelativeTime(item.createdAt),
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 12,
                color: colors.onSurfaceVariant,
              ),
            ),
            trailing: item.replyCount > 0 || repliesExpanded
                ? Tooltip(
                    message: repliesExpanded
                        ? '收起回复'
                        : '${item.replyCount} 条回复',
                    child: TextButton.icon(
                      onPressed: onToggleReplies,
                      style: TextButton.styleFrom(
                        foregroundColor: colors.onSurface,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      icon: const Icon(CupertinoIcons.chat_bubble, size: 24),
                      label: Text(
                        '${item.replyCount}',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  )
                : onReply == null
                ? null
                : IconButton(
                    tooltip: '回复这条动态',
                    onPressed: onReply,
                    icon: const Icon(CupertinoIcons.chat_bubble, size: 24),
                  ),
            reactions: item.reactions,
            currentUsername: currentUsername,
            onReply: null,
            onReactionChanged: onReactionChanged,
            reactionBusy: reactionBusy,
          ),
          if ((item.isStatus && (onReply != null || item.replyCount > 0)) ||
              repliesExpanded)
            Container(
              margin: const EdgeInsets.only(top: 2, bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: inset,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (repliesExpanded) ...[
                    if (repliesLoading)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    else if (repliesError != null)
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              repliesError!,
                              style: TextStyle(color: colors.error),
                            ),
                          ),
                          TextButton(
                            onPressed: onReloadReplies ?? onToggleReplies,
                            child: const Text('重试'),
                          ),
                        ],
                      )
                    else if (replies == null || replies!.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('暂时没有回复'),
                      )
                    else
                      _TimelineReplyList(
                        replies: replies!,
                        onReply: onReplyTo,
                        onOpenUser: onOpenUser,
                      ),
                  ],
                  if (onReply != null)
                    InkWell(
                      onTap: onReply,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 4,
                        ),
                        child: Text(
                          '说点什么…',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          Divider(
            height: 24,
            thickness: .6,
            color: colors.outlineVariant.withValues(alpha: .5),
          ),
        ],
      ),
    );
  }
}

class _TimelineTargets extends StatefulWidget {
  const _TimelineTargets({required this.targets, this.onOpen});
  final List<CommunityTimelineTarget> targets;
  final ValueChanged<CommunityTimelineTarget>? onOpen;
  @override
  State<_TimelineTargets> createState() => _TimelineTargetsState();
}

class _TimelineTargetsState extends State<_TimelineTargets> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final target in widget.targets.take(
        _expanded ? widget.targets.length : 5,
      ))
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: Color.alphaBlend(
              Theme.of(context).colorScheme.onSurface.withValues(alpha: .035),
              Theme.of(context).colorScheme.surface,
            ),
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: widget.onOpen == null
                  ? null
                  : () => widget.onOpen!(target),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    _TimelineCover(
                      imageUrl: target.imageUrl,
                      icon: switch (target.kind) {
                        CommunityTimelineTargetKind.subject =>
                          Icons.book_outlined,
                        CommunityTimelineTargetKind.blog =>
                          Icons.article_outlined,
                        _ => Icons.person_outline,
                      },
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            target.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            switch (target.kind) {
                              CommunityTimelineTargetKind.subject => '作品',
                              CommunityTimelineTargetKind.blog => '日志',
                              CommunityTimelineTargetKind.character => '角色',
                              CommunityTimelineTargetKind.person => '人物',
                            },
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                    if (widget.onOpen != null)
                      const Icon(Icons.chevron_right, size: 18),
                  ],
                ),
              ),
            ),
          ),
        ),
      if (widget.targets.length > 5)
        TextButton(
          onPressed: () => setState(() => _expanded = !_expanded),
          child: Text(_expanded ? '收起' : '展开全部 ${widget.targets.length} 项'),
        ),
    ],
  );
}

class _TimelineProgressPanel extends StatelessWidget {
  const _TimelineProgressPanel({required this.progress, this.onOpenSubject});

  final CommunityTimelineProgress progress;
  final VoidCallback? onOpenSubject;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final episode = progress.episode;
    final scoreText = progress.score > 0
        ? '评分 ${progress.score.toStringAsFixed(1)}'
        : '';
    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onOpenSubject,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _TimelineCover(
                    imageUrl: progress.imageUrl,
                    icon: Icons.movie_outlined,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          progress.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          episode == null
                              ? _batchProgressText(progress)
                              : [
                                  _episodeLabel(episode),
                                  if (episode.title.isNotEmpty) episode.title,
                                ].join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (scoreText.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            scoreText,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (onOpenSubject != null)
                    const Icon(Icons.chevron_right_rounded),
                ],
              ),
              const SizedBox(height: 9),
              if (episode != null)
                _EpisodeGridCell(label: _episodeLabel(episode), active: true)
              else
                _BatchEpisodeGrid(progress: progress),
            ],
          ),
        ),
      ),
    );
  }
}

class _BatchEpisodeGrid extends StatelessWidget {
  const _BatchEpisodeGrid({required this.progress});

  final CommunityTimelineProgress progress;

  @override
  Widget build(BuildContext context) {
    final count = progress.episodeProgress ?? 0;
    final volume = progress.volumeProgress ?? 0;
    if (count <= 0 && volume <= 0) {
      return const Text('没有可显示的章节进度');
    }
    if (count <= 0) {
      return _EpisodeGridCell(label: 'VOL.$volume', active: true);
    }
    final first = count > 12 ? count - 11 : 1;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          if (first > 1) ...[
            _EpisodeGridCell(label: 'EP.1…${first - 1}', active: false),
            const SizedBox(width: 5),
          ],
          for (var number = first; number <= count; number++) ...[
            if (number > first) const SizedBox(width: 5),
            _EpisodeGridCell(label: 'EP.$number', active: number == count),
          ],
        ],
      ),
    );
  }
}

class _EpisodeGridCell extends StatelessWidget {
  const _EpisodeGridCell({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 43),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: active
            ? colors.primaryContainer
            : colors.surfaceContainerHighest,
        border: Border.all(
          color: active ? colors.primary : colors.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: active ? colors.onPrimaryContainer : colors.onSurfaceVariant,
          fontSize: 11,
          fontWeight: active ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    );
  }
}

class _TimelineReplyList extends StatelessWidget {
  const _TimelineReplyList({
    required this.replies,
    this.onReply,
    this.onOpenUser,
  });

  final List<CommunityTimelineReply> replies;
  final CommunityTimelineReplyCallback? onReply;
  final ValueChanged<CommunityUser>? onOpenUser;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var index = 0; index < replies.length; index++) ...[
        if (index > 0) const Divider(height: 18),
        _TimelineReplyView(
          reply: replies[index],
          floor: '#${index + 1}',
          onReply: onReply,
          onOpenUser: onOpenUser,
        ),
        for (
          var nestedIndex = 0;
          nestedIndex < replies[index].replies.length;
          nestedIndex++
        )
          Padding(
            padding: const EdgeInsets.only(left: 30, top: 10),
            child: _TimelineReplyView(
              reply: replies[index].replies[nestedIndex],
              parent: replies[index],
              floor: '#${index + 1}-${nestedIndex + 1}',
              compact: true,
              onReply: onReply,
              onOpenUser: onOpenUser,
            ),
          ),
      ],
    ],
  );
}

class _TimelineReplyView extends StatelessWidget {
  const _TimelineReplyView({
    required this.reply,
    required this.floor,
    this.parent,
    this.compact = false,
    this.onReply,
    this.onOpenUser,
  });

  final CommunityTimelineReply reply;
  final CommunityTimelineReply? parent;
  final String floor;
  final bool compact;
  final CommunityTimelineReplyCallback? onReply;
  final ValueChanged<CommunityUser>? onOpenUser;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      CommunityAvatar(
        imageUrl: reply.user.avatarUrl,
        radius: compact ? 14 : 17,
        onTap: onOpenUser == null ? null : () => onOpenUser!(reply.user),
      ),
      const SizedBox(width: 9),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: onOpenUser == null
                        ? null
                        : () => onOpenUser!(reply.user),
                    child: Text(
                      reply.user.displayName,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: onOpenUser == null
                            ? null
                            : Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ),
                Text(
                  '$floor · ${communityRelativeTime(reply.createdAt)}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
            if (reply.content.isNotEmpty) ...[
              const SizedBox(height: 5),
              CollapsibleCommunityText(reply.content),
            ],
            if (reply.imageUrls.isNotEmpty) ...[
              const SizedBox(height: 8),
              _ImageStrip(urls: reply.imageUrls),
            ],
            if (onReply != null && !reply.isDeleted)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => onReply!(reply, parent),
                  icon: const Icon(Icons.reply_rounded, size: 16),
                  label: const Text('回复'),
                ),
              ),
          ],
        ),
      ),
    ],
  );
}

class CollapsibleCommunityText extends StatefulWidget {
  const CollapsibleCommunityText(
    this.text, {
    super.key,
    this.collapseAfter = 700,
  });

  final String text;
  final int collapseAfter;

  @override
  State<CollapsibleCommunityText> createState() =>
      _CollapsibleCommunityTextState();
}

class _CollapsibleCommunityTextState extends State<CollapsibleCommunityText> {
  bool _expanded = false;

  bool get _isLong =>
      widget.text.length > widget.collapseAfter ||
      '\n'.allMatches(widget.text).length >= 14;

  List<InlineSpan> _spansFor(BuildContext context, String text) {
    final style = DefaultTextStyle.of(context).style;
    final parts = BangumiSmiles.split(text);
    if (parts.every((part) => !part.isImage)) {
      return [TextSpan(text: text, style: style)];
    }
    return [
      for (final part in parts)
        if (part.isImage)
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: Image(
                image: CachedNetworkImageProvider(
                  BangumiEndpoints.imageUrl(part.imageUrl!),
                ),
                height: 22,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => Text(part.text),
              ),
            ),
          )
        else
          TextSpan(text: part.text, style: style),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final collapsed = _isLong && !_expanded;
    final visible = collapsed && widget.text.length > widget.collapseAfter
        ? '${widget.text.substring(0, widget.collapseAfter).trimRight()}…'
        : widget.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectableText.rich(
          TextSpan(children: _spansFor(context, visible)),
          maxLines: collapsed ? 14 : null,
          scrollPhysics: const NeverScrollableScrollPhysics(),
        ),
        if (_isLong)
          TextButton.icon(
            onPressed: () => setState(() => _expanded = !_expanded),
            icon: Icon(
              _expanded ? Icons.unfold_less_rounded : Icons.unfold_more_rounded,
              size: 17,
            ),
            label: Text(_expanded ? '收起长内容' : '展开全文'),
          ),
      ],
    );
  }
}

class BlockedCommunityContent extends StatefulWidget {
  const BlockedCommunityContent({
    super.key,
    required this.username,
    required this.blocked,
    required this.child,
  });

  final String username;
  final bool blocked;
  final Widget child;

  @override
  State<BlockedCommunityContent> createState() =>
      _BlockedCommunityContentState();
}

class _BlockedCommunityContentState extends State<BlockedCommunityContent> {
  bool _revealed = false;

  @override
  void didUpdateWidget(covariant BlockedCommunityContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.blocked && widget.blocked) _revealed = false;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.blocked || _revealed) return widget.child;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: const Icon(Icons.visibility_off_outlined),
        title: Text('已折叠 @${widget.username} 的内容'),
        subtitle: const Text('这是本机屏蔽规则，不影响 Bangumi 账号设置'),
        trailing: TextButton(
          onPressed: () => setState(() => _revealed = true),
          child: const Text('临时查看'),
        ),
      ),
    );
  }
}

String _episodeLabel(CommunityTimelineEpisode episode) {
  final prefix = switch (episode.type) {
    1 => 'SP',
    2 => 'OP',
    3 => 'ED',
    4 => 'PV',
    5 => 'MAD',
    6 => 'OTHER',
    _ => 'EP',
  };
  final sort = episode.sort == episode.sort.roundToDouble()
      ? episode.sort.toInt().toString()
      : episode.sort.toStringAsFixed(1);
  return '$prefix.$sort';
}

String _batchProgressText(CommunityTimelineProgress progress) {
  final episode = progress.episodeProgress;
  final volume = progress.volumeProgress;
  final parts = <String>[
    if (volume != null)
      '第 $volume${progress.volumeTotal.isEmpty ? '' : '/${progress.volumeTotal}'} 卷',
    if (episode != null)
      '第 $episode${progress.episodeTotal.isEmpty ? '' : '/${progress.episodeTotal}'} 话',
  ];
  return parts.isEmpty ? '更新了章节进度' : '进度 ${parts.join(' · ')}';
}

class _TimelineCover extends StatelessWidget {
  const _TimelineCover({required this.imageUrl, required this.icon});
  final String imageUrl;
  final IconData icon;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(7),
    child: SizedBox(
      width: 64,
      height: 84,
      child: ColoredBox(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .06),
        child: imageUrl.isEmpty
            ? Icon(icon, size: 26)
            : CachedNetworkImage(
                imageUrl: BangumiEndpoints.imageUrl(imageUrl),
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => Icon(icon, size: 26),
              ),
      ),
    ),
  );
}

class _TimelineImages extends StatelessWidget {
  const _TimelineImages({required this.urls});
  final List<String> urls;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = urls.length == 1
          ? 1
          : (urls.length == 2 || urls.length == 4 ? 2 : 3);
      final width = constraints.maxWidth.clamp(
        0.0,
        urls.length == 1 ? 420.0 : 640.0,
      );
      final tile = (width - (columns - 1) * 6) / columns;
      return Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final url in urls)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedNetworkImage(
                imageUrl: BangumiEndpoints.imageUrl(url),
                width: tile,
                height: columns == 1 ? tile * .75 : tile,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => SizedBox(
                  width: tile,
                  height: columns == 1 ? tile * .75 : tile,
                  child: const Icon(Icons.broken_image_outlined),
                ),
              ),
            ),
        ],
      );
    },
  );
}

class _ImageStrip extends StatelessWidget {
  const _ImageStrip({required this.urls});

  final List<String> urls;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 112,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: urls.length,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (context, index) => ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: CachedNetworkImage(
          imageUrl: BangumiEndpoints.imageUrl(urls[index]),
          width: 112,
          height: 112,
          fit: BoxFit.cover,
          errorWidget: (_, _, _) => const SizedBox.square(
            dimension: 112,
            child: Icon(Icons.broken_image_outlined),
          ),
        ),
      ),
    ),
  );
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Theme.of(context).colorScheme.outline),
        const SizedBox(width: 4),
        Text(text, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(5),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      child: Text(
        label,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onErrorContainer,
          fontSize: 9,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

String communityRelativeTime(DateTime time) {
  final difference = DateTime.now().difference(time);
  if (difference.isNegative || difference.inMinutes < 1) return '刚刚';
  if (difference.inHours < 1) return '${difference.inMinutes} 分钟前';
  if (difference.inDays < 1) return '${difference.inHours} 小时前';
  if (difference.inDays < 30) return '${difference.inDays} 天前';
  String two(int value) => value.toString().padLeft(2, '0');
  return '${time.year}-${two(time.month)}-${two(time.day)}';
}
