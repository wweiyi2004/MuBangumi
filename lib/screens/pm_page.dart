import 'dart:async';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/layout/app_layout.dart';
import '../core/network/bangumi_endpoints.dart';
import '../core/network/pm_service.dart';
import '../core/theme/app_theme.dart';
import '../models/pm_models.dart';
import '../state/website_session_controller.dart';
import 'community_page.dart';
import 'website_login_screen.dart';

/// Native 站内短信：Cookie 会话 + HTML 解析；失败时回退官网 WebView。
class PmPage extends ConsumerStatefulWidget {
  const PmPage({super.key, this.composeTo});

  final String? composeTo;

  @override
  ConsumerState<PmPage> createState() => _PmPageState();
}

class _PmPageState extends ConsumerState<PmPage> {
  final _service = PmService.shared;

  int _tab = 0; // 0 inbox, 1 outbox
  List<PmConversation> _inbox = const [];
  List<PmConversation> _outbox = const [];
  bool _loadingInbox = true;
  bool _loadingOutbox = false;
  String? _error;
  bool _needAuth = false;
  bool _outboxLoaded = false;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    await _loadInbox();
    final target = widget.composeTo?.trim();
    if (target != null && target.isNotEmpty && mounted && !_needAuth) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PmComposeScreen(toUser: target),
        ),
      );
      if (mounted) await _loadInbox();
    }
  }

  Future<void> _loadInbox() async {
    setState(() {
      _loadingInbox = true;
      _error = null;
      _needAuth = false;
    });
    try {
      final list = await _service.loadInbox();
      if (!mounted) return;
      setState(() {
        _inbox = list;
        _loadingInbox = false;
      });
    } on PmAuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingInbox = false;
        _needAuth = true;
        _error = error.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingInbox = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _loadOutbox() async {
    setState(() {
      _loadingOutbox = true;
      _error = null;
    });
    try {
      final list = await _service.loadOutbox();
      if (!mounted) return;
      setState(() {
        _outbox = list;
        _loadingOutbox = false;
        _outboxLoaded = true;
      });
    } on PmAuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingOutbox = false;
        _needAuth = true;
        _error = error.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingOutbox = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _selectTab(int index) async {
    if (_tab == index) return;
    setState(() => _tab = index);
    if (index == 1 && !_outboxLoaded && !_loadingOutbox) {
      await _loadOutbox();
    }
  }

  Future<void> _openConversation(PmConversation item) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PmConversationScreen(
          conversationId: item.id,
          title: item.title,
          peerName: item.peerName,
          peerAvatar: item.avatarUrl,
        ),
      ),
    );
    if (mounted) unawaited(_loadInbox());
  }

  Future<void> _openCompose() async {
    final sent = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const PmComposeScreen()));
    if (sent == true && mounted) unawaited(_loadInbox());
  }

  Future<void> _syncWebsiteLogin() async {
    await openWebsiteLoginScreen(context);
    if (!mounted) return;
    await ref.read(websiteSessionProvider.notifier).reload();
    await _loadInbox();
  }

  Future<void> _openWebFallback() async {
    final cookies = await loadWebsiteSeedCookies();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CommunityWebScreen(
          initialUrl: 'https://bgm.tv/pm',
          title: '站内短信（网页）',
          showSectionSwitcher: false,
          seedCookies: cookies,
          loginHint: '原生接口失败时的网页兜底。',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final website = ref.watch(websiteSessionProvider);
    final phone = AppLayout.isPhone(context);
    final pad = AppLayout.pagePadding(context);
    final items = _tab == 0 ? _inbox : _outbox;
    final loading = _tab == 0 ? _loadingInbox : _loadingOutbox;
    final unread = _inbox.where((e) => e.isUnread).length;

    return Scaffold(
      extendBodyBehindAppBar: false,
      appBar: AppBar(
        titleSpacing: phone ? 8 : 16,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('站内短信'),
            Text(
              website.isSynced
                  ? (unread > 0 ? '$unread 条未读 · 网站会话已同步' : '网站会话已同步')
                  : '需同步网站登录后使用',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: website.isSynced ? '重新同步网站登录' : '同步网站登录',
            onPressed: _syncWebsiteLogin,
            icon: Icon(
              website.isSynced
                  ? Icons.verified_user_rounded
                  : Icons.shield_outlined,
              color: website.isSynced ? scheme.primary : null,
            ),
          ),
          IconButton(
            tooltip: '网页版',
            onPressed: _openWebFallback,
            icon: const Icon(Icons.open_in_new_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: _needAuth
          ? null
          : FloatingActionButton(
              onPressed: _openCompose,
              elevation: 2,
              child: const Icon(Icons.edit_rounded),
            ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(pad, 4, pad, 10),
            child: _PmSegmentedTabs(
              index: _tab,
              inboxCount: _inbox.length,
              outboxCount: _outbox.length,
              unread: unread,
              onChanged: _selectTab,
            ),
          ),
          Expanded(
            child: _PmListBody(
              loading: loading,
              error: _error,
              needAuth: _needAuth,
              items: items,
              emptyLabel: _tab == 0 ? '还没有收到短信' : '还没有发出的短信',
              emptyHint: _tab == 0 ? '和好友互相发送站内短信后会出现在这里' : '写一封新短信开始对话',
              onRetry: _tab == 0 ? _loadInbox : _loadOutbox,
              onSyncLogin: _syncWebsiteLogin,
              onOpenWeb: _openWebFallback,
              onOpen: _openConversation,
              onRefresh: _tab == 0 ? _loadInbox : _loadOutbox,
            ),
          ),
        ],
      ),
    );
  }
}

class _PmSegmentedTabs extends StatelessWidget {
  const _PmSegmentedTabs({
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
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .6)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _seg(
              context,
              selected: index == 0,
              label: '收件箱',
              count: inboxCount,
              badge: unread,
              onTap: () => onChanged(0),
            ),
          ),
          Expanded(
            child: _seg(
              context,
              selected: index == 1,
              label: '已发送',
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
      color: selected ? scheme.surface : Colors.transparent,
      elevation: selected ? 0.5 : 0,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
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
                        ? scheme.primary.withValues(alpha: .8)
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
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    badge > 99 ? '99+' : '$badge',
                    style: TextStyle(
                      color: scheme.onPrimary,
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

class _PmListBody extends StatelessWidget {
  const _PmListBody({
    required this.loading,
    required this.error,
    required this.needAuth,
    required this.items,
    required this.emptyLabel,
    required this.emptyHint,
    required this.onRetry,
    required this.onSyncLogin,
    required this.onOpenWeb,
    required this.onOpen,
    required this.onRefresh,
  });

  final bool loading;
  final String? error;
  final bool needAuth;
  final List<PmConversation> items;
  final String emptyLabel;
  final String emptyHint;
  final Future<void> Function() onRetry;
  final Future<void> Function() onSyncLogin;
  final Future<void> Function() onOpenWeb;
  final Future<void> Function(PmConversation) onOpen;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    if (loading && items.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.4));
    }
    if (needAuth) {
      return _PmStateCard(
        icon: Icons.lock_person_rounded,
        title: '需要网站登录',
        message: error ?? '站内短信使用官网会话，与 OAuth 登录相互独立。',
        primaryLabel: '同步网站登录',
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
        message: error!,
        primaryLabel: '重试',
        primaryIcon: Icons.refresh_rounded,
        onPrimary: onRetry,
        secondaryLabel: '打开网页版',
        onSecondary: onOpenWeb,
      );
    }
    if (items.isEmpty) {
      return _PmStateCard(
        icon: Icons.mail_outline_rounded,
        title: emptyLabel,
        message: emptyHint,
        primaryLabel: '刷新',
        primaryIcon: Icons.refresh_rounded,
        onPrimary: onRefresh,
      );
    }

    final pad = AppLayout.pagePadding(context);
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(pad, 2, pad, 96),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final item = items[index];
          return _PmConversationTile(item: item, onTap: () => onOpen(item));
        },
      ),
    );
  }
}

