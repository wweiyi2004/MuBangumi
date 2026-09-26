import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../models/pm_contact.dart';
import '../../../state/pm_contacts_controller.dart';
import '../../../widgets/social_chat_style.dart';
import 'pm_avatar.dart';
import '../../../widgets/projection_art.dart';

class PmContactsView extends StatelessWidget {
  const PmContactsView({
    super.key,
    required this.contacts,
    required this.onOpen,
    required this.onSyncLogin,
    this.selectedId,
    this.query = '',
    this.openingKey,
    this.authMessage,
  });
  final PmContactsController contacts;
  final ValueChanged<PmContact> onOpen;
  final VoidCallback onSyncLogin;
  final String? selectedId, openingKey;
  final String? authMessage;
  final String query;

  @override
  Widget build(BuildContext context) {
    final items = contacts.items
        .where((person) => person.matches(query))
        .toList();
    final colors = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 8, 2),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  contacts.friendsLoading && contacts.friends.isEmpty
                      ? '正在加载完整好友列表…'
                      : contacts.friendsError != null &&
                            contacts.friends.isEmpty
                      ? '好友暂未加载'
                      : '${contacts.friends.length} 位好友',
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
              IconButton(
                tooltip: '刷新好友和会话',
                onPressed: contacts.busy
                    ? null
                    : () => contacts.refresh(forceFriends: true),
                icon: const Icon(CupertinoIcons.arrow_clockwise, size: 18),
              ),
            ],
          ),
        ),
        if (contacts.busy) const LinearProgressIndicator(minHeight: 2),
        if (contacts.friendsError != null)
          _Notice(
            message: contacts.friendsError!,
            action: '重试好友加载',
            onTap: () => contacts.refreshFriends(refresh: true),
          ),
        if (contacts.needAuth)
          _Notice(
            message: '需要补充账号验证，验证后可查看和发送私信',
            details: authMessage ?? contacts.historyError,
            action: '登录后继续',
            onTap: onSyncLogin,
          )
        else if (contacts.historyError != null)
          _Notice(
            message: '私信记录加载失败，已保留当前列表',
            details: contacts.historyError,
            action: '重试私信同步',
            onTap: () => contacts.syncHistory(more: true),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => contacts.refresh(forceFriends: true),
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 80),
              itemCount: items.length + 1,
              itemBuilder: (context, index) {
                if (index == items.length) {
                  return Column(
                    children: [
                      if (items.isEmpty && !contacts.busy)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Column(
                            children: [
                              ProjectionIllustration(
                                scene: query.isNotEmpty
                                    ? ProjectionScene.discover
                                    : ProjectionScene.conversation,
                                width: 92,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                query.isNotEmpty ? '没有匹配的好友或联系人' : '还没有好友或私信会话',
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      if (contacts.historyIncomplete &&
                          !contacts.syncingHistory &&
                          contacts.historyError == null)
                        TextButton(
                          onPressed: () => contacts.syncHistory(more: true),
                          child: const Text('继续同步历史会话'),
                        ),
                    ],
                  );
                }
                final person = items[index];
                final message = person.latest;
                final selected = person.conversations.any(
                  (row) => row.id == selectedId,
                );
                final title = message?.title ?? '';
                final preview = message?.preview ?? '';
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!person.isFriend &&
                        (index == 0 || items[index - 1].isFriend))
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
                        child: Text(
                          '其他会话',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    Material(
                      color: selected
                          ? SocialChatStyle.accent(
                              context,
                            ).withValues(alpha: .09)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        onTap: openingKey == null ? () => onOpen(person) : null,
                        borderRadius: BorderRadius.circular(10),
                        child: Semantics(
                          selected: selected,
                          label: person.isUnread ? '未读私信' : null,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 14,
                            ),
                            child: Row(
                              children: [
                                Badge(
                                  isLabelVisible: person.isUnread,
                                  backgroundColor: colors.error,
                                  child: PmAvatar(
                                    url: person.avatarUrl,
                                    name: person.name,
                                    radius: 23,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              person.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                          if (message?.timeText.isNotEmpty ==
                                              true) ...[
                                            const SizedBox(width: 8),
                                            ConstrainedBox(
                                              constraints: const BoxConstraints(
                                                maxWidth: 90,
                                              ),
                                              child: Text(
                                                message!.timeText,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color:
                                                      colors.onSurfaceVariant,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      if (message == null)
                                        Text(
                                          '@${person.username} · 发起私聊',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: colors.onSurfaceVariant,
                                          ),
                                        )
                                      else
                                        Row(
                                          children: [
                                            if (title.isNotEmpty)
                                              Flexible(
                                                child: Text(
                                                  title,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color:
                                                        colors.onSurfaceVariant,
                                                  ),
                                                ),
                                              ),
                                            if (preview.isNotEmpty &&
                                                preview != title) ...[
                                              if (title.isNotEmpty)
                                                Text(
                                                  ' · ',
                                                  style: TextStyle(
                                                    color: colors.outline,
                                                  ),
                                                ),
                                              Flexible(
                                                child: Text(
                                                  preview,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color:
                                                        colors.onSurfaceVariant,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                    ],
                                  ),
                                ),
                                if (openingKey == person.key)
                                  const Padding(
                                    padding: EdgeInsets.only(left: 8),
                                    child: SizedBox.square(
                                      dimension: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
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
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.message,
    this.details,
    required this.action,
    required this.onTap,
  });
  final String message, action;
  final String? details;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(message, style: Theme.of(context).textTheme.bodySmall),
        if (details != null && details != message)
          Text(details!, style: Theme.of(context).textTheme.bodySmall),
        TextButton(onPressed: onTap, child: Text(action)),
      ],
    ),
  );
}
