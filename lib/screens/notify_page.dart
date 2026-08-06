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

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _load(refresh: true));
  }

  Future<void> _load({bool refresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _service.loadNotices(
        unreadOnly: _unreadOnly,
        refresh: refresh,
      );
      if (!mounted) return;
      setState(() {
        _items = page.data;
        _total = page.total;
        _loading = false;
      });
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
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
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
                  FilledButton(onPressed: () => _load(refresh: true), child: const Text('重试')),
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
                        notice.title.isEmpty ? '通知 #${notice.id}' : notice.title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        [
                          if (sender != null) sender.displayName,
                          _formatTime(notice.createdAt),
                          if (notice.unread) '未读',
                        ].join(' · '),
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
