import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/network/bangumi_endpoints.dart';
import '../models/bangumi_models.dart';

class SubjectCover extends StatelessWidget {
  const SubjectCover({
    super.key,
    required this.subject,
    this.width,
    this.height,
    this.borderRadius = 16,
    this.size = BangumiImageSize.large,
  });

  final Subject subject;
  final double? width;
  final double? height;
  final double borderRadius;
  final BangumiImageSize size;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        // Poster cards provide dimensions through layout, not explicit fields.
        final displayWidth =
            width ??
            (constraints.hasBoundedWidth ? constraints.maxWidth : null);
        final displayHeight =
            height ??
            (constraints.hasBoundedHeight ? constraints.maxHeight : null);
        int? pixels(double? logical) =>
            logical != null && logical.isFinite && logical > 0
            ? (logical * dpr).round().clamp(1, 4096)
            : null;
        final cacheWidth = pixels(displayWidth);
        final cacheHeight = pixels(displayHeight);
        return ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          child: ColoredBox(
            color: Theme.of(context).colorScheme.surfaceContainer,
            child: subject.imageUrl.isEmpty
                ? SizedBox(
                    width: width,
                    height: height,
                    child: const Center(
                      child: Icon(Icons.movie_filter_outlined, size: 34),
                    ),
                  )
                : CachedNetworkImage(
                    imageUrl: BangumiEndpoints.imageUrl(
                      subject.imageUrl,
                      size: size,
                    ),
                    width: width,
                    height: height,
                    fit: BoxFit.cover,
                    // Decode to display size only — full-res covers were a major jank source.
                    memCacheWidth: cacheWidth,
                    memCacheHeight: cacheHeight,
                    fadeInDuration: Duration.zero,
                    fadeOutDuration: Duration.zero,
                    placeholder: (_, _) => SizedBox(
                      width: width,
                      height: height,
                      child: ColoredBox(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                      ),
                    ),
                    errorWidget: (_, _, _) => SizedBox(
                      width: width,
                      height: height,
                      child: const Center(
                        child: Icon(Icons.broken_image_outlined),
                      ),
                    ),
                  ),
          ),
        );
      },
    );
  }
}

IconData subjectTypeIcon(SubjectType type) => switch (type) {
  SubjectType.book => Icons.menu_book_rounded,
  SubjectType.anime => Icons.movie_filter_rounded,
  SubjectType.music => Icons.music_note_rounded,
  SubjectType.game => Icons.sports_esports_rounded,
  SubjectType.real => Icons.live_tv_rounded,
};

class SubjectTypeBadge extends StatelessWidget {
  const SubjectTypeBadge({super.key, required this.type});

