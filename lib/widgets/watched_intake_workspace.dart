import 'package:flutter/material.dart';
import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/network/bangumi_endpoints.dart';
import '../models/bangumi_models.dart';

import '../core/onboarding/watched_guess.dart';
import '../core/theme/anime_icon.dart';
import 'subject_widgets.dart';

/// Warm only the next poster at its actual decode size. Rapid draws replace the
/// queued request instead of launching a download for every intermediate card.
class WatchedIntakePreload extends StatefulWidget {
  const WatchedIntakePreload({
    super.key,
    required this.child,
    this.next,
    this.preload,
  });
  final Widget child;
  final Subject? next;
  final Future<void> Function(ImageProvider, BuildContext)? preload;
  @override
  State<WatchedIntakePreload> createState() => _WatchedIntakePreloadState();
}

class _WatchedIntakePreloadState extends State<WatchedIntakePreload> {
  (String, int, int)? _wanted, _queued;
  bool _busy = false;
  Future<void> _drain() async {
    if (_busy || !mounted) return;
    _busy = true;
    try {
      while (mounted && _queued != null) {
        final next = _queued!;
        _queued = null;
        final provider = ResizeImage.resizeIfNeeded(
          next.$2,
          next.$3,
          CachedNetworkImageProvider(next.$1),
        );
        if (!mounted) return;
        try {
          if (widget.preload case final load?) {
            await load(provider, context);
          } else {
            await precacheImage(provider, context, onError: (_, _) {});
          }
        } catch (_) {
          /* The visible cover retains its own error placeholder. */
        }
      }
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final url = widget.next?.imageUrl ?? '';
      final dpr = MediaQuery.devicePixelRatioOf(context);
      final next =
          !TickerMode.valuesOf(context).enabled ||
              url.isEmpty ||
              !constraints.hasBoundedWidth ||
              !constraints.hasBoundedHeight
          ? null
          : (
              BangumiEndpoints.imageUrl(url, size: BangumiImageSize.large),
              (constraints.maxWidth * dpr).round().clamp(1, 2048),
              (constraints.maxHeight * dpr).round().clamp(1, 2048),
            );
      if (next != _wanted) {
        _wanted = _queued = next;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_drain());
        });
      }
      return widget.child;
    },
  );
}

/// Layout stays in place while the catalog loads or cards change.
class WatchedIntakeWorkspace extends StatelessWidget {
  const WatchedIntakeWorkspace({
    super.key,
    required this.stage,
    required this.remaining,
    required this.kept,
    required this.enriching,
    required this.actions,
    required this.save,
    required this.onReview,
    this.notice,
  });

  final Widget stage, actions, save;
  final int remaining, kept;
  final bool enriching;
  final String? notice;
  final VoidCallback? onReview;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 760;
        final compact =
            constraints.maxHeight < 660 ||
            MediaQuery.textScalerOf(context).scale(14) > 20;
        final header = Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: AnimeIcon(
                Icons.auto_awesome_rounded,
                color: scheme.onPrimaryContainer,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '猜你看过',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (!compact || wide)
                    Text(
                      '把回忆，放回收藏里。',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                ],
              ),
            ),
          ],
        );
        final progress = Row(
          children: [
            if (enriching) ...[
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 1.5),
              ),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Text(
                notice ?? (enriching ? '继续为你找番 · 可以先挑选' : '还有 $remaining 部候选'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        );
        final tray = Material(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: onReview,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  AnimeIcon(
                    Icons.collections_bookmark_outlined,
                    size: 22,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      kept == 0 ? '本次挑选' : '待同步 $kept 部',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (kept > 0) ...[
                    Text(
                      '核对清单',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(width: 4),
                    const AnimeIcon(Icons.chevron_right_rounded, size: 18),
                  ],
                ],
              ),
            ),
          ),
        );
        if (wide) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: 360,
                            maxHeight: 520,
                          ),
                          child: SizedBox.expand(child: stage),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 4,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(12, 24, 28, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          header,
                          const SizedBox(height: 24),
                          Text(
                            '整部看完，或只看到某一集，都可以记下来。没印象的先跳过，误点也能撤销。',
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              height: 1.7,
                            ),
                          ),
                          const SizedBox(height: 24),
                          progress,
                          const SizedBox(height: 14),
                          actions,
                          const SizedBox(height: 24),
                          tray,
                          const SizedBox(height: 12),
                          save,
                          const SizedBox(height: 8),
                          Text(
                            '确认同步前，挑选结果只保留在本次页面。',
                            style: Theme.of(context).textTheme.bodySmall,
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
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              const SizedBox(height: 12),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: SizedBox.expand(child: stage),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              progress,
              const SizedBox(height: 10),
              actions,
              const SizedBox(height: 10),
              tray,
              const SizedBox(height: 8),
              save,
            ],
          ),
        );
      },
    );
  }
}

class WatchedIntakePoster extends StatelessWidget {
  const WatchedIntakePoster({super.key, required this.guess});
  final WatchedGuess guess;