class _PmConversationTile extends StatelessWidget {
  const _PmConversationTile({required this.item, required this.onTap});

  final PmConversation item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final subtitle = [
      if (item.peerName.isNotEmpty) item.peerName,
      if (item.preview.isNotEmpty) item.preview,
    ].join(' · ');

    return Material(
      color: item.isUnread
          ? scheme.primaryContainer.withValues(alpha: .28)
          : scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: item.isUnread
                  ? scheme.primary.withValues(alpha: .22)
                  : scheme.outlineVariant.withValues(alpha: .55),
            ),
          ),
          child: Row(
            children: [
              _PmAvatar(
                url: item.avatarUrl,
                name: item.peerName.isNotEmpty ? item.peerName : item.title,
                radius: 26,
                showRing: item.isUnread,
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
                            item.peerName.isNotEmpty
                                ? item.peerName
                                : item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: item.isUnread
                                  ? FontWeight.w800
                                  : FontWeight.w700,
                              letterSpacing: -.2,
                            ),
                          ),
                        ),
                        if (item.timeText.isNotEmpty)
                          Text(
                            item.timeText,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: item.isUnread
                                      ? scheme.primary
                                      : scheme.onSurfaceVariant,
                                  fontWeight: item.isUnread
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface.withValues(alpha: .88),
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        item.preview.isNotEmpty ? item.preview : subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (item.isUnread) ...[
                const SizedBox(width: 8),
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: scheme.primary.withValues(alpha: .35),
                        blurRadius: 6,
                      ),
                    ],
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