  final SubjectType type;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(subjectTypeIcon(type), size: 13, color: scheme.onSurfaceVariant),
          const SizedBox(width: 3),
          Text(
            type.label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

int subjectPosterColumnCount(double width) {
  if (width >= 1120) return 6;
  if (width >= 900) return 5;
  if (width >= 660) return 4;
  if (width >= 430) return 3;
  return 2;
}

double subjectPosterItemHeight(
  double width,
  int columns, {
  double spacing = 12,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  final itemWidth = (width - spacing * (columns - 1)) / columns;
  return itemWidth / .72 + _posterFooterHeight(textScaler);
}

double _posterFooterHeight(TextScaler textScaler) =>
    textScaler.scale(14) * 2 * 1.25 +
    math.max(30, textScaler.scale(11) * 1.5) +
    15;

/// Image-first media card used by the home and discovery feeds.
///
/// The actions intentionally stay on the card so the denser layout does not
/// trade away MuBangumi's quick episode workflow.
class SubjectPosterCard extends StatelessWidget {
  const SubjectPosterCard({
    super.key,
    required this.subject,
    required this.onTap,
    this.collection,
    this.onNextEpisode,
    this.onEpisodeGrid,
    this.busy = false,
    this.statusLabel,
    this.metaLabel,
  });

  final Subject subject;
  final UserCollection? collection;
  final VoidCallback onTap;
  final VoidCallback? onNextEpisode;
  final VoidCallback? onEpisodeGrid;
  final bool busy;
  final String? statusLabel;
  final String? metaLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final progress = _progressValue(subject, collection);
    final defaultStatus = collection == null
        ? subject.rank > 0
              ? '#${subject.rank}'
              : subject.type.label
        : _progressText(subject, collection);
    final status = statusLabel ?? defaultStatus;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: .72,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    SubjectCover(subject: subject, borderRadius: 0),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: [0, .55, 1],
                          colors: [
                            Color(0x24000000),
                            Colors.transparent,
                            Color(0xB8000000),
                          ],
                        ),
                      ),
                    ),
                    if (subject.score > 0)
                      Positioned(
                        right: 8,
                        top: 8,
                        child: _PosterBadge(
                          icon: Icons.star_rounded,
                          label: subject.score.toStringAsFixed(1),
                          iconColor: const Color(0xFFFFD166),
                        ),
                      ),
                    Positioned(
                      left: 10,
                      right: onNextEpisode == null ? 10 : 52,
                      bottom: 11,
                      child: Text(
                        status,
                        maxLines:
                            MediaQuery.textScalerOf(context).scale(12) > 16
                            ? 2
                            : 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              shadows: const [
                                Shadow(color: Colors.black54, blurRadius: 6),
                              ],
                            ),
                      ),
                    ),
                    if (onNextEpisode != null)
                      Positioned(
                        right: 8,
                        bottom: 7,
                        child: IconButton.filled(
                          tooltip: '看完下一集',
                          style: IconButton.styleFrom(
                            backgroundColor: scheme.primary,
                            foregroundColor: scheme.onPrimary,
                            minimumSize: const Size.square(38),
                            maximumSize: const Size.square(38),
                            padding: EdgeInsets.zero,
                          ),
                          onPressed: busy ? null : onNextEpisode,
                          icon: busy
                              ? const SizedBox.square(
                                  dimension: 15,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.add_rounded, size: 21),
                        ),
                      ),
                    if (progress != null)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 3,
                          color: scheme.primary,
                          backgroundColor: Colors.white24,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            SizedBox(
              height: _posterFooterHeight(MediaQuery.textScalerOf(context)),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(2, 9, 0, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        subject.displayName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          height: 1.25,
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            metaLabel ??
                                (collection == null
                                    ? _posterMeta(subject)
                                    : collection!.type.labelFor(subject.type)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ),
                        if (onEpisodeGrid != null)
                          IconButton(
                            tooltip: '点格子',
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints.tightFor(
                              width: 34,
                              height: 30,
                            ),
                            padding: EdgeInsets.zero,
                            onPressed: busy ? null : onEpisodeGrid,
                            icon: const Icon(Icons.grid_view_rounded, size: 17),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PosterBadge extends StatelessWidget {
  const _PosterBadge({
    required this.icon,
    required this.label,
    this.iconColor = Colors.white,
  });

  final IconData icon;
  final String label;
  final Color iconColor;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0x990D0D14),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: iconColor),
          const SizedBox(width: 3),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    ),
  );
}

String _posterMeta(Subject subject) {
  if (subject.ratingTotal > 0) return '${subject.ratingTotal} 人评分';
  if (subject.date.isNotEmpty) return subject.date;
  return subject.type.label;
}

class SubjectPosterGrid extends StatelessWidget {
  const SubjectPosterGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const spacing = 12.0;
      final columns = subjectPosterColumnCount(constraints.maxWidth);
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        addAutomaticKeepAlives: false,
        addRepaintBoundaries: true,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisExtent: subjectPosterItemHeight(
            constraints.maxWidth,
            columns,
            spacing: spacing,
            textScaler: MediaQuery.textScalerOf(context),
          ),
          mainAxisSpacing: spacing,
          crossAxisSpacing: spacing,
        ),
        itemCount: itemCount,
        itemBuilder: itemBuilder,
      );
    },
  );
}

class SubjectTile extends StatelessWidget {
  const SubjectTile({
    super.key,
    required this.subject,
    required this.onTap,
    this.collection,
    this.onNextEpisode,
    this.onEpisodeGrid,
    this.busy = false,
    this.showTypeBadge = true,
  });

  final Subject subject;
  final UserCollection? collection;
  final VoidCallback onTap;
  final VoidCallback? onNextEpisode;
  final VoidCallback? onEpisodeGrid;
  final bool busy;
  final bool showTypeBadge;

