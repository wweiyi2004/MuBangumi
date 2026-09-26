import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

import '../../../core/network/bangumi_endpoints.dart';
import '../../../core/network/bangumi_smiles.dart';
import '../../../models/community_models.dart';

class CommunityPostActions extends StatelessWidget {
  const CommunityPostActions({
    super.key,
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