class PmConversationScreen extends StatefulWidget {
  const PmConversationScreen({
    super.key,
    required this.conversationId,
    required this.title,
    this.peerName = '',
    this.peerAvatar = '',
  });

  final String conversationId;
  final String title;
  final String peerName;
  final String peerAvatar;

  @override
  State<PmConversationScreen> createState() => _PmConversationScreenState();
}

class _PmConversationScreenState extends State<PmConversationScreen> {
  final _service = PmService.shared;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();

  PmConversationDetail? _detail;
  bool _loading = true;
  bool _sending = false;
  String? _error;
  String? _threadId;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    // Capture the requested thread up-front so a slow response for a
    // previously-selected thread cannot overwrite the current one (and so
    // _send can never reply through a stale thread's form).
    final requestedThread = _threadId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await _service.loadConversation(
        widget.conversationId,
        threadId: requestedThread,
      );
      if (!mounted || requestedThread != _threadId) return;
      setState(() {
        _detail = detail;
        _loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    } catch (error) {
      if (!mounted || requestedThread != _threadId) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _send() async {
    final detail = _detail;
    final text = _input.text.trim();
    if (detail == null || text.isEmpty || _sending || _loading) return;
    setState(() => _sending = true);
    try {
      await _service.reply(form: detail.form, body: text);
      _input.clear();
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final detail = _detail;
    final title = detail?.peerName.isNotEmpty == true
        ? detail!.peerName
        : (widget.peerName.isNotEmpty ? widget.peerName : widget.title);
    final avatar = widget.peerAvatar.isNotEmpty
        ? widget.peerAvatar
        : (detail?.messages
                  .where((m) => !m.isSelf && m.avatarUrl.isNotEmpty)
                  .map((m) => m.avatarUrl)
                  .firstOrNull ??
              '');

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            _PmAvatar(url: avatar, name: title, radius: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  if (widget.title.isNotEmpty && widget.title != title)
                    Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          if (detail != null && detail.threads.length > 1)
            SizedBox(
              height: 48,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
                itemCount: detail.threads.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final thread = detail.threads[index];
                  final selected =
                      (_threadId == null && thread.current) ||
                      _threadId == thread.id;
                  return ChoiceChip(
                    label: Text(thread.title),
                    selected: selected,
                    onSelected: (_) {
                      setState(() => _threadId = thread.id);
                      unawaited(_load());
                    },
                  );
                },
              ),
            ),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    scheme.surface,
                    scheme.surfaceContainerLowest.withValues(alpha: .65),
                  ],
                ),
              ),
              child: _loading && detail == null
                  ? const Center(
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    )
                  : _messageList(detail),
            ),
          ),
          _ComposerBar(
            controller: _input,
            focusNode: _focus,
            sending: _sending,
            enabled: detail != null && !_sending && !_loading,
            onSend: _send,
          ),
        ],
      ),
    );
  }

  Widget _messageList(PmConversationDetail? detail) {
    if (_error != null && detail == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.tonal(onPressed: _load, child: const Text('重试')),
            ],
          ),
        ),
      );
    }
    final messages = detail?.messages ?? const <PmMessage>[];
    if (messages.isEmpty) {
      return const Center(child: Text('暂无消息'));
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final msg = messages[index];
        final prev = index > 0 ? messages[index - 1] : null;
        final showAvatar = !msg.isSelf && (prev == null || prev.isSelf);
        return _ChatBubble(message: msg, showAvatar: showAvatar);
      },
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message, required this.showAvatar});

  final PmMessage message;
  final bool showAvatar;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isSelf = message.isSelf;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: Radius.circular(isSelf ? 18 : 5),
      bottomRight: Radius.circular(isSelf ? 5 : 18),
    );

    final bubble = ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.74,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(13, 10, 13, 8),
        decoration: BoxDecoration(
          gradient: isSelf
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFFF779D), Color(0xFFE7447A)],
                )
              : null,
          color: isSelf ? null : scheme.surfaceContainerHigh,
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isSelf ? .12 : .05),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
          border: isSelf
              ? null
              : Border.all(color: scheme.outlineVariant.withValues(alpha: .45)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isSelf)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  message.name,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: scheme.primary,
                  ),
                ),
              ),
            SelectableText(
              message.contentText,
              style: TextStyle(
                height: 1.4,
                color: isSelf ? Colors.white : scheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (message.timeText.isNotEmpty) ...[
              const SizedBox(height: 5),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  message.timeText,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: isSelf
                        ? Colors.white.withValues(alpha: .78)
                        : scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    return Padding(
      padding: EdgeInsets.only(
        bottom: 10,
        left: isSelf ? 36 : 0,
        right: isSelf ? 0 : 36,
      ),
      child: Row(
        mainAxisAlignment: isSelf
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isSelf) ...[
            if (showAvatar)
              _PmAvatar(url: message.avatarUrl, name: message.name, radius: 15)
            else
              const SizedBox(width: 30),
            const SizedBox(width: 8),
          ],
          Flexible(child: bubble),
        ],
      ),
    );
  }
}