  @override
  Widget build(BuildContext context) {
    final progressText = _progressText(subject, collection);
    final progress = _progressValue(subject, collection);
    final showProgressBar = collection != null && progress != null;
    final scheme = Theme.of(context).colorScheme;
    final narrow = MediaQuery.sizeOf(context).width < 400;
    // Fixed content height matches cover so Spacer works in ListView items
    // (unbounded list height + Spacer otherwise throws).
    final coverHeight = narrow ? 92.0 : 104.0;
    final coverWidth = narrow ? 66.0 : 74.0;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(narrow ? 8 : 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SubjectCover(
                subject: subject,
                width: coverWidth,
                height: coverHeight,
                borderRadius: 12,
                size: BangumiImageSize.common,
              ),
              SizedBox(width: narrow ? 8 : 12),
              Expanded(
                child: SizedBox(
                  height: coverHeight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        subject.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontSize: narrow ? 15 : null),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (showTypeBadge) ...[
                            SubjectTypeBadge(type: subject.type),
                            const SizedBox(width: 6),
                          ],
                          if (collection != null)
                            Flexible(
                              child: Text(
                                collection!.type.labelFor(subject.type),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      color: scheme.primary,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            )
                          else if (subject.nameCn.isNotEmpty &&
                              subject.name.isNotEmpty)
                            Expanded(
                              child: Text(
                                subject.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                            ),
                        ],
                      ),
                      const Spacer(),
                      if (collection != null) ...[
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                progressText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelMedium
                                    ?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                            ),
                            if (subject.score > 0) ...[
                              const Icon(
                                Icons.star_rounded,
                                color: Color(0xFFF3A646),
                                size: 16,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                subject.score.toStringAsFixed(1),
                                style: Theme.of(context).textTheme.labelMedium,
                              ),
                            ],
                            if (collection!.rate > 0 && !narrow) ...[
                              const SizedBox(width: 6),
                              Text(
                                '我的 ${collection!.rate}',
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      color: scheme.onSecondaryContainer,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ],
                          ],
                        ),
                        if (showProgressBar) ...[
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 5,
                              backgroundColor: scheme.surfaceContainer,
                            ),
                          ),
                        ],
                      ] else ...[
                        Row(
                          children: [
                            if (subject.score > 0) ...[
                              const Icon(
                                Icons.star_rounded,
                                color: Color(0xFFF3A646),
                                size: 17,
                              ),
                              const SizedBox(width: 3),
                              Text(subject.score.toStringAsFixed(1)),
                            ],
                            if (subject.ratingTotal > 0) ...[
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  '${subject.ratingTotal}人',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: scheme.onSurfaceVariant,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                            if (subject.rank > 0) ...[
                              const SizedBox(width: 8),
                              Text(
                                '#${subject.rank}',
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (onEpisodeGrid != null || onNextEpisode != null) ...[
                SizedBox(width: narrow ? 2 : 6),
                SizedBox(
                  height: coverHeight,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (onEpisodeGrid != null)
                        IconButton.outlined(
                          tooltip: '点格子',
                          visualDensity: VisualDensity.compact,
                          onPressed: busy ? null : onEpisodeGrid,
                          icon: Icon(
                            Icons.grid_view_rounded,
                            size: narrow ? 16 : 18,
                          ),
                        ),
                      if (onNextEpisode != null) ...[
                        SizedBox(height: narrow ? 0 : 2),
                        IconButton.filledTonal(
                          tooltip: '看完下一集',
                          visualDensity: VisualDensity.compact,
                          onPressed: busy ? null : onNextEpisode,
                          icon: busy
                              ? const SizedBox.square(
                                  dimension: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(Icons.add_rounded, size: narrow ? 16 : 18),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String _progressText(Subject subject, UserCollection? collection) {
  if (collection == null) return '';
  final type = subject.type;
  if (type.hasEpisodes) {
    final watched = collection.episodeStatus;
    final total = subject.episodeCount;
    return total > 0 ? '看到 $watched / $total' : '已看 $watched 集';
  }
  if (type.hasVolumes) {
    final read = collection.volumeStatus;
    final total = subject.volumeCount;
    return total > 0 ? '读到 $read / $total 卷' : '已读 $read 卷';
  }
  return collection.type.labelFor(type);
}

double? _progressValue(Subject subject, UserCollection? collection) {
  if (collection == null) return null;
  if (subject.type.hasEpisodes && subject.episodeCount > 0) {
    return (collection.episodeStatus / subject.episodeCount).clamp(0.0, 1.0);
  }
  if (subject.type.hasVolumes && subject.volumeCount > 0) {
    return (collection.volumeStatus / subject.volumeCount).clamp(0.0, 1.0);
  }
  return null;
}

class SubjectGrid extends StatelessWidget {
  const SubjectGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 1050
          ? 3
          : constraints.maxWidth >= 640
          ? 2
          : 1;
      final narrow = constraints.maxWidth < 400;
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        addAutomaticKeepAlives: false,
        addRepaintBoundaries: true,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisExtent: narrow ? 116 : 128,
          mainAxisSpacing: narrow ? 10 : 14,
          crossAxisSpacing: narrow ? 10 : 14,
        ),
        itemCount: itemCount,
        itemBuilder: itemBuilder,
      );
    },
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 46, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 14),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          if (action != null) ...[const SizedBox(height: 18), action!],
        ],
      ),
    ),
  );
}

void showAppMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
