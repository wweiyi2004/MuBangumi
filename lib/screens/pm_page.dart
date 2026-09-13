import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/layout/app_layout.dart';
import '../core/network/bangumi_endpoints.dart';
import '../core/network/pm_service.dart';
import '../models/pm_models.dart';
import '../state/website_session_controller.dart';
import '../state/pm_mailbox_controller.dart';
import '../state/session_controller.dart';
import '../widgets/community_loading.dart';
import '../widgets/pm_draft_editor.dart';
import '../core/storage/pm_draft_store.dart';
import 'community_page.dart';
import 'website_login_screen.dart';

void _watchPmSession(WidgetRef ref, VoidCallback onChanged) {
  ref.listenManual(websiteSessionProvider, (previous, next) {
    if (next.ready &&
        previous?.ready == true &&
        previous?.snapshot?.authenticationKey !=
            next.snapshot?.authenticationKey) {
      onChanged();
    }
  });
}

/// Native 站内短信：Cookie 会话 + HTML 解析；失败时回退官网 WebView。
class PmPage extends ConsumerStatefulWidget {
  const PmPage({super.key, this.composeTo, this.service});

  final String? composeTo;
  final PmService? service;

  @override
  ConsumerState<PmPage> createState() => _PmPageState();
}

class _PmPageState extends ConsumerState<PmPage> {
  late final _service = widget.service ?? PmService.shared;
  late final _inbox = PmMailboxController(_service.loadInbox);
  late final _outbox = PmMailboxController(_service.loadOutbox);
  PmMailboxController get _mailbox => _tab == 0 ? _inbox : _outbox;

