import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/network/bangumi_endpoints.dart';
import '../core/network/community_service.dart';
import '../models/community_models.dart';
import '../state/notify_controller.dart';
import '../widgets/subject_widgets.dart';
import 'user_profile_page.dart';

class NotifyPage extends ConsumerStatefulWidget {
  const NotifyPage({super.key});

  @override
  ConsumerState<NotifyPage> createState() => _NotifyPageState();
}

class _NotifyPageState extends ConsumerState<NotifyPage> {
  final _service = CommunityService.shared;
  List<BangumiNotice> _items = const [];
  int _total = 0;
  bool _loading = true;
  bool _busy = false;
  bool _unreadOnly = false;
  String? _error;
  Map<int, String> _noticeContents = const {};
  Set<int> _loadingContentIds = const {};
  Map<String, bool> _friendRequestAccepted = const {};
  Set<String> _loadingFriendRequestUsers = const {};
  final Set<int> _acceptingNoticeIds = {};
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _load(refresh: true));
  }

  Future<void> _load({bool refresh = false}) async {
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _service.loadNotices(
        unreadOnly: _unreadOnly,
        refresh: refresh,
      );
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _items = page.data;
        _total = page.total;
        _loading = false;
        _noticeContents = const {};
        _loadingContentIds = {
          for (final notice in page.data)
            if (notice.canLoadReplyContent) notice.id,
        };
        _loadingFriendRequestUsers = {
          for (final notice in page.data)
            if (notice.isFriendRequest) notice.sender!.username.toLowerCase(),
        };
      });
      unawaited(_loadContents(page.data, generation, refresh: refresh));
      unawaited(_loadFriendRequestStatuses(page.data, generation));
      // Keep shell badge in sync with unread totals.
      if (_unreadOnly) {
        ref
            .read(notifyBadgeProvider.notifier)
            .setUnreadCount(page.total > 0 ? page.total : page.data.length);
      } else {
        final unread = page.data.where((n) => n.unread).length;
        // Prefer total when listing all is truncated; refresh badge separately.
        if (unread > 0 || page.data.isEmpty) {
          ref.read(notifyBadgeProvider.notifier).setUnreadCount(unread);
        } else {
          unawaited(ref.read(notifyBadgeProvider.notifier).refresh());
        }
      }
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _loadFriendRequestStatuses(
    List<BangumiNotice> notices,
    int generation,
  ) async {
    final usernames = {
      for (final notice in notices)
        if (notice.isFriendRequest) notice.sender!.username,
    }.toList();
    if (usernames.isEmpty) return;
    final accepted = <String, bool>{};
    const concurrency = 4;
    for (var index = 0; index < usernames.length; index += concurrency) {
      final end = (index + concurrency).clamp(0, usernames.length);
      await Future.wait(
        usernames.sublist(index, end).map((username) async {
          try {
            accepted[username.toLowerCase()] = await _service.isFriend(
              username,
            );
          } catch (_) {
            // The actionable request remains visible when status lookup fails.
          }
        }),
      );
    }
    if (!mounted || generation != _loadGeneration) return;
    setState(() {
      _friendRequestAccepted = {..._friendRequestAccepted, ...accepted};
      _loadingFriendRequestUsers = const {};
    });
  }

  Future<void> _acceptFriendRequest(BangumiNotice notice) async {
    final sender = notice.sender;
    if (sender == null || _acceptingNoticeIds.contains(notice.id)) return;
    setState(() => _acceptingNoticeIds.add(notice.id));
    try {
      await _service.acceptFriendRequest(notice);
      if (!mounted) return;
      final wasUnread = notice.unread;
      setState(() {
        _friendRequestAccepted = {
          ..._friendRequestAccepted,
          sender.username.toLowerCase(): true,
        };
        _items = [
          for (final item in _items)
            if (item.id == notice.id)
              BangumiNotice(
                id: item.id,
                title: item.title,
                type: item.type,
                mainId: item.mainId,
                relatedId: item.relatedId,
                unread: false,
                createdAt: item.createdAt,
                sender: item.sender,
              )
            else
              item,
        ];
      });
      if (wasUnread) {
        ref.read(notifyBadgeProvider.notifier).markOneReadLocally();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已接受 ${sender.displayName} 的好友申请')),
      );
      unawaited(ref.read(notifyBadgeProvider.notifier).refresh());
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _acceptingNoticeIds.remove(notice.id));
      }
    }
  }

  Future<void> _loadContents(
    List<BangumiNotice> notices,
    int generation, {
    required bool refresh,
  }) async {
    if (!notices.any((notice) => notice.canLoadReplyContent)) return;
    final contents = await _service.loadNoticeContents(
      notices,
      refresh: refresh,
    );
    if (!mounted || generation != _loadGeneration) return;
    setState(() {
      _noticeContents = contents;
      _loadingContentIds = const {};
    });
  }

  Future<void> _markAllRead() async {
    setState(() => _busy = true);
    try {
      await _service.clearNotices();
      if (!mounted) return;
      ref.read(notifyBadgeProvider.notifier).clearLocally();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已全部标为已读')));
      await _load(refresh: true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _markOne(BangumiNotice notice) async {
    if (!notice.unread) return;
    try {
      await _service.clearNotices(ids: [notice.id]);
      if (!mounted) return;
      ref.read(notifyBadgeProvider.notifier).markOneReadLocally();
      setState(() {
        _items = [
          for (final item in _items)
            if (item.id == notice.id)
              BangumiNotice(
                id: item.id,
                title: item.title,
                type: item.type,
                mainId: item.mainId,
                relatedId: item.relatedId,
                unread: false,
                createdAt: item.createdAt,
                sender: item.sender,
              )
            else
              item,
        ];
      });
    } catch (_) {
      // Non-blocking: list still usable.
    }
  }

  Future<void> _openNotice(BangumiNotice notice) async {
    await _markOne(notice);
    final url = notice.webUrl;
    final uri = Uri.tryParse(url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('电波提醒'),
        actions: [
          IconButton(
            tooltip: _unreadOnly ? '显示全部' : '仅未读',
            onPressed: _loading
                ? null
                : () {
                    setState(() => _unreadOnly = !_unreadOnly);
                    _load(refresh: true);
                  },
            icon: Icon(
              _unreadOnly
                  ? Icons.mark_email_unread_rounded
                  : Icons.mark_email_read_outlined,
            ),
          ),
          IconButton(
            tooltip: '全部已读',
            onPressed: _busy || _loading ? null : _markAllRead,
            icon: const Icon(Icons.done_all_rounded),
          ),
          IconButton(
            tooltip: '在官网打开',
            onPressed: () => launchUrl(
              Uri.parse('https://bgm.tv/notify/all'),
              mode: LaunchMode.externalApplication,
            ),
            icon: const Icon(Icons.open_in_new_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(refresh: true),
        child: _loading
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 120),
                  Center(child: CircularProgressIndicator()),
                ],
              )
            : _error != null
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                children: [
                  EmptyState(
                    icon: Icons.notifications_off_outlined,
                    title: '通知加载失败',
                    message: _error!,
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => _load(refresh: true),
                    child: const Text('重试'),
                  ),
                  TextButton(
                    onPressed: () => launchUrl(
                      Uri.parse('https://bgm.tv/notify/all'),
                      mode: LaunchMode.externalApplication,
                    ),
                    child: const Text('打开官网通知'),
                  ),
                ],
              )
            : _items.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                children: [
                  EmptyState(
                    icon: Icons.notifications_none_rounded,
                    title: _unreadOnly ? '没有未读电波' : '暂无电波提醒',
                    message: _unreadOnly
                        ? '切换到「全部」可查看历史通知。'
                        : '有新回复或好友动态时会出现在这里。',
                  ),
                ],
              )
            : ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 40),
                itemCount: _items.length + 1,
                separatorBuilder: (_, _) => const SizedBox(height: 4),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                      child: Text(
                        _unreadOnly
                            ? '未读 $_total 条'
                            : '共 $_total 条 · 显示 ${_items.length} 条',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    );
                  }
                  final notice = _items[index - 1];
                  final sender = notice.sender;
                  final content = _noticeContents[notice.id];
                  final loadingContent = _loadingContentIds.contains(notice.id);
                  final friendUsername = sender?.username.toLowerCase();
                  final friendAccepted = friendUsername == null
                      ? false
                      : _friendRequestAccepted[friendUsername] == true;
                  final checkingFriend =
                      friendUsername != null &&
                      _loadingFriendRequestUsers.contains(friendUsername);
                  final acceptingFriend = _acceptingNoticeIds.contains(
                    notice.id,
                  );
                  return Card(
                    color: notice.unread
                        ? scheme.primaryContainer.withValues(alpha: 0.35)
                        : null,
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: scheme.surfaceContainerHighest,
                        backgroundImage:
                            sender != null && sender.avatarUrl.isNotEmpty
                            ? CachedNetworkImageProvider(
                                BangumiEndpoints.imageUrl(sender.avatarUrl),
                              )
                            : null,
                        child: sender == null || sender.avatarUrl.isEmpty
                            ? const Icon(Icons.notifications_outlined)
                            : null,
                      ),
                      title: Text(
                        notice.actionText,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (notice.showsContextTitle)
                              Text(
                                '《${notice.title}》',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            if (content != null) ...[
                              const SizedBox(height: 6),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: scheme.surfaceContainerHighest
                                      .withValues(alpha: 0.6),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  content,
                                  maxLines: 4,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ] else if (loadingContent) ...[
                              const SizedBox(height: 5),
                              Text(
                                '正在读取回复内容…',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                            ],
                            if (notice.isFriendRequest) ...[
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  FilledButton.tonalIcon(
                                    onPressed:
                                        friendAccepted ||
                                            checkingFriend ||
                                            acceptingFriend
                                        ? null
                                        : () => _acceptFriendRequest(notice),
                                    icon: acceptingFriend || checkingFriend
                                        ? const SizedBox.square(
                                            dimension: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : Icon(
                                            friendAccepted
                                                ? Icons.check_rounded
                                                : Icons
                                                      .person_add_alt_1_rounded,
                                            size: 18,
                                          ),
                                    label: Text(
                                      friendAccepted ? '已接受' : '接受好友',
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: sender == null
                                        ? null
                                        : () => openUserProfile(
                                            context,
                                            username: sender.username,
                                            nickname: sender.nickname,
                                            avatarUrl: sender.avatarUrl,
                                            id: sender.id,
                                          ),
                                    child: const Text('查看主页'),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 5),
                            Text(
                              [
                                _formatTime(notice.createdAt),
                                if (notice.unread) '未读',
                              ].join(' · '),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      trailing: notice.unread
                          ? Icon(Icons.circle, size: 10, color: scheme.primary)
                          : const Icon(Icons.chevron_right_rounded),
                      onTap: () => _openNotice(notice),
                      onLongPress: sender == null
                          ? null
                          : () => openUserProfile(
                              context,
                              username: sender.username,
                              nickname: sender.nickname,
                              avatarUrl: sender.avatarUrl,
                              id: sender.id,
                            ),
                    ),
                  );
                },
              ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final local = time.toLocal();
    final now = DateTime.now();
    final diff = now.difference(local);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
    if (diff.inDays < 1) return '${diff.inHours} 小时前';
    if (diff.inDays < 7) return '${diff.inDays} 天前';
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }
}