class _ComposerBar extends StatelessWidget {
  const _ComposerBar({
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.enabled,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final bool enabled;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: .92),
            border: Border(
              top: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: .7),
              ),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      enabled: enabled,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        hintText: '输入回复…',
                        isDense: true,
                        filled: true,
                        fillColor: scheme.surfaceContainerLow,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: BorderSide(
                            color: scheme.outlineVariant.withValues(alpha: .5),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: BorderSide(
                            color: scheme.primary.withValues(alpha: .7),
                            width: 1.4,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 160),
                    opacity: enabled ? 1 : .5,
                    child: Material(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(18),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: enabled ? onSend : null,
                        child: SizedBox(
                          width: 48,
                          height: 48,
                          child: Center(
                            child: sending
                                ? SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                      color: scheme.onPrimary,
                                    ),
                                  )
                                : Icon(
                                    Icons.arrow_upward_rounded,
                                    color: scheme.onPrimary,
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PmComposeScreen extends StatefulWidget {
  const PmComposeScreen({super.key, this.toUser});

  final String? toUser;

  @override
  State<PmComposeScreen> createState() => _PmComposeScreenState();
}

class _PmComposeScreenState extends State<PmComposeScreen> {
  final _service = PmService.shared;
  final _to = TextEditingController();
  final _title = TextEditingController();
  final _body = TextEditingController();
  PmComposeParams? _params;
  bool _loading = false;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.toUser?.trim() ?? '';
    if (initial.isNotEmpty) {
      _to.text = initial;
      unawaited(_prepare());
    }
  }

  @override
  void dispose() {
    _to.dispose();
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _prepare() async {
    final user = _to.text.trim();
    if (user.isEmpty) {
      setState(() => _error = '请填写对方用户名或 UID');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final params = await _service.loadComposeParams(user);
      if (!mounted) return;
      setState(() {
        _params = params;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _params = null;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _send() async {
    var params = _params;
    if (params == null) {
      await _prepare();
      params = _params;
    }
    if (params == null || _sending) return;
    setState(() => _sending = true);
    try {
      await _service.compose(
        params: params,
        title: _title.text,
        body: _body.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pad = AppLayout.pagePadding(context);
    return Scaffold(
      appBar: AppBar(title: const Text('写短信')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(pad, 8, pad, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  scheme.primary.withValues(alpha: .12),
                  scheme.secondary.withValues(alpha: .08),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: .5),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: .16),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.mail_rounded, color: scheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '发送站内短信给 Bangumi 用户。对方会在官网收件箱中看到。',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _to,
            decoration: InputDecoration(
              labelText: '收件人',
              hintText: '用户名或 UID',
              prefixIcon: const Icon(Icons.person_outline_rounded),
              suffixIcon: IconButton(
                tooltip: '校验收件人',
                onPressed: _loading ? null : _prepare,
                icon: _loading
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.person_search_rounded),
              ),
            ),
            onSubmitted: (_) => _prepare(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _title,
            decoration: const InputDecoration(
              labelText: '标题',
              prefixIcon: Icon(Icons.title_rounded),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _body,
            minLines: 8,
            maxLines: 14,
            decoration: const InputDecoration(
              labelText: '内容',
              alignLabelWithHint: true,
              prefixIcon: Padding(
                padding: EdgeInsets.only(bottom: 120),
                child: Icon(Icons.notes_rounded),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: scheme.error, height: 1.4)),
          ],
          if (_params != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: .45),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle_rounded,
                    color: scheme.primary,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '收件人已确认，可以发送',
                    style: TextStyle(
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 22),
          FilledButton(
            onPressed: _sending ? null : _send,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: _sending
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  )
                : const Text(
                    '发送短信',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
          ),
        ],
      ),
    );
  }
}

class _PmAvatar extends StatelessWidget {
  const _PmAvatar({
    required this.url,
    required this.name,
    this.radius = 22,
    this.showRing = false,
  });

  final String url;
  final String name;
  final double radius;
  final bool showRing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final resolved = BangumiEndpoints.imageUrl(url);
    final letter = name.trim().isEmpty
        ? '?'
        : name.trim().characters.first.toUpperCase();

    Widget avatar;
    if (resolved.isEmpty) {
      avatar = CircleAvatar(
        radius: radius,
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
        child: Text(
          letter,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: radius * 0.78,
          ),
        ),
      );
    } else {
      avatar = CircleAvatar(
        radius: radius,
        backgroundColor: scheme.surfaceContainerHighest,
        backgroundImage: CachedNetworkImageProvider(resolved),
        onBackgroundImageError: (_, _) {},
      );
    }

    if (!showRing) return avatar;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [Color(0xFFFF779D), Color(0xFFE7447A)],
        ),
        boxShadow: [
          BoxShadow(color: AppTheme.seed.withValues(alpha: .25), blurRadius: 8),
        ],
      ),
      child: avatar,
    );
  }
}

/// Opens native inbox (or compose when [composeTo] is set).
Future<void> openPmPage(BuildContext context, {String? composeTo}) async {
  await Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => PmPage(composeTo: composeTo)));
}
