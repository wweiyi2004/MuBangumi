import '../core/theme/anime_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'community_widgets.dart';
import 'bounded_image.dart';
import 'retained_tab_stack.dart';
import '../core/theme/app_tokens.dart';
import '../core/theme/custom_colors.dart';

class ProfileHomeLayout extends StatelessWidget {
  const ProfileHomeLayout({
    super.key,
    required this.nickname,
    required this.username,
    required this.sign,
    required this.avatarUrl,
    required this.total,
    required this.doing,
    required this.friends,
    required this.selectedTab,
    required this.onSelectTab,
    required this.onSettings,
    required this.onCollections,
    required this.onDoing,
    required this.onFriends,
    required this.content,
    this.coverImage,
    this.feedLabels = const ['我的动态', '好友动态', '日志'],
    this.biography,
  });
  final String nickname, username, sign, avatarUrl;
  final int total, doing, selectedTab;
  final int? friends;
  final ValueChanged<int> onSelectTab;
  final VoidCallback onSettings, onCollections, onDoing, onFriends;
  final Widget content;
  final ImageProvider? coverImage;
  final List<String> feedLabels;
  final Widget? biography;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final compact = MediaQuery.sizeOf(context).width < 600;
    final paper = Theme.of(context).brightness == Brightness.dark
        ? colors.surfaceContainer
        : colors.surface;
    final inset = compact ? 20.0 : 32.0;
    return _ProfileScrollFrame(
      selectedTab: selectedTab,
      username: username,
      buildContent: (nestedKey) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 0 : 24,
              compact ? 0 : 20,
              compact ? 0 : 24,
              0,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(compact ? 0 : 20),
              ),
              child: ColoredBox(
                color: paper,
                child: NestedScrollView(
                  key: nestedKey,
                  headerSliverBuilder: (context, innerScrolled) => [
                    _ProfileHeaderSliver(
                      builder: (context, constraints, extent) {
                        final visibility =
                            (1 - constraints.scrollOffset / extent).clamp(
                              0.0,
                              1.0,
                            );
                        return SliverToBoxAdapter(
                          child: IgnorePointer(
                            ignoring: visibility == 0,
                            child: Opacity(
                              key: const Key('profile-header-fade'),
                              opacity: visibility,
                              child: Stack(
                                children: [
                                  Positioned(
                                    top: 0,
                                    left: 0,
                                    right: 0,
                                    height: 230,
                                    child: ProfileSpaceCover(
                                      image: coverImage,
                                      paper: paper,
                                    ),
                                  ),
                                  Padding(
                                    padding: EdgeInsets.fromLTRB(
                                      inset,
                                      12,
                                      inset,
                                      12,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Row(
                                          children: [
                                            const SizedBox(width: 44),
                                            Expanded(
                                              child: Text(
                                                '我的空间',
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  fontSize: 17,
                                                  fontWeight: FontWeight.w600,
                                                  color: colors.onSurface,
                                                ),
                                              ),
                                            ),
                                            IconButton(
                                              onPressed: onSettings,
                                              tooltip: '设置',
                                              style: IconButton.styleFrom(
                                                backgroundColor: paper
                                                    .withValues(alpha: .66),
                                              ),
                                              icon: const AnimeIcon(
                                                CupertinoIcons.gear_alt,
                                                size: 22,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 46),
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            DecoratedBox(
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: paper,
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.black
                                                        .withValues(alpha: .06),
                                                    blurRadius: 14,
                                                    offset: const Offset(0, 4),
                                                  ),
                                                ],
                                              ),
                                              child: Padding(
                                                padding: const EdgeInsets.all(
                                                  4,
                                                ),
                                                child: CommunityAvatar(
                                                  imageUrl: avatarUrl,
                                                  radius: compact ? 38 : 44,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 16),
                                            Expanded(
                                              child: Padding(
                                                padding: const EdgeInsets.only(
                                                  bottom: 8,
                                                ),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      nickname,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        fontSize: 25,
                                                        height: 1.3,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 5),
                                                    Text(
                                                      '@$username',
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        fontSize:
                                                            AppText.caption,
                                                        color: colors
                                                            .onSurfaceVariant,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (sign.isNotEmpty) ...[
                                          const SizedBox(height: 14),
                                          Text(
                                            sign,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 14,
                                              height: 1.6,
                                              color: colors.onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                        ?biography,
                                        const SizedBox(height: 10),
                                        Row(
                                          children: [
                                            _Stat(
                                              value: '$total',
                                              label: '收藏',
                                              onTap: onCollections,
                                            ),
                                            _Stat(
                                              value: '$doing',
                                              label: '进行中',
                                              onTap: onDoing,
                                            ),
                                            _Stat(
                                              value: friends?.toString() ?? '—',
                                              label: '好友',
                                              onTap: onFriends,
                                            ),
                                          ],
                                        ),
                                      ],
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
                  body: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      PersonalFeedTabs(
                        labels: feedLabels,
                        selected: selectedTab,
                        onSelect: onSelectTab,
                      ),
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: inset),
                          child: content,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Measure the header's previous layout so introductions and large text cannot
/// make its remaining visible controls disappear before the header leaves view.
class _ProfileHeaderSliver extends StatefulWidget {
  const _ProfileHeaderSliver({required this.builder});
  final Widget Function(BuildContext, SliverConstraints, double) builder;
  @override
  State<_ProfileHeaderSliver> createState() => _ProfileHeaderSliverState();
}

class _ProfileHeaderSliverState extends State<_ProfileHeaderSliver> {
  final _sliver = GlobalKey();
  @override
  Widget build(BuildContext context) => SliverLayoutBuilder(
    builder: (context, constraints) {
      final render =
          _sliver.currentContext?.findRenderObject() as RenderSliver?;
      final extent = render?.geometry?.scrollExtent ?? 400;
      return KeyedSubtree(
        key: _sliver,
        child: widget.builder(context, constraints, extent > 0 ? extent : 400),
      );
    },
  );
}

class _ProfileScrollFrame extends StatefulWidget {
  const _ProfileScrollFrame({
    required this.selectedTab,
    required this.username,
    required this.buildContent,
  });
  final int selectedTab;
  final String username;
  final Widget Function(GlobalKey<NestedScrollViewState>) buildContent;
  @override
  State<_ProfileScrollFrame> createState() => _ProfileScrollFrameState();
}

class _ProfileScrollFrameState extends State<_ProfileScrollFrame> {
  final _nested = GlobalKey<NestedScrollViewState>();
  bool _showTop = false, _returning = false;
  void _updateVisibility() {
    if (!mounted) return;
    final nested = _nested.currentState;
    final outer = nested?.outerController.positions;
    final inner = nested?.innerController.positions;
    final offset =
        (outer?.fold<double>(0, (m, p) => p.pixels > m ? p.pixels : m) ?? 0) +
        (inner?.fold<double>(0, (m, p) => p.pixels > m ? p.pixels : m) ?? 0);
    final show = offset > 240;
    if (_showTop != show) setState(() => _showTop = show);
  }

  @override
  void didUpdateWidget(covariant _ProfileScrollFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedTab != widget.selectedTab ||
        oldWidget.username != widget.username) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _updateVisibility());
    }
  }

  Future<void> _toTop() async {
    final nested = _nested.currentState;
    if (_returning || nested == null || !nested.outerController.hasClients) {
      return;
    }
    setState(() => _returning = true);
    try {
      // NestedScrollPosition delegates this animation to both the outer header
      // and the currently attached inner feed, retaining the other feed offsets.
      await nested.outerController.animateTo(
        0,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    } finally {
      if (mounted) {
        setState(() => _returning = false);
        _updateVisibility();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      fit: StackFit.expand,
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n.metrics.axis == Axis.vertical &&
                n.depth <= 1 &&
                (n is ScrollUpdateNotification || n is ScrollEndNotification)) {
              _updateVisibility();
            }
            return false;
          },
          child: widget.buildContent(_nested),
        ),
        Positioned(
          right: MediaQuery.sizeOf(context).width < 600 ? 16 : 24,
          bottom: 96,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: _showTop
                ? SizedBox.square(
                    dimension: 48,
                    child: FloatingActionButton.small(
                      key: const ValueKey('profile-back-to-top'),
                      heroTag: null,
                      tooltip: '回到顶部',
                      elevation: 0,
                      hoverElevation: 0,
                      focusElevation: 0,
                      highlightElevation: 0,
                      shape: const CircleBorder(),
                      backgroundColor: scheme.primary,
                      foregroundColor: scheme.onPrimary,
                      onPressed: _returning ? null : _toTop,
                      child: const AnimeIcon(
                        Icons.arrow_upward_rounded,
                        size: 22,
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }
}

class ProfileSpaceCover extends StatelessWidget {
  const ProfileSpaceCover({super.key, this.image, required this.paper});
  final ImageProvider? image;
  final Color paper;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accessible = MediaQuery.highContrastOf(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: accessible
                  ? [paper, paper]
                  : Theme.of(context).extension<BrandColors>() != null
                  ? [
                      Theme.of(context).colorScheme.primaryContainer,
                      Theme.of(context).colorScheme.secondaryContainer,
                      paper,
                    ]
                  : dark
                  ? [...AppPalette.profileHeaderDark, paper]
                  : AppPalette.profileHeaderLight,
            ),
          ),
        ),
        if (!accessible && image != null)
          Image(
            image: boundedImageProvider(
              image!,
              width: MediaQuery.sizeOf(context).width.clamp(1, 820),
              height: 230,
              pixelRatio: MediaQuery.devicePixelRatioOf(context),
            ),
            fit: BoxFit.cover,
            excludeFromSemantics: true,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        if (!accessible && image == null)
          CustomPaint(
            painter: _CoverLines(
              dark
                  ? Colors.white.withValues(alpha: .08)
                  : Colors.white.withValues(alpha: .5),
            ),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0, .3, .65, 1],
              colors: [
                paper.withValues(alpha: .35),
                paper.withValues(alpha: .15),
                paper.withValues(alpha: .65),
                paper,
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The same soft cover and identity treatment as the personal space, with one feed.
class PublicSpaceHeader extends StatelessWidget {
  const PublicSpaceHeader({
    super.key,
    required this.nickname,
    required this.username,
    required this.avatarUrl,
    this.sign = '',
    this.biography,
    this.footer,
    this.loading = false,
  });
  final String nickname, username, avatarUrl, sign;
  final Widget? biography, footer;
  final bool loading;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 210,
            child: ProfileSpaceCover(paper: scheme.surface),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 48, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.surface,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: scheme.shadow.withValues(alpha: .08),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: CommunityAvatar(imageUrl: avatarUrl, radius: 38),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            nickname,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '@$username',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (sign.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(
                    sign,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
                ?biography,
                if (footer != null) ...[const SizedBox(height: 8), footer!],
                if (loading) ...[
                  const SizedBox(height: 10),
                  const LinearProgressIndicator(minHeight: 2),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CoverLines extends CustomPainter {
  const _CoverLines(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (var i = 0; i < 6; i++) {
      final y = 20.0 + i * 21;
      canvas.drawPath(
        Path()
          ..moveTo(-30, y + 50)
          ..cubicTo(
            size.width * .2,
            y - 65,
            size.width * .42,
            y + 110,
            size.width * .67,
            y + 10,
          )
          ..quadraticBezierTo(size.width * .9, y - 55, size.width + 30, y + 15),
        paint,
      );
    }
    canvas.drawCircle(
      Offset(size.width * .83, 62),
      26,
      Paint()..color = color.withValues(alpha: .25),
    );
  }

  @override
  bool shouldRepaint(_CoverLines oldDelegate) => oldDelegate.color != color;
}

/// Keeps each feed mounted, but only the visible feed joins the outer scroll.
/// Switching between nested and standalone positions needs an explicit offset
/// restore: those two position types cannot absorb each other's saved pixels.
class ProfileFeedStack extends StatelessWidget {
  const ProfileFeedStack({
    super.key,
    required this.index,
    required this.children,
  });
  final int index;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => RetainedTabStack(
    index: index,
    children: [
      for (var i = 0; i < children.length; i++)
        _RememberedFeedScroll(active: i == index, child: children[i]),
    ],
  );
}

class _RememberedFeedScroll extends StatefulWidget {
  const _RememberedFeedScroll({required this.active, required this.child});
  final bool active;
  final Widget child;

  @override
  State<_RememberedFeedScroll> createState() => _RememberedFeedScrollState();
}

class _RememberedFeedScrollState extends State<_RememberedFeedScroll> {
  double _offset = 0;

  @override
  void didUpdateWidget(covariant _RememberedFeedScroll oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active && _offset > 0) {
      final target = _offset;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !widget.active) return;
        final controller = PrimaryScrollController.maybeOf(context);
        if (controller == null || controller.positions.length != 1) return;
        controller.jumpTo(
          target.clamp(0.0, controller.position.maxScrollExtent),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (widget.active &&
              notification.depth == 0 &&
              notification.metrics.axis == Axis.vertical &&
              notification is ScrollUpdateNotification) {
            _offset = notification.metrics.pixels.clamp(0.0, double.infinity);
          }
          return false;
        },
        child: widget.child,
      );
}

class PersonalFeedTabs extends StatelessWidget {
  const PersonalFeedTabs({
    super.key,
    required this.selected,
    required this.onSelect,
    this.labels = const ['我的动态', '好友动态', '日志'],
  });
  final int selected;
  final ValueChanged<int> onSelect;
  final List<String> labels;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    const icons = [
      CupertinoIcons.chat_bubble,
      CupertinoIcons.person_2,
      CupertinoIcons.book,
      CupertinoIcons.list_bullet,
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: colors.outlineVariant.withValues(alpha: .4),
            width: .7,
          ),
        ),
      ),
      child: Row(
        children: [
          for (final (index, label) in labels.indexed)
            Expanded(
              child: Semantics(
                selected: selected == index,
                button: true,
                child: InkWell(
                  onTap: () => onSelect(index),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 12, 4, 7),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimeIcon(
                          icons[index % icons.length],
                          size: 25,
                          color: selected == index
                              ? colors.onSurface
                              : colors.onSurfaceVariant,
                        ),
                        const SizedBox(height: 7),
                        Text(
                          label,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: selected == index
                                ? FontWeight.w700
                                : FontWeight.w400,
                            color: selected == index
                                ? colors.onSurface
                                : colors.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Container(
                          width: 18,
                          height: 3,
                          decoration: BoxDecoration(
                            color: selected == index
                                ? colors.primary
                                : Colors.transparent,
                            borderRadius: AppRadius.round,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, required this.onTap});
  final String value, label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Expanded(
    child: InkWell(
      onTap: onTap,
      borderRadius: AppRadius.small,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 3),
        child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 5,
          runSpacing: 2,
          children: [
            Text(
              value,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: AppText.caption,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
