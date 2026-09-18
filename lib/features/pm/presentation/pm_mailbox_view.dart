import 'package:flutter/material.dart';
import '../../../models/pm_models.dart';
import '../../../state/pm_mailbox_controller.dart';
import '../../../widgets/community_loading.dart';
import 'pm_avatar.dart';
import '../../../widgets/social_chat_style.dart';

class PmSegmentedTabs extends StatelessWidget {
  const PmSegmentedTabs({
    super.key,
    required this.index,
    required this.inboxCount,
    required this.outboxCount,
    required this.unread,
    required this.onChanged,
  });

  final int index;
  final int inboxCount;
  final int outboxCount;
  final int unread;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: SocialChatStyle.canvas(context),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: _seg(
              context,
              selected: index == 0,
              label: '收到',
              count: inboxCount,
              badge: unread,
              onTap: () => onChanged(0),
            ),
          ),
          Expanded(
            child: _seg(
              context,
              selected: index == 1,
              label: '发出',
              count: outboxCount,
              onTap: () => onChanged(1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _seg(
    BuildContext context, {
    required bool selected,
    required String label,
    required int count,
    int badge = 0,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? SocialChatStyle.paper(context) : Colors.transparent,
      elevation: 0,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? SocialChatStyle.accent(context)
                      : scheme.onSurfaceVariant,
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 6),
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: selected
                        ? SocialChatStyle.accent(context).withValues(alpha: .8)
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (badge > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: SocialChatStyle.accent(context),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    badge > 99 ? '99+' : '$badge',
                    style: TextStyle(
                      color: SocialChatStyle.dark(context)
                          ? Colors.black
                          : Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
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

class PmListBody extends StatelessWidget {
  const PmListBody({
    super.key,
    required this.mailbox,
    required this.emptyLabel,
    required this.emptyHint,
    required this.onRetry,
    required this.onSyncLogin,
    required this.onOpenWeb,
    required this.onOpen,
    required this.onRefresh,
    this.selectedId,
    this.query = '',
  });

  final PmMailboxController mailbox;
  final String emptyLabel;
  final String emptyHint;
  final Future<void> Function() onRetry;
  final Future<void> Function() onSyncLogin;
  final Future<void> Function() onOpenWeb;
  final Future<void> Function(PmConversation) onOpen;
  final Future<void> Function() onRefresh;
  final String? selectedId;
  final String query;

  @override
  Widget build(BuildContext context) {
    final term = query.trim().toLowerCase();
    final items = mailbox.items
        .where(
          (item) =>
              term.isEmpty ||
              '${item.peerName} ${item.title} ${item.preview}'
                  .toLowerCase()
                  .contains(term),
        )
        .toList();
    final loading = mailbox.refreshing;
    final error = mailbox.error;
    final needAuth = mailbox.needAuth;
    if (loading && items.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.4));
    }
    if (needAuth) {
      return _PmStateCard(
        icon: Icons.lock_person_rounded,
        title: '需要补充账号验证',
        message: error ?? '收藏账号已保留，完成验证后即可继续聊天。',
        primaryLabel: '登录后继续',
        primaryIcon: Icons.login_rounded,
        onPrimary: onSyncLogin,
        secondaryLabel: '改用网页版',
        onSecondary: onOpenWeb,
      );
    }
    if (error != null && items.isEmpty) {
      return _PmStateCard(
        icon: Icons.cloud_off_rounded,
        title: '加载失败',
        message: error,
        primaryLabel: '重试',
        primaryIcon: Icons.refresh_rounded,
        onPrimary: onRetry,
        secondaryLabel: '打开网页版',
        onSecondary: onOpenWeb,
      );
    }
    if (mailbox.items.isEmpty) {
      return _PmStateCard(
        icon: Icons.mail_outline_rounded,
        title: emptyLabel,
        message: emptyHint,
        primaryLabel: '刷新',
        primaryIcon: Icons.refresh_rounded,
        onPrimary: onRefresh,
      );
    }

    return Column(
      children: [
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text('已加载会话中没有匹配结果'),
          ),
        CommunityRefreshStatus(
          loading: loading,
          error: error,
          onRetry: onRetry,
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: onRefresh,
            child: ListView.separated(
              key: PageStorageKey(mailbox),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(8, 2, 8, 88),
              itemCount: items.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: 2),
              itemBuilder: (context, index) {
                if (index == items.length) {
                  return CommunityLoadMoreFooter(
                    loading: mailbox.loadingMore,
                    hasMore: mailbox.hasMore,
                    error: mailbox.moreError,
                    onLoad: loading ? null : mailbox.loadMore,
                  );
                }
                final item = items[index];
                return _PmConversationTile(
                  item: item,
                  selected: item.id == selectedId,
                  onTap: () => onOpen(item),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _PmConversationTile extends StatelessWidget {
  const _PmConversationTile({
    required this.item,
    required this.onTap,
    this.selected = false,
  });

  final PmConversation item;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? SocialChatStyle.accent(context).withValues(alpha: .09)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Semantics(
          selected: selected,
          label: item.isUnread ? '未读会话' : null,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Badge(
                  isLabelVisible: item.isUnread,
                  backgroundColor: scheme.error,
                  child: PmAvatar(
                    url: item.avatarUrl,
                    name: item.peerName,
                    radius: 23,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.peerName.isEmpty
                                  ? item.title
                                  : item.peerName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (item.timeText.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 90),
                              child: Text(
                                item.timeText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          if (item.title.isNotEmpty &&
                              item.title != item.peerName)
                            Flexible(
                              child: Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          if (item.preview.isNotEmpty) ...[
                            if (item.title.isNotEmpty &&
                                item.title != item.peerName)
                              Text(
                                ' · ',
                                style: TextStyle(color: scheme.outline),
                              ),
                            Flexible(
                              flex: 2,
                              child: Text(
                                item.preview,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PmStateCard extends StatelessWidget {
  const _PmStateCard({
    required this.icon,
    required this.title,
    required this.message,
    required this.primaryLabel,
    required this.primaryIcon,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });

  final IconData icon;
  final String title;
  final String message;
  final String primaryLabel;
  final IconData primaryIcon;
  final VoidCallback onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 78,
                height: 78,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      scheme.primary.withValues(alpha: .18),
                      scheme.secondary.withValues(alpha: .12),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Icon(icon, size: 36, color: scheme.primary),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: onPrimary,
                icon: Icon(primaryIcon),
                label: Text(primaryLabel),
              ),
              if (secondaryLabel != null && onSecondary != null) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: onSecondary,
                  child: Text(secondaryLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
