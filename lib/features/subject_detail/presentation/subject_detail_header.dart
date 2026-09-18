import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/external_link.dart';
import '../../../models/bangumi_models.dart';
import '../../../core/network/bangumi_endpoints.dart';
import '../../../widgets/subject_widgets.dart';

class SubjectDetailHeader extends StatelessWidget {
  const SubjectDetailHeader({
    super.key,
    required this.subject,
    required this.collection,
    required this.busy,
    required this.onCollectionChanged,
    required this.onManageCollection,
    this.onTagTap,
    this.showActions = true,
  });

  final bool showActions;
  final Subject subject;
  final UserCollection? collection;
  final bool busy;
  final ValueChanged<CollectionType> onCollectionChanged;
  final VoidCallback onManageCollection;
  final ValueChanged<String>? onTagTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 620;
        final veryNarrow = constraints.maxWidth < 380;
        final padding = compact ? 14.0 : 20.0;
        final coverW = veryNarrow
            ? 96.0
            : compact
            ? 112.0
            : 170.0;
        final coverH = veryNarrow
            ? 136.0
            : compact
            ? 158.0
            : 240.0;
        final cover = SubjectCover(
          subject: subject,
          width: coverW,
          height: coverH,
          borderRadius: compact ? 14 : 18,
          size: BangumiImageSize.large,
        );