  int _tab = 0; // 0 inbox, 1 outbox
  String? _pendingComposeTo;
  PmConversation? _selected;
  GlobalKey<_PmConversationScreenState> _chatKey = GlobalKey();
  bool _switching = false;
  int _selectionGeneration = 0;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _pendingComposeTo = widget.composeTo?.trim();
    _inbox.addListener(_onMailboxChanged);
    _outbox.addListener(_onMailboxChanged);
    ref.listenManual(sessionProvider.select((state) => state.user?.id), (
      previous,
      next,
    ) {
      if (previous == next) return;
      _chatKey.currentState?._onWebsiteSessionChanged();
      _selectionGeneration++;
      setState(() => _selected = null);
    });
    ref.listenManual(websiteSessionProvider, (previous, next) {
      if (!next.ready ||
          previous?.snapshot?.authenticationKey ==
              next.snapshot?.authenticationKey) {
        return;
      }
      _inbox.reset(requireAuth: !next.isSynced);
      _outbox.reset(requireAuth: !next.isSynced);
      _chatKey.currentState?._onWebsiteSessionChanged();
      _selectionGeneration++;
      setState(() => _selected = null);
      if (next.isSynced) {
        unawaited(_inbox.refresh());
        if (_tab == 1) unawaited(_outbox.refresh());
      }
    });
    unawaited(_bootstrap());
  }

  void _onMailboxChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _inbox.dispose();
    _outbox.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await _inbox.refresh();
    await _resumePendingCompose();
  }

  Future<void> _resumePendingCompose() async {
    final target = _pendingComposeTo;
    if (target != null && target.isNotEmpty && mounted && !_inbox.needAuth) {
      _pendingComposeTo = null;
      final sent = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => PmComposeScreen(toUser: target, service: _service),
        ),
      );
      if (sent == true && mounted) await _refreshMailboxes();
    }
  }

  Future<void> _refreshMailboxes() async {
    await Future.wait([
      _inbox.refresh(supersede: true),
      _outbox.refresh(supersede: true),
    ]);
  }

  Future<void> _selectTab(int index) async {
    if (_tab == index) return;
    setState(() => _tab = index);
    if (!_mailbox.loaded) {
      await _mailbox.refresh();
    }
  }

  Future<void> _openConversation(PmConversation item) async {
    if (_selected?.id == item.id || _switching) return;
    _switching = true;
    final generation = _selectionGeneration;
    try {
      if (!await (_chatKey.currentState?.prepareToLeave() ??
          Future.value(true))) {
        return;
      }
      if (!mounted || generation != _selectionGeneration) return;
      setState(() {
        _selected = item;
        _chatKey = GlobalKey();
      });
    } finally {
      _switching = false;
    }
  }

  Future<void> _closeConversation() async {
    if (_switching) return;
    _switching = true;
    try {
      if (!await (_chatKey.currentState?.prepareToLeave() ??
          Future.value(true))) {
        return;
      }
      if (!mounted) return;
      setState(() => _selected = null);
      await _refreshMailboxes();
    } finally {
      _switching = false;
    }
  }

  Future<void> _openCompose() async {
    final sent = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => PmComposeScreen(service: _service)),
    );
    if (sent == true && mounted) await _refreshMailboxes();
  }

  Future<void> _syncWebsiteLogin() async {
    final saved = await openWebsiteLoginScreen(context);
    if (!mounted || saved != true) return;
    await ref.read(websiteSessionProvider.notifier).reload();
    await _refreshMailboxes();
    if (mounted) await _resumePendingCompose();
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
          loginHint: '可在官网查看和发送私信。',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final website = ref.watch(websiteSessionProvider);
    final phone = AppLayout.isPhone(context);
    final mailbox = _mailbox;
    final unread = _inbox.items.where((e) => e.isUnread).length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        final selection = _selected;
        final sidebar = Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: '搜索已加载会话',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: '清除搜索',
                          onPressed: () => setState(_search.clear),
                          icon: const Icon(Icons.close_rounded),
                        ),
                  isDense: true,
                  filled: true,
                  fillColor: scheme.surfaceContainerLow,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: _PmSegmentedTabs(
                index: _tab,
                inboxCount: _inbox.items.length,
                outboxCount: _outbox.items.length,
                unread: unread,
                onChanged: _selectTab,
              ),
            ),
            Expanded(
              child: _PmListBody(
                key: ValueKey(_tab),
                mailbox: mailbox,
                selectedId: selection?.id,
                query: _search.text,
                emptyLabel: _tab == 0 ? '还没有收到短信' : '还没有发出的短信',
                emptyHint: _tab == 0 ? '和好友互相发送站内短信后会出现在这里' : '写一封新短信开始对话',
                onRetry: () => mailbox.refresh(),
                onSyncLogin: _syncWebsiteLogin,
                onOpenWeb: _openWebFallback,
                onOpen: _openConversation,
                onRefresh: () => mailbox.refresh(),
              ),
            ),
            if (wide && !mailbox.needAuth)
              Padding(
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: _openCompose,
                    icon: const Icon(Icons.edit_square),
                    label: const Text('发起聊天'),
                  ),
                ),
              ),
          ],
        );
        return Scaffold(
          extendBodyBehindAppBar: false,
          appBar: !wide && selection != null
              ? null
              : AppBar(
                  titleSpacing: phone ? 8 : 16,
                  title: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '站内短信',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        website.isSynced
                            ? (unread > 0 ? '已加载会话中 $unread 条未读' : '已加载会话暂无未读')
                            : '需同步网站登录后使用',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                    ],
                  ),
                  actions: [
                    IconButton(
                      tooltip: '刷新',
                      onPressed: mailbox.refreshing
                          ? null
                          : () => mailbox.refresh(),
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                    IconButton(
                      tooltip: website.isSynced ? '网站登录状态' : '登录 Bangumi 网站',
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
          floatingActionButton: mailbox.needAuth || selection != null || wide
              ? null
              : FloatingActionButton(
                  onPressed: _openCompose,
                  elevation: 2,
                  child: const Icon(Icons.edit_rounded),
                ),
          body: Row(
            children: [
              SizedBox(
                width: wide
                    ? 320
                    : selection == null
                    ? constraints.maxWidth
                    : 0,
                child: Offstage(
                  offstage: !wide && selection != null,
                  child: sidebar,
                ),
              ),
              if (wide)
                VerticalDivider(
                  width: 1,
                  color: scheme.outlineVariant.withValues(alpha: .5),
                ),
              Expanded(
                child: Offstage(
                  offstage: !wide && selection == null,
                  child: selection == null
                      ? ColoredBox(
                          color: scheme.surfaceContainerLow,
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.forum_outlined,
                                  size: 56,
                                  color: scheme.outline,
                                ),
                                const SizedBox(height: 16),
                                const Text('选择一个会话，开始聊天'),
                                const SizedBox(height: 8),
                                Text(
                                  '在这里继续和 Bangumi 好友的对话',
                                  style: TextStyle(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : PmConversationScreen(
                          key: _chatKey,
                          service: _service,
                          conversationId: selection.id,
                          title: selection.title,
                          peerName: selection.peerName,
                          peerAvatar: selection.avatarUrl,
                          onClose: _closeConversation,
                          onMessagesChanged: _refreshMailboxes,
                        ),
                ),
              ),
            ],
          ),
        );
      },
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
                  fontWeight: FontWeight.w600,
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
        title: '需要网站登录',
        message: error ?? '登录 Bangumi 官网后即可查看和发送私信。',
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
          ? scheme.primaryContainer.withValues(alpha: .6)
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
                  child: _PmAvatar(
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
                      if (item.title.isNotEmpty && item.title != item.peerName)
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      if (item.preview.isNotEmpty)
                        Text(
                          item.preview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: scheme.onSurfaceVariant,
                          ),
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

class PmConversationScreen extends ConsumerStatefulWidget {
  const PmConversationScreen({
    super.key,
    required this.conversationId,
    required this.title,
    this.peerName = '',
    this.peerAvatar = '',
    this.service,
    this.onClose,
    this.onMessagesChanged,
  });

  final String conversationId;
  final String title;
  final String peerName;
  final String peerAvatar;
  final PmService? service;
  final Future<void> Function()? onClose;
  final Future<void> Function()? onMessagesChanged;

  @override
  ConsumerState<PmConversationScreen> createState() =>
      _PmConversationScreenState();
}

class _PmConversationScreenState extends ConsumerState<PmConversationScreen> {
  late final _service = widget.service ?? PmService.shared;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();

  PmConversationDetail? _detail;
  PmDraftEditing? _draftEditing;
  bool _loading = true;
  bool _sending = false;
  bool _showLatest = false;
  String? _error;
  String? _threadId;
  int _requestId = 0;
  bool _sessionChanged = false;
  String? _loadedThread;
  List<PmThreadFilter> _threads = const [];

  Future<bool> prepareToLeave() async {
    if (_sending) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('正在发送，请稍候再切换会话')));
      return false;
    }
    final draft = _draftEditing?.controller;
    if (draft?.dirty != true) return true;
    return await _draftEditing!.flush();
  }

  @override
  void initState() {
    super.initState();
    _watchPmSession(ref, _onWebsiteSessionChanged);
    _scroll.addListener(() {
      final show = _scroll.hasClients && _scroll.position.extentBefore > 180;
      if (mounted && show != _showLatest) setState(() => _showLatest = show);
    });
    unawaited(_load());
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onWebsiteSessionChanged() {
    if (!mounted) return;
    _draftEditing?.suspend();
    _requestId++;
    _input.clear();
    setState(() {
      _sessionChanged = true;
      _detail = null;
      _threads = const [];
      _loading = _sending = false;
      _error = '网站登录已变化，请返回后重新打开私信';
    });
  }

  Future<void> _load() async {
    if (!mounted || _sessionChanged) return;
    final requestId = ++_requestId;
    final draft = _draftEditing?.controller;
    setState(() => _loading = true);
    if (draft?.dirty == true && !await draft!.flush()) {
      if (mounted && requestId == _requestId) setState(() => _loading = false);
      return;
    }
    if (!mounted || requestId != _requestId) return;
    // Capture the requested thread up-front so a slow response for a
    // previously-selected thread cannot overwrite the current one (and so
    // _send can never reply through a stale thread's form).
    final requestedThread = _threadId;
    final followLatest =
        _detail == null ||
        requestedThread != _loadedThread ||
        _sending ||
        !_scroll.hasClients ||
        _scroll.position.extentBefore < 120;
    setState(() {
      _loading = true;
      _error = null;
      if (requestedThread != _loadedThread) _detail = null;
    });
    try {
      final detail = await _service.loadConversation(
        widget.conversationId,
        threadId: requestedThread,
      );
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _detail = detail;
        _threads = detail.threads;
        _loadedThread = requestedThread;
        _loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            requestId == _requestId &&
            followLatest &&
            _scroll.hasClients) {
          _scroll.jumpTo(0);
        }
      });
    } catch (error) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _loading = false;
        if (error is PmAuthException) _detail = null;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _send() async {
    final detail = _detail;
    final editing = _draftEditing;
    final draft = editing?.controller;
    final text = _input.text.trim();
    if (!mounted ||
        _sessionChanged ||
        detail == null ||
        text.isEmpty ||
        _sending ||
        _loading ||
        _error != null ||
        editing?.ready != true ||
        draft == null) {
      return;
    }
    final requestId = _requestId;
    setState(() => _sending = true);
    try {
      if (!await editing!.flush()) return;
      if (!mounted || _sessionChanged || requestId != _requestId) return;
      await _service.reply(form: detail.form, body: text);
      final cleared = await draft.markSent();
      if (!mounted || _sessionChanged || requestId != _requestId) return;
      if (!cleared) return;
      await editing.restart();
      if (mounted && !_sessionChanged) await _load();
      if (mounted && !_sessionChanged) {
        unawaited(widget.onMessagesChanged?.call());
      }
    } catch (error) {
      if (!mounted || _sessionChanged) return;
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
    final title = _sessionChanged
        ? '站内短信'
        : detail?.peerName.isNotEmpty == true
        ? detail!.peerName
        : (widget.peerName.isNotEmpty ? widget.peerName : widget.title);
    final avatar = _sessionChanged
        ? ''
        : widget.peerAvatar.isNotEmpty
        ? widget.peerAvatar
        : (detail?.messages
                  .where((m) => !m.isSelf && m.avatarUrl.isNotEmpty)
                  .map((m) => m.avatarUrl)
                  .firstOrNull ??
              '');

    final canonicalThread = _loadedThread?.isNotEmpty == true
        ? _loadedThread!
        : detail?.threads
                  .where((thread) => thread.current && thread.id.isNotEmpty)
                  .firstOrNull
                  ?.id ??
              detail?.form.related ??
              '';
    return PmDraftEditor(
      service: _service,
      kind: PmDraftKind.reply,
      onClose: widget.onClose,
      body: _input,
      conversationId: widget.conversationId,
      threadId: canonicalThread,
      contextReady: detail != null,
      replyRecipient: detail?.peerUserId.isNotEmpty == true
          ? detail!.peerUserId
          : detail?.form.msgReceivers ?? '',
      replyTitle: detail?.form.msgTitle ?? widget.title,
      onSessionInvalidated: _onWebsiteSessionChanged,
      onOwnerVerified: () {
        if (_sessionChanged && mounted) {
          setState(() => _sessionChanged = false);
          unawaited(_load());
        }
      },
      onSentCleanup: () => unawaited(_load()),
      builder: (context, editing) {
        _draftEditing = editing;
        return Scaffold(
          appBar: AppBar(
            titleSpacing: 12,
            leading: widget.onClose == null
                ? null
                : IconButton(
                    tooltip: '返回会话列表',
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
            title: Row(
              children: [
                _PmAvatar(
                  url: editing.ownerVerified ? avatar : '',
                  name: editing.ownerVerified ? title : '站内短信',
                  radius: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        editing.ownerVerified ? title : '站内短信',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (editing.ownerVerified &&
                          !_sessionChanged &&
                          widget.title.isNotEmpty &&
                          widget.title != title)
                        Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: '刷新',
                onPressed: _loading || _sessionChanged ? null : _load,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          body: !editing.ownerVerified
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: editing.status,
                  ),
                )
              : Column(
                  children: [
                    if (_threads.length > 1)
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
                        child: Row(
                          children: _threads.map((thread) {
                            final selected =
                                (_threadId == null && thread.current) ||
                                _threadId == thread.id;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                materialTapTargetSize:
                                    MaterialTapTargetSize.padded,
                                label: Text(thread.title),
                                selected: selected,
                                onSelected: _sending || _loading
                                    ? null
                                    : (_) async {
                                        if (editing.controller != null &&
                                            !await editing.flush()) {
                                          return;
                                        }
                                        if (!mounted || _sessionChanged) return;
                                        setState(() => _threadId = thread.id);
                                        await _load();
                                      },
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    if (_error != null && detail != null)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          _error!,
                          style: TextStyle(color: scheme.error),
                        ),
                      ),
                    Expanded(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerLow,
                        ),
                        child: _loading && detail == null
                            ? const Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                ),
                              )
                            : Stack(
                                children: [
                                  Positioned.fill(child: _messageList(detail)),
                                  if (_loading)
                                    const Positioned(
                                      top: 0,
                                      left: 0,
                                      right: 0,
                                      child: LinearProgressIndicator(
                                        minHeight: 2,
                                      ),
                                    ),
                                  if (_showLatest)
                                    Positioned(
                                      right: 16,
                                      bottom: 16,
                                      child: FilledButton.tonalIcon(
                                        onPressed: () => _scroll.animateTo(
                                          0,
                                          duration: const Duration(
                                            milliseconds: 220,
                                          ),
                                          curve: Curves.easeOut,
                                        ),
                                        icon: const Icon(
                                          Icons.arrow_downward_rounded,
                                          size: 18,
                                        ),
                                        label: const Text('回到最新'),
                                      ),
                                    ),
                                ],
                              ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: editing.status,
                    ),
                    _ComposerBar(
                      controller: _input,
                      focusNode: _focus,
                      sending: _sending,
                      enabled:
                          detail != null &&
                          !_sending &&
                          !_loading &&
                          _error == null &&
                          !_sessionChanged &&
                          editing.ready,
                      onSend: _send,
                    ),
                  ],
                ),
        );
      },
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
              if (!_sessionChanged)
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
    final selfAvatar = ref.watch(
      sessionProvider.select((state) => state.user?.avatarUrl ?? ''),
    );
    return ListView.builder(
      controller: _scroll,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final messageIndex = messages.length - 1 - index;
        final msg = messages[messageIndex];
        final prev = messageIndex > 0 ? messages[messageIndex - 1] : null;
        final showTime =
            msg.timeText.isNotEmpty && msg.timeText != prev?.timeText;
        return Column(
          children: [
            if (showTime)
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 18),
                child: Text(
                  msg.timeText,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            _ChatBubble(
              message: msg,
              avatar: msg.avatarUrl.isNotEmpty
                  ? msg.avatarUrl
                  : msg.isSelf
                  ? selfAvatar
                  : widget.peerAvatar,
            ),
          ],
        );
      },
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message, required this.avatar});

  final PmMessage message;
  final String avatar;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final self = message.isSelf;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bubble = ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: (constraints.maxWidth - 104).clamp(80.0, 560.0),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: self
                    ? scheme.primaryContainer
                    : scheme.surfaceContainerLowest,
                border: Border.all(
                  color: self
                      ? scheme.primary.withValues(alpha: .12)
                      : scheme.outlineVariant.withValues(alpha: .35),
                ),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(self ? 12 : 3),
                  topRight: Radius.circular(self ? 3 : 12),
                  bottomLeft: const Radius.circular(12),
                  bottomRight: const Radius.circular(12),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                child: SelectableText(
                  message.contentText,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.5,
                    fontWeight: FontWeight.w400,
                    fontFamilyFallback: const [
                      'Microsoft YaHei UI',
                      'Segoe UI Emoji',
                      'Apple Color Emoji',
                      'Noto Color Emoji',
                    ],
                    color: self ? scheme.onPrimaryContainer : scheme.onSurface,
                  ),
                ),
              ),
            ),
          );
          final portrait = _PmAvatar(
            url: avatar,
            name: self ? '我' : message.name,
            radius: 20,
          );
          return Row(
            mainAxisAlignment: self
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!self) ...[portrait, const SizedBox(width: 10)],
              Flexible(
                child: Column(
                  crossAxisAlignment: self
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    if (!self && message.name.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: Text(
                          message.name,
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    bubble,
                  ],
                ),
              ),
              if (self) ...[const SizedBox(width: 10), portrait],
            ],
          );
        },
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 560;
        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.enter, control: true): () {
              if (enabled &&
                  controller.text.trim().isNotEmpty &&
                  controller.value.composing.isCollapsed) {
                onSend();
              }
            },
          },
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surface,
              border: Border(
                top: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: .5),
                ),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: controller,
                      focusNode: focusNode,
                      enabled: enabled,
                      minLines: desktop ? 3 : 1,
                      maxLines: desktop ? 6 : 4,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        hintText: '输入回复…',
                        filled: true,
                        fillColor: scheme.surfaceContainerLow,
                        contentPadding: const EdgeInsets.all(12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: desktop
                              ? Text(
                                  'Enter 换行 · Ctrl + Enter 发送',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                )
                              : const SizedBox.shrink(),
                        ),
                        ValueListenableBuilder<TextEditingValue>(
                          valueListenable: controller,
                          builder: (context, value, _) => FilledButton.icon(
                            onPressed: enabled && value.text.trim().isNotEmpty
                                ? onSend
                                : null,
                            icon: sending
                                ? const SizedBox.square(
                                    dimension: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(
                                    Icons.arrow_upward_rounded,
                                    size: 18,
                                  ),
                            label: Text(sending ? '发送中' : '发送'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class PmComposeScreen extends ConsumerStatefulWidget {
  const PmComposeScreen({super.key, this.toUser, this.service, this.draftId});

  final String? toUser;
  final PmService? service;
  final String? draftId;

  @override
  ConsumerState<PmComposeScreen> createState() => _PmComposeScreenState();
}

class _PmComposeScreenState extends ConsumerState<PmComposeScreen> {
  late final _service = widget.service ?? PmService.shared;
  final _to = TextEditingController();
  final _title = TextEditingController();
  final _body = TextEditingController();
  PmComposeParams? _params;
  PmDraftEditing? _draftEditing;
  bool _loading = false;
  bool _sending = false;
  bool _choosingDraft = false;
  bool _sentFromOtherDraft = false;
  String? _error;
  String _recipient = '';
  String? _preparedRecipient;
  int _prepareGeneration = 0;
  Future<void>? _preparing;
  bool _sessionChanged = false;

  @override
  void initState() {
    super.initState();
    _watchPmSession(ref, _onWebsiteSessionChanged);
    _to.addListener(_recipientChanged);
    final initial = widget.toUser?.trim() ?? '';
    if (initial.isNotEmpty) {
      _to.text = initial;
    }
  }

  @override
  void dispose() {
    _prepareGeneration++;
    _to.removeListener(_recipientChanged);
    _to.dispose();
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  void _recipientChanged() {
    final next = _to.text.trim();
    if (next == _recipient) return;
    _recipient = next;
    _prepareGeneration++;
    _preparing = null;
    setState(() {
      _params = null;
      _preparedRecipient = null;
      _loading = false;
      if (!_sessionChanged) _error = null;
    });
  }

  void _onWebsiteSessionChanged() {
    if (!mounted) return;
    _draftEditing?.suspend();
    _sessionChanged = true;
    _prepareGeneration++;
    _preparing = null;
    _to.clear();
    _title.clear();
    _body.clear();
    setState(() {
      _params = null;
      _preparedRecipient = null;
      _loading = _sending = false;
      _error = '网站登录已变化，请返回后重新打开私信';
    });
  }

  Future<void> _prepare() {
    if (!mounted || _sessionChanged) return Future.value();
    if (_preparing != null) return _preparing!;
    final user = _recipient;
    if (user.isEmpty) {
      setState(() => _error = '请填写对方用户名或 UID');
      return Future.value();
    }
    final generation = ++_prepareGeneration;
    setState(() {
      _loading = true;
      _params = null;
      _preparedRecipient = null;
      _error = null;
    });
    return _preparing = _fetchRecipient(user, generation);
  }

  Future<void> _fetchRecipient(String user, int generation) async {
    try {
      final params = await _service.loadComposeParams(user);
      if (!mounted || generation != _prepareGeneration || _sessionChanged) {
        return;
      }
      setState(() {
        _params = params;
        _preparedRecipient = user;
      });
    } catch (error) {
      if (!mounted || generation != _prepareGeneration || _sessionChanged) {
        return;
      }
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted && generation == _prepareGeneration && !_sessionChanged) {
        _preparing = null;
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _send() async {
    final editing = _draftEditing;
    final draft = editing?.controller;
    if (!mounted ||
        _sending ||
        _sessionChanged ||
        editing?.ready != true ||
        draft == null) {
      return;
    }
    final user = _recipient;
    final title = _title.text;
    final body = _body.text;
    setState(() => _sending = true);
    try {
      if (!await editing!.flush()) return;
      if (!mounted || _sessionChanged) return;
      if (_params == null || _preparedRecipient != user) await _prepare();
      if (!mounted || _sessionChanged || _recipient != user) return;
      final params = _params;
      if (params == null || _preparedRecipient != user) return;
      await _service.compose(params: params, title: title, body: body);
      final cleared = await draft.markSent();
      if (!mounted || _sessionChanged || !cleared) return;
      editing.allowPop();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop(true);
      });
    } catch (error) {
      if (!mounted || _sessionChanged) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _chooseDraft() async {
    if (_choosingDraft || _sending || _draftEditing?.ready != true) return;
    setState(() => _choosingDraft = true);
    try {
      if (!await _draftEditing!.flush() || !mounted || _sessionChanged) return;
      final selected = await pickPmComposeDraft(
        context,
        ref,
        _service,
        excludeId: _draftEditing?.controller?.data.id,
      );
      if (!mounted || _sessionChanged || selected == null) return;
      final sent = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) =>
              PmComposeScreen(service: _service, draftId: selected.id),
        ),
      );
      if (mounted && sent == true) setState(() => _sentFromOtherDraft = true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('草稿打开失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _choosingDraft = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pad = AppLayout.pagePadding(context);
    return PmDraftEditor(
      service: _service,
      kind: PmDraftKind.compose,
      recipient: _to,
      title: _title,
      body: _body,
      initialRecipient: widget.toUser,
      draftId: widget.draftId,
      sentElsewhere: _sentFromOtherDraft,
      onSessionInvalidated: _onWebsiteSessionChanged,
      onOwnerVerified: () {
        if (mounted && _sessionChanged) setState(() => _sessionChanged = false);
      },
      onRestored: () {
        if (_to.text.trim().isNotEmpty) unawaited(_prepare());
      },
      builder: (context, editing) {
        _draftEditing = editing;
        return Scaffold(
          appBar: AppBar(
            title: const Text('写短信'),
            actions: [
              IconButton(
                tooltip: '其他草稿',
                onPressed: !editing.ready || _sending || _choosingDraft
                    ? null
                    : _chooseDraft,
                icon: const Icon(Icons.drafts_outlined),
              ),
              IconButton(
                tooltip: '新建草稿',
                onPressed: !editing.canStartNew || _sending || _choosingDraft
                    ? null
                    : editing.newCompose,
                icon: const Icon(Icons.note_add_outlined),
              ),
            ],
          ),
          body: ListView(
            padding: EdgeInsets.fromLTRB(pad, 8, pad, 28),
            children: [
              editing.status,
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
                enabled:
                    !_sending &&
                    !_choosingDraft &&
                    !_sessionChanged &&
                    editing.ready,
                decoration: InputDecoration(
                  labelText: '收件人',
                  hintText: '用户名或 UID',
                  prefixIcon: const Icon(Icons.person_outline_rounded),
                  suffixIcon: IconButton(
                    tooltip: '校验收件人',
                    onPressed:
                        !editing.ready ||
                            _loading ||
                            _sending ||
                            _sessionChanged
                        ? null
                        : _prepare,
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
                enabled:
                    !_sending &&
                    !_choosingDraft &&
                    !_sessionChanged &&
                    editing.ready,
                decoration: const InputDecoration(
                  labelText: '标题',
                  prefixIcon: Icon(Icons.title_rounded),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _body,
                enabled:
                    !_sending &&
                    !_choosingDraft &&
                    !_sessionChanged &&
                    editing.ready,
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
                Text(
                  _error!,
                  style: TextStyle(color: scheme.error, height: 1.4),
                ),
              ],
              if (_params != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
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
                      Expanded(
                        child: Text(
                          '收件人已确认，可以发送',
                          style: TextStyle(
                            color: scheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 22),
              FilledButton(
                onPressed:
                    _sending ||
                        _choosingDraft ||
                        _sessionChanged ||
                        !editing.ready
                    ? null
                    : _send,
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
      },
    );
  }
}

class _PmAvatar extends StatelessWidget {
  const _PmAvatar({required this.url, required this.name, this.radius = 22});
  final String url;
  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final resolved = BangumiEndpoints.imageUrl(url);
    final letter = name.trim().isEmpty
        ? '?'
        : name.trim().characters.first.toUpperCase();
    final fallback = ColoredBox(
      color: scheme.primaryContainer,
      child: Center(
        child: Text(
          letter,
          style: TextStyle(
            color: scheme.onPrimaryContainer,
            fontSize: radius * .78,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
    return Semantics(
      image: true,
      label: '${name.isEmpty ? '用户' : name}的头像',
      child: ExcludeSemantics(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox.square(
            dimension: radius * 2,
            child: resolved.isEmpty
                ? fallback
                : CachedNetworkImage(
                    imageUrl: resolved,
                    fit: BoxFit.cover,
                    placeholder: (_, _) => fallback,
                    errorWidget: (_, _, _) => fallback,
                  ),
          ),
        ),
      ),
    );
  }
}

/// Opens native inbox (or compose when [composeTo] is set).
Future<void> openPmPage(BuildContext context, {String? composeTo}) async {
  await Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => PmPage(composeTo: composeTo)));
}
