import 'package:flutter/material.dart';
import '../../core/theme/app_tokens.dart';

/// Lays out [top] at its own height (scrolling if it is taller than the
/// space) and gives [below] whatever height remains, hiding it when that is
/// less than [minBelow]. The controls never scroll to make room for it.
class FillBelow extends StatelessWidget {
  const FillBelow({
    super.key,
    required this.top,
    required this.below,
    this.minBelow = 96,
  });
  final Widget top, below;
  final double minBelow;

  @override
  Widget build(BuildContext context) => CustomMultiChildLayout(
    delegate: _FillBelowDelegate(minBelow),
    children: [
      LayoutId(id: #top, child: top),
      LayoutId(id: #below, child: below),
    ],
  );
}

class _FillBelowDelegate extends MultiChildLayoutDelegate {
  _FillBelowDelegate(this.minBelow);
  final double minBelow;

  @override
  void performLayout(Size size) {
    final top = layoutChild(#top, BoxConstraints.loose(size));
    positionChild(#top, Offset.zero);
    final rest = size.height - top.height;
    final show = rest >= minBelow;
    layoutChild(
      #below,
      BoxConstraints.tight(Size(size.width, show ? rest : 0)),
    );
    positionChild(#below, Offset(0, show ? top.height : size.height));
  }

  @override
  bool shouldRelayout(_FillBelowDelegate old) => old.minBelow != minBelow;
}

/// The newest few visible comments of the current round, newest first.
class RoomCommentPreview extends StatelessWidget {
  const RoomCommentPreview({
    super.key,
    required this.round,
    required this.onOpenWall,
  });
  final Map<String, dynamic>? round;
  final VoidCallback onOpenWall;

  @override
  Widget build(BuildContext context) {
    final r = round;
    final open = (r?['commentsOpen'] ?? r?['publicComments']) == true;
    final comments = ((r?['comments'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .where((c) => c['hidden'] != true || c['mine'] == true)
        .toList()
        .reversed
        .toList();
    // FillBelow gives no height when there is no room; draw nothing then.
    return LayoutBuilder(
      builder: (context, box) => box.maxHeight < 1
          ? const SizedBox.shrink()
          : _body(context, open, comments),
    );
  }

  Widget _body(
    BuildContext context,
    bool open,
    List<Map<String, dynamic>> comments,
  ) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  open ? '大家的短评' : '我的短评',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (comments.isNotEmpty)
                TextButton(onPressed: onOpenWall, child: const Text('查看全部')),
            ],
          ),
          if (!open)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.lock_outline_rounded,
                    size: 16,
                    color: colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '评分后即可看到大家的短评',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: comments.isEmpty
                ? Align(
                    alignment: Alignment.topLeft,
                    child: Text(
                      '还没有短评，写下第一句吧',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  )
                // Fade the cut-off edge so a clipped card reads as "more".
                : ShaderMask(
                    blendMode: BlendMode.dstIn,
                    shaderCallback: (bounds) => LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: const [Colors.black, Colors.transparent],
                      stops: [(1 - 28 / bounds.height).clamp(0.0, 1.0), 1],
                    ).createShader(bounds),
                    child: ListView.separated(
                      key: const ValueKey('participant-comment-preview'),
                      padding: EdgeInsets.zero,
                      itemCount: comments.length.clamp(0, 20),
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final c = comments[i];
                        return DecoratedBox(
                          decoration: BoxDecoration(
                            color: colors.surfaceContainer,
                            borderRadius: AppRadius.medium,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (c['mine'] == true)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Text(
                                      c['hidden'] == true ? '我 · 已被隐藏' : '我',
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                            color: colors.onSurfaceVariant,
                                          ),
                                    ),
                                  ),
                                Text(
                                  c['text'] as String,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
