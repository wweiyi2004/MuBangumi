import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/network/community_service.dart';
import '../state/notify_controller.dart';
import '../state/session_controller.dart';
import '../widgets/friend_qr_actions.dart';
import '../widgets/social_chat_style.dart';
import 'package:flutter/cupertino.dart';
import 'community_hub_page.dart';
import 'friends_page.dart';
import 'notify_page.dart';
import 'pm_page.dart';

class MessagesPage extends ConsumerStatefulWidget {
  const MessagesPage({super.key, this.initialTab = 0, this.communityService});
  final int initialTab;
  final CommunityService? communityService;
  @override
  ConsumerState<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends ConsumerState<MessagesPage> {
  late int _tab = widget.initialTab;
  late final _opened = <int>{widget.initialTab};
  int _friendsRevision = 0;
  @override
  Widget build(BuildContext context) {
    final unread = ref.watch(
      notifyBadgeProvider.select((state) => state.unreadCount),
    );
    return MessageHubLayout(
      selectedTab: _tab,
      unreadCount: unread,
      onScan: () async {
        final added = await scanAndAddFriend(
          context,
          myUsername: ref.read(sessionProvider).user?.username ?? '',
        );
        if (added && mounted) setState(() => _friendsRevision++);
      },
      onSelectTab: (index) => setState(() {
        _tab = index;
        _opened.add(index);
      }),
      onFriends: () async {
        await Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const FriendsPage()));
        if (mounted) setState(() => _friendsRevision++);
      },
      content: IndexedStack(
        index: _tab,
        children: [
          _opened.contains(0)
              ? PmPage(embedded: true, friendsRevision: _friendsRevision)
              : const SizedBox.shrink(),
          _opened.contains(1)
              ? CommunityGroupBrowser(
                  service: widget.communityService,
                  joinedOnly: true,
                )
              : const SizedBox.shrink(),
          _opened.contains(2)
              ? const NotifyPage(embedded: true)
              : const SizedBox.shrink(),
        ],
      ),
    );
  }
}

class MessageHubLayout extends StatelessWidget {
  const MessageHubLayout({
    super.key,
    required this.selectedTab,
    required this.unreadCount,
    required this.onSelectTab,
    required this.onFriends,
    required this.content,
    this.onScan,
  });
  final int selectedTab, unreadCount;
  final ValueChanged<int> onSelectTab;
  final VoidCallback onFriends;
  final Widget content;
  final VoidCallback? onScan;
  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1240),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 0 : 24,
            compact ? 0 : 20,
            compact ? 0 : 24,
            0,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(compact ? 0 : 18),
            ),
            child: ColoredBox(
              color: SocialChatStyle.paper(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
                    child: Row(
                      children: [
                        const Text(
                          '消息',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        if (onScan != null)
                          IconButton(
                            tooltip: '扫一扫',
                            onPressed: onScan,
                            icon: const Icon(
                              CupertinoIcons.qrcode_viewfinder,
                              size: 23,
                            ),
                          ),
                        TextButton.icon(
                          onPressed: onFriends,
                          icon: const Icon(CupertinoIcons.person_2, size: 22),
                          label: const Text('好友'),
                          style: TextButton.styleFrom(
                            foregroundColor: Theme.of(
                              context,
                            ).colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SocialSectionTabs(
                    selected: selectedTab,
                    onSelect: onSelectTab,
                    unread: unreadCount,
                  ),
                  Divider(
                    height: 1,
                    thickness: .6,
                    color: Theme.of(
                      context,
                    ).colorScheme.outlineVariant.withValues(alpha: .5),
                  ),
                  Expanded(child: content),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
