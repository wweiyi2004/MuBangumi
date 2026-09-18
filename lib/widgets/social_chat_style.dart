import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

abstract final class SocialChatStyle {
  static bool dark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;
  static Color paper(BuildContext context) =>
      dark(context) ? const Color(0xFF1D2026) : Colors.white;
  static Color canvas(BuildContext context) =>
      dark(context) ? const Color(0xFF171A20) : const Color(0xFFF4F6F9);
  static Color accent(BuildContext context) =>
      dark(context) ? const Color(0xFF8CC8FF) : const Color(0xFF287BC1);
  static Color ownBubble(BuildContext context) =>
      dark(context) ? const Color(0xFF24445C) : const Color(0xFFDDEFFF);
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
                        borderRadius: BorderRadius.circular(3),
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
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  onTap: onReply,
                  borderRadius: BorderRadius.circular(10),
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
