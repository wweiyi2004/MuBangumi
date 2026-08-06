import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/network/bangumi_endpoints.dart';
import '../models/community_models.dart';

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
                          style: const TextStyle(fontWeight: FontWeight.w700),
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
    this.isFriend = false,
  });

  final CommunityPost post;
  final VoidCallback? onReply;
  final VoidCallback? onOpenUser;
  /// Garage #14 / #1075: highlight friends in discussion threads.
  final bool isFriend;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final highlight = post.isOriginal || isFriend;
    return Padding(
      padding: EdgeInsets.only(left: post.isNested ? 38 : 0, bottom: 10),
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
                                const _Badge(label: '楼主'),
                              if (isFriend) const _Badge(label: '好友'),
                            ],
                          ),
                        ),
                        if (post.meta.isNotEmpty)
                          Text(
                            post.meta,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                      ],
                    ),
                    if (post.body.isNotEmpty) ...[
                      const SizedBox(height: 9),
                      SelectableText(post.body),
                    ],
                    if (post.images.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      _ImageStrip(urls: post.images),
                    ],
                  ],
                ),
              ),
              if (onReply != null)
                IconButton(
                  tooltip: '回复',
                  visualDensity: VisualDensity.compact,
                  onPressed: onReply,
                  icon: const Icon(Icons.reply_rounded, size: 19),
                ),
            ],
          ),
        ),
      ),
    );
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
  });

  final CommunityTimelineItem item;
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
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CommunityAvatar(
            imageUrl: item.user.avatarUrl,
            radius: 21,
            onTap: onOpenUser == null ? null : () => onOpenUser!(item.user),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      WidgetSpan(
                        alignment: PlaceholderAlignment.baseline,
                        baseline: TextBaseline.alphabetic,
                        child: GestureDetector(
                          onTap: onOpenUser == null
                              ? null
                              : () => onOpenUser!(item.user),
                          child: Text(
                            item.user.displayName,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: onOpenUser == null
                                  ? null
                                  : Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                      ),
                      TextSpan(text: '  ${item.description}'),
                    ],
                  ),
                ),
                if (item.content.isNotEmpty) ...[
                  const SizedBox(height: 9),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: SelectableText(item.content),
                  ),
                ],
                if (item.imageUrls.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _ImageStrip(urls: item.imageUrls),
                ],
                if (item.progress case final progress?) ...[
                  const SizedBox(height: 10),
                  _TimelineProgressPanel(
                    progress: progress,
                    onOpenSubject: onOpenSubject,
                  ),
                ],
                const SizedBox(height: 9),
                Row(
                  children: [
                    Text(
                      communityRelativeTime(item.createdAt),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    const Spacer(),
                    if (item.isStatus &&
                        (item.replyCount > 0 || repliesExpanded))
                      TextButton.icon(
                        onPressed: onToggleReplies,
                        icon: Icon(
                          repliesExpanded
                              ? Icons.expand_less_rounded
                              : Icons.chat_bubble_outline_rounded,
                          size: 17,
                        ),
                        label: Text(
                          repliesExpanded ? '收起回复' : '${item.replyCount} 条回复',
                        ),
                      ),
                    if (onReply != null)
                      IconButton(
                        tooltip: '回复这条动态',
                        visualDensity: VisualDensity.compact,
                        onPressed: onReply,
                        icon: const Icon(Icons.reply_rounded, size: 19),
                      ),
                  ],
                ),
                if (repliesExpanded) ...[
                  const Divider(height: 16),
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
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
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
              ],
            ),
          ),
        ],
      ),
    ),
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
                  ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: progress.imageUrl.isEmpty
                        ? Container(
                            width: 42,
                            height: 56,
                            color: colors.surfaceContainerHighest,
                            child: const Icon(Icons.movie_outlined, size: 20),
                          )
                        : CachedNetworkImage(
                            imageUrl: BangumiEndpoints.imageUrl(
                              progress.imageUrl,
                            ),
                            width: 42,
                            height: 56,
                            fit: BoxFit.cover,
                            errorWidget: (_, _, _) => const SizedBox(
                              width: 42,
                              height: 56,
                              child: Icon(Icons.broken_image_outlined),
                            ),
                          ),
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
              SelectableText(reply.content),
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
