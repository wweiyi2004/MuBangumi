import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../core/theme/app_tokens.dart';

/// Chat, group and notification surfaces. Everything derives from the app
/// theme so messages share the brand accent with the rest of MuBangumi.
abstract final class SocialChatStyle {
  static bool dark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;
  static ColorScheme _scheme(BuildContext context) =>
      Theme.of(context).colorScheme;
  static Color paper(BuildContext context) => dark(context)
      ? _scheme(context).surfaceContainer
      : _scheme(context).surface;
  static Color canvas(BuildContext context) => dark(context)
      ? _scheme(context).surfaceContainerLow
      : _scheme(context).surfaceContainer;
  static Color accent(BuildContext context) => _scheme(context).primary;
  // A tint rather than primaryContainer keeps body text on its usual color.
  static Color ownBubble(BuildContext context) => Color.alphaBlend(
    accent(context).withValues(alpha: dark(context) ? .22 : .12),
    paper(context),
  );
}

class SocialSectionTabs extends StatelessWidget {
  const SocialSectionTabs({
    super.key,
    required this.selected,
    required this.onSelect,
    this.unread = 0,
  });
  final int selected, unread;
  final ValueChanged<int> onSelect;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final (index, label, icon) in const [
        (0, '私聊', CupertinoIcons.chat_bubble_2),
        (1, '小组', CupertinoIcons.person_3),
        (2, '通知', CupertinoIcons.bell),
      ])
        Expanded(
          child: Semantics(
            selected: index == selected,
            button: true,
            child: InkWell(
              onTap: () => onSelect(index),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 12, 6, 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Badge(
                          isLabelVisible: index == 2 && unread > 0,
                          label: Text(unread > 99 ? '99+' : '$unread'),
                          child: Icon(
                            icon,
                            size: 21,
                            color: index == selected
                                ? SocialChatStyle.accent(context)
                                : Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            label,
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: index == selected
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                              color: index == selected
                                  ? SocialChatStyle.accent(context)
                                  : Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: 22,
                      height: 3,
                      decoration: BoxDecoration(
                        color: index == selected
                            ? SocialChatStyle.accent(context)
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
  );
}

class DiscussionReplyBar extends StatelessWidget {
  const DiscussionReplyBar({super.key, required this.onReply});
  final VoidCallback onReply;
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: SocialChatStyle.paper(context),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Material(
                color: SocialChatStyle.canvas(context),
                borderRadius: AppRadius.small,
                child: InkWell(
                  onTap: onReply,
                  borderRadius: AppRadius.small,
                  child: Padding(
                    padding: const EdgeInsets.all(13),
                    child: Text(
                      '参与这场讨论…',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            TextButton(
              onPressed: onReply,
              style: TextButton.styleFrom(
                foregroundColor: SocialChatStyle.accent(context),
              ),
              child: const Text('回复'),
            ),
          ],
        ),
      ),
    ),
  );
}