        final titleStyle = compact
            ? Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                height: 1.2,
              )
            : Theme.of(context).textTheme.headlineMedium;

        final titleBlock = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(subject.displayName, style: titleStyle),
            if (subject.nameCn.isNotEmpty && subject.name.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                subject.name,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: compact ? 13 : null,
                ),
              ),
            ],
            SizedBox(height: compact ? 10 : 14),
            Wrap(
              spacing: compact ? 8 : 12,
              runSpacing: 6,
              children: [
                _Meta(
                  icon: subjectTypeIcon(subject.type),
                  text: subject.type.label,
                  compact: compact,
                ),
                if (subject.score > 0)
                  _Meta(
                    icon: Icons.star_rounded,
                    text: subject.score.toStringAsFixed(2),
                    color: const Color(0xFFF3A646),
                    compact: compact,
                  ),
                if (subject.rank > 0)
                  _Meta(
                    icon: Icons.emoji_events_outlined,
                    text: '#${subject.rank}',
                    compact: compact,
                  ),
                if (!compact && subject.ratingTotal > 0)
                  _Meta(
                    icon: Icons.how_to_vote_outlined,
                    text: '${subject.ratingTotal} 人评分',
                  ),
                if (subject.episodeCount > 0)
                  _Meta(
                    icon: Icons.play_circle_outline_rounded,
                    text: '${subject.episodeCount} 话',
                    compact: compact,
                  ),
                if (subject.volumeCount > 0)
                  _Meta(
                    icon: Icons.menu_book_outlined,
                    text: '${subject.volumeCount} 卷',
                    compact: compact,
                  ),
                if (subject.date.isNotEmpty)
                  _Meta(
                    icon: Icons.calendar_today_outlined,
                    text: subject.date,
                    compact: compact,
                  ),
                if (!compact && subject.platform.isNotEmpty)
                  _Meta(icon: Icons.tv_outlined, text: subject.platform),
                if (subject.nsfw)
                  _Meta(
                    icon: Icons.warning_amber_rounded,
                    text: 'NSFW',
                    color: const Color(0xFFE95383),
                    compact: compact,
                  ),
              ],
            ),
          ],
        );

        final tags = subject.metaTags.isEmpty && subject.tags.isEmpty
            ? null
            : Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final tag in [
                    ...subject.metaTags,
                    ...subject.tags.where((t) => !subject.metaTags.contains(t)),
                  ].take(compact ? 8 : 10))
                    ActionChip(
                      label: Text(tag),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onPressed: onTagTap == null ? null : () => onTagTap!(tag),
                    ),
                ],
              );

        final officialSite = subject.officialSite.isEmpty
            ? null
            : Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed: () {
                    final raw = subject.officialSite.trim();
                    final uri = Uri.tryParse(
                      raw.startsWith('http') ? raw : 'https://$raw',
                    );
                    unawaited(launchExternalLink(uri));
                  },
                  icon: const Icon(Icons.public_rounded, size: 18),
                  label: const Text('官方网站'),
                ),
              );

        final myCollection =
            collection == null ||
                (collection!.rate <= 0 &&
                    collection!.comment.isEmpty &&
                    collection!.tags.isEmpty)
            ? null
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (collection!.rate > 0)
                        Chip(
                          avatar: const Icon(Icons.star_rounded, size: 18),
                          label: Text('我的评分 ${collection!.rate}'),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      if (collection!.private)
                        const Chip(
                          avatar: Icon(Icons.lock_outline_rounded, size: 16),
                          label: Text('仅自己可见'),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      for (final tag in collection!.tags.take(compact ? 4 : 6))
                        ActionChip(
                          label: Text(tag),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          onPressed: onTagTap == null
                              ? null
                              : () => onTagTap!(tag),
                        ),
                    ],
                  ),
                  if (collection!.comment.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      collection!.comment,
                      maxLines: compact ? 3 : 6,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              );

        final collectButton = MenuAnchor(
          builder: (context, controller, child) => FilledButton.icon(
            onPressed: busy
                ? null
                : () => controller.isOpen
                      ? controller.close()
                      : controller.open(),
            icon: busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    collection == null
                        ? Icons.add_rounded
                        : Icons.bookmark_rounded,
                  ),
            label: Text(
              collection?.type.labelFor(subject.type) ?? '加入收藏',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          menuChildren: [
            for (final type in CollectionType.values)
              MenuItemButton(
                leadingIcon: collection?.type == type
                    ? const Icon(Icons.check_rounded)
                    : null,
                onPressed: () => onCollectionChanged(type),
                child: Text(type.labelFor(subject.type)),
              ),
          ],
        );

        final manageButton = OutlinedButton.icon(
          onPressed: busy ? null : onManageCollection,
          icon: const Icon(Icons.edit_note_rounded),
          label: Text(compact ? '评分' : '评分与吐槽'),
        );

        final actions = compact
            ? Row(
                children: [
                  Expanded(child: collectButton),
                  const SizedBox(width: 8),
                  Expanded(child: manageButton),
                ],
              )
            : Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  SizedBox(width: 210, child: collectButton),
                  manageButton,
                ],
              );

        if (compact) {
          return Padding(
            padding: EdgeInsets.all(padding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    cover,
                    SizedBox(width: veryNarrow ? 12 : 14),
                    Expanded(child: titleBlock),
                  ],
                ),
                if (tags != null) ...[const SizedBox(height: 12), tags],
                if (officialSite != null) ...[
                  const SizedBox(height: 4),
                  officialSite,
                ],
                if (myCollection != null) ...[
                  const SizedBox(height: 10),
                  myCollection,
                ],
                if (showActions) ...[const SizedBox(height: 12), actions],
              ],
            ),
          );
        }

        return Padding(
          padding: EdgeInsets.all(padding),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              cover,
              const SizedBox(width: 28),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    titleBlock,
                    if (tags != null) ...[const SizedBox(height: 14), tags],
                    if (officialSite != null) ...[
                      const SizedBox(height: 4),
                      officialSite,
                    ],
                    if (myCollection != null) ...[
                      const SizedBox(height: 12),
                      myCollection,
                    ],
                    const SizedBox(height: 12),
                    actions,
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({
    required this.icon,
    required this.text,
    this.color,
    this.compact = false,
  });

  final IconData icon;
  final String text;
  final Color? color;
  final bool compact;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        icon,
        size: compact ? 16 : 18,
        color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      SizedBox(width: compact ? 3 : 4),
      Text(text, style: TextStyle(fontSize: compact ? 12.5 : null)),
    ],
  );
}
