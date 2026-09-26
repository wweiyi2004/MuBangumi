import 'community_post_actions.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

import '../../../core/network/bangumi_endpoints.dart';
import '../../../models/community_models.dart';
import '../../../widgets/community_rich_content.dart';

import 'community_primitives.dart';

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
          CommunityPostActions(
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
              CommunityImageStrip(urls: reply.imageUrls),
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