  @override
  Widget build(BuildContext context) {
    final item = guess.candidate;
    final scheme = Theme.of(context).colorScheme;
    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: scheme.shadow.withValues(alpha: .12),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxHeight < 280;
              return Stack(
                fit: StackFit.expand,
                children: [
                  if (item.imageUrl.isNotEmpty)
                    SubjectCover(subject: item.toSubject(), borderRadius: 0)
                  else
                    const _PosterPlaceholder(),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0, .25, .55, 1],
                        colors: [
                          Color(0x33000000),
                          Colors.transparent,
                          Color(0x22000000),
                          Color(0xF01F2029),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 14,
                    left: 14,
                    right: 60,
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (item.year > 0) _PosterTag('${item.year}'),
                        if (item.episodeCount > 0)
                          _PosterTag('${item.episodeCount} 话'),
                        if (!compact && item.score > 0)
                          _PosterTag('★ ${item.score.toStringAsFixed(1)}'),
                      ],
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Padding(
                      padding: EdgeInsets.all(compact ? 14 : 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            item.displayName,
                            maxLines: compact ? 1 : 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: compact ? 18 : 23,
                              height: 1.25,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            guess.reason,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Color(0xFFD7CAD5)),
                          ),
                          if (!compact) ...[
                            const SizedBox(height: 10),
                            const Text(
                              '左滑跳过 · 右滑看过',
                              style: TextStyle(
                                color: Color(0xFFDACED8),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Drag feedback only rebuilds this card, keeping the rest of the page still.
class WatchedIntakeSwipeCard extends StatefulWidget {
  const WatchedIntakeSwipeCard({
    super.key,
    required this.child,
    required this.enabled,
    required this.onKeep,
    required this.onSkip,
  });
  final Widget child;
  final bool enabled;
  final VoidCallback onKeep, onSkip;
  @override
  State<WatchedIntakeSwipeCard> createState() => _WatchedIntakeSwipeCardState();
}

class _WatchedIntakeSwipeCardState extends State<WatchedIntakeSwipeCard> {
  double _drag = 0;
  bool _dragging = false;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onHorizontalDragUpdate: !widget.enabled
        ? null
        : (details) {
            setState(() {
              _dragging = true;
              _drag = (_drag + details.delta.dx).clamp(-120, 120);
            });
          },
    onHorizontalDragCancel: () => setState(() {
      _drag = 0;
      _dragging = false;
    }),
    onHorizontalDragEnd: !widget.enabled
        ? null
        : (_) {
            final distance = _drag;
            final committed = distance.abs() >= 64;
            setState(() {
              _drag = committed ? distance : 0;
              // Hold the release position during the parent's exit animation.
              _dragging = committed;
            });
            if (distance >= 64) widget.onKeep();
            if (distance <= -64) widget.onSkip();
          },
    child: TweenAnimationBuilder<double>(
      tween: Tween(end: _drag),
      duration:
          _dragging ||
              MediaQuery.disableAnimationsOf(context) ||
              MediaQuery.accessibleNavigationOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 160),
      child: RepaintBoundary(child: widget.child),
      builder: (context, distance, child) => Transform.translate(
        offset: Offset(distance, 0),
        child: Transform.rotate(
          angle: distance * .0004,
          child: Stack(
            fit: StackFit.expand,
            children: [
              child!,
              if (distance.abs() > 12)
                Positioned(
                  top: 68,
                  left: 16,
                  right: 16,
                  child: Opacity(
                    opacity: (distance.abs() / 64).clamp(0, 1),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xEEFFFFFF),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          distance > 0 ? '记为看过' : '先跳过',
                          style: const TextStyle(
                            color: Color(0xFF503A49),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class WatchedIntakeLoading extends StatelessWidget {
  const WatchedIntakeLoading({super.key, this.label = '正在找第一部番…'});
  final String label;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(24),
    child: Stack(
      fit: StackFit.expand,
      children: [
        const _PosterPlaceholder(),
        Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 240),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xD9433549),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0x30FFFFFF)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class WatchedIntakeMessage extends StatelessWidget {
  const WatchedIntakeMessage({
    super.key,
    required this.title,
    required this.detail,
    required this.icon,
    required this.actionLabel,
    required this.onAction,
  });
  final String title, detail, actionLabel;
  final IconData icon;
  final VoidCallback onAction;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
      ),
      padding: const EdgeInsets.all(20),
      alignment: Alignment.center,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimeIcon(icon, size: 40, color: scheme.onSurfaceVariant),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, height: 1.6),
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}

class _PosterPlaceholder extends StatelessWidget {
  const _PosterPlaceholder();
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF7B6782), Color(0xFFB8808C), Color(0xFF45445E)],
      ),
    ),
    child: Center(
      child: Transform.rotate(
        angle: -.15,
        child: const AnimeIcon(
          Icons.movie_filter_outlined,
          size: 96,
          color: Color(0x55FFFFFF),
        ),
      ),
    ),
  );
}

class _PosterTag extends StatelessWidget {
  const _PosterTag(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: const Color(0x991F2029),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      label,
      style: const TextStyle(color: Colors.white, fontSize: 12),
    ),
  );
}
