import '../state/service_providers.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../widgets/social_chat_style.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/pm_models.dart';
import '../models/pm_contact.dart';
import '../models/bangumi_models.dart';
import '../state/pm_contacts_controller.dart';
import '../state/pm_send_queue_controller.dart';
import '../models/pm_send_command.dart';
import '../features/pm/presentation/pm_send_queue_view.dart';
import '../core/layout/app_layout.dart';
import '../core/network/pm_service.dart';
import '../state/website_session_controller.dart';
import '../state/pm_mailbox_controller.dart';
import '../state/session_controller.dart';
import 'community_page.dart';
import 'website_login_screen.dart';
import '../features/pm/presentation/pm_contacts_view.dart';
import '../features/pm/presentation/pm_conversation_screen.dart';
import '../features/pm/presentation/pm_compose_screen.dart';
export '../features/pm/presentation/pm_conversation_screen.dart';
export '../features/pm/presentation/pm_compose_screen.dart';

/// Native 站内短信：Cookie 会话 + HTML 解析；失败时回退官网 WebView。
class PmPage extends ConsumerStatefulWidget {
  const PmPage({
    super.key,
    this.composeTo,
    this.service,
    this.embedded = false,
    this.friendsLoader,
    this.friendsRevision = 0,
  });
  final bool embedded;
  final int friendsRevision;
  final Future<List<BangumiUser>> Function(String username)? friendsLoader;

  final String? composeTo;
  final PmService? service;

  @override
  ConsumerState<PmPage> createState() => _PmPageState();
}

class _PmPageState extends ConsumerState<PmPage> {
  late final _service = widget.service ?? pmServiceFor(context);
  late final _inbox = PmMailboxController(_service.loadInbox);
  late final _outbox = PmMailboxController(_service.loadOutbox);
  late final _contacts = PmContactsController(
    inbox: _inbox,
    outbox: _outbox,
    loadFriends: () {
      final user = ref.read(sessionProvider).user;
      if (user == null) return Future.value(<BangumiUser>[]);
      return widget.friendsLoader?.call(user.username) ??
          communityServiceFor(
            context,
          ).loadAllFriends(user.username, pageSize: 100, refresh: true);
    },
  );
  String? _openingContactKey;
  String? _pendingComposeTo;
  PmConversation? _selected;
  PmConversation? _resumeAfterLogin;
  GlobalKey<PmConversationScreenState> _chatKey = GlobalKey();
  bool _switching = false;
  int _selectionGeneration = 0;
  final _search = TextEditingController();
  Timer? _queueRefreshTimer;
  final _sentCommands = <String>{};

  @override
  void initState() {
    super.initState();
    _pendingComposeTo = widget.composeTo?.trim();
    _contacts.addListener(_onMailboxChanged);
    ref.listenManual(sessionProvider.select((state) => state.user?.id), (
      previous,
      next,
    ) {
      if (previous == next) return;
      _chatKey.currentState?.invalidateWebsiteSession();
      _selectionGeneration++;
      _resumeAfterLogin = null;
      _openingContactKey = null;
      _search.clear();
      _contacts.reset(clearFriends: true, requireAuth: true);
      setState(() => _selected = null);
      if (next != null) unawaited(_contacts.refreshFriends());
    });
    ref.listenManual(websiteSessionProvider, (previous, next) {
      final keyChanged =
          previous?.snapshot?.authenticationKey !=
          next.snapshot?.authenticationKey;
      final accessChanged =
          previous?.status != next.status &&
              const {
                WebsiteAccessStatus.expired,
                WebsiteAccessStatus.mismatch,
                WebsiteAccessStatus.missing,
                WebsiteAccessStatus.challenge,
              }.contains(next.status) ||
          next.isSynced && _inbox.needAuth;
      if (!next.ready || (!keyChanged && !accessChanged)) {
        return;
      }
      _contacts.reset(requireAuth: !next.isSynced);
      _resumeAfterLogin ??= _selected;
      _chatKey.currentState?.invalidateWebsiteSession();
      _selectionGeneration++;
      setState(() => _selected = null);
      if (next.isSynced) {
        unawaited(_contacts.syncHistory());
        unawaited(_resumeConversationAfterLogin());
      }
    });
    ref.listenManual(pmSendQueueProvider(_service), (_, queue) {
      final fresh = queue.entries
          .where(
            (e) =>
                e.status == PmSendStatus.sent && !_sentCommands.contains(e.id),
          )
          .toList();
      _sentCommands.addAll(fresh.map((e) => e.id));
      if (fresh.isNotEmpty) {
        _queueRefreshTimer?.cancel();
        _queueRefreshTimer = Timer(const Duration(milliseconds: 400), () {
          if (mounted) unawaited(_refreshMailboxes());
        });
      }
    });
    unawaited(_bootstrap());
  }

  void _onMailboxChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant PmPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.friendsRevision != widget.friendsRevision) {
      unawaited(_contacts.refreshFriends());
    }
  }

  @override
  void dispose() {
    _queueRefreshTimer?.cancel();
    _contacts.dispose();
    _inbox.dispose();
    _outbox.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    unawaited(_contacts.refresh());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_resumePendingCompose());
    });
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

  Future<void> _refreshMailboxes() =>
      _contacts.refresh(includeFriends: false, supersede: true);

  Future<void> _openContact(PmContact person) async {
    if (_openingContactKey != null || _switching) return;
    var generation = _selectionGeneration;
    final account = ref.read(sessionProvider).user?.id;
    setState(() => _openingContactKey = person.key);
    try {
      if (_contacts.needAuth) {
        await _syncWebsiteLogin();
        if (!mounted ||
            _contacts.needAuth ||
            ref.read(sessionProvider).user?.id != account) {
          return;
        }
        generation = _selectionGeneration;
      }
      if (!mounted || generation != _selectionGeneration) return;
      final current =
          _contacts.items.where((row) => row.key == person.key).firstOrNull ??
          person;
      final latest = current.latest;
      if (latest != null) {
        await _openConversation(latest);
        return;
      }
      if (!await (_chatKey.currentState?.prepareToLeave() ??
          Future.value(true))) {
        return;
      }
      if (!mounted || generation != _selectionGeneration) return;
      final recipient = person.username.isNotEmpty
          ? person.username
          : person.friend?.id != null && person.friend!.id > 0
          ? '${person.friend!.id}'
          : '';
      if (recipient.isEmpty) return;
      final sent = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => PmComposeScreen(toUser: recipient, service: _service),
        ),
      );
      if (sent == true && mounted && generation == _selectionGeneration) {
        unawaited(_refreshMailboxes());
      }
    } finally {
      if (mounted) setState(() => _openingContactKey = null);
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
        _resumeAfterLogin = null;
        _chatKey = GlobalKey();
      });
    } finally {
      _switching = false;
    }
  }

  Future<void> _closeConversation() async {
    _resumeAfterLogin = null;
    if (_switching) return;
    _switching = true;
    try {
      if (!await (_chatKey.currentState?.prepareToLeave() ??
          Future.value(true))) {
        return;
      }
      if (!mounted) return;
      setState(() => _selected = null);
      unawaited(_refreshMailboxes());
    } finally {
      _switching = false;
    }
  }

  Future<void> _openCompose() async {
    if (_openingContactKey != null || _switching) return;
    _resumeAfterLogin = null;
    final sent = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => PmComposeScreen(service: _service)),
    );
    if (sent == true && mounted) await _refreshMailboxes();
  }

  Future<void> _syncWebsiteLogin() async {
    final saved = await openWebsiteLoginScreen(context);
    if (!mounted || saved != true) return;
    await ref.read(websiteSessionProvider.notifier).reload();
    unawaited(_refreshMailboxes());
    if (mounted) await _resumeConversationAfterLogin();
    if (mounted) await _resumePendingCompose();
  }

  Future<void> _resumeConversationAfterLogin() async {
    final conversation = _resumeAfterLogin;
    if (!mounted || _selected != null || conversation == null) return;
    await _openConversation(conversation);
  }

  Future<void> _openWebFallback() async {
    if (!await ensureWebsiteAccess(context, forceLogin: true) || !mounted) {
      return;
    }
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
    final contacts = _contacts;
    final sendQueue = ref.watch(pmSendQueueProvider(_service));
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
                  hintText: '搜索好友昵称或用户名',
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
                  fillColor: SocialChatStyle.canvas(context),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            if (sendQueue.supported)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PmSendQueueScreen(service: _service),
                    ),
                  ),
                  icon: const Icon(Icons.outbox_outlined, size: 18),
                  label: Text(
                    sendQueue.pendingCount > 0
                        ? '发送队列 · ${sendQueue.pendingCount}'
                        : '发送队列',
                  ),
                ),
              ),
            Expanded(
              child: PmContactsView(
                contacts: contacts,
                selectedId: selection?.id,
                query: _search.text,
                openingKey: _openingContactKey,
                onOpen: _openContact,
                onSyncLogin: _syncWebsiteLogin,
              ),
            ),
            if (wide && !contacts.needAuth)
              Padding(
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: _openCompose,
                    icon: const Icon(Icons.edit_square),
                    style: FilledButton.styleFrom(
                      backgroundColor: SocialChatStyle.accent(
                        context,
                      ).withValues(alpha: .10),
                      foregroundColor: SocialChatStyle.accent(context),
                    ),
                    label: const Text('发起私聊'),
                  ),
                ),
              ),
          ],
        );
        return Scaffold(
          backgroundColor: SocialChatStyle.paper(context),
          extendBodyBehindAppBar: false,
          appBar: widget.embedded || (!wide && selection != null)
              ? null
              : AppBar(
                  titleSpacing: phone ? 8 : 16,
                  title: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '私聊',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        website.isSynced
                            ? (unread > 0 ? '已加载会话中 $unread 条未读' : '已加载会话暂无未读')
                            : website.statusLabel,
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
                      onPressed: contacts.busy
                          ? null
                          : () => contacts.refresh(),
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                    IconButton(
                      tooltip: website.isSynced ? '账号验证状态' : '补充账号验证',
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
          floatingActionButton: contacts.needAuth || selection != null || wide
              ? null
              : FloatingActionButton(
                  onPressed: _openCompose,
                  elevation: 2,
                  tooltip: '发起私聊',
                  child: const Icon(CupertinoIcons.square_pencil),
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
                          color: SocialChatStyle.canvas(context),
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
                                const Text('选择一位好友，开始聊天'),
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
                      : Column(
                          children: [
                            if (contacts.items
                                    .where(
                                      (person) => person.conversations.any(
                                        (row) => row.id == selection.id,
                                      ),
                                    )
                                    .firstOrNull
                                case final person?)
                              if (person.conversations.length > 1)
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: PopupMenuButton<PmConversation>(
                                    tooltip: '与此人的其他会话',
                                    onSelected: _openConversation,
                                    itemBuilder: (_) => [
                                      for (final row in person.conversations)
                                        PopupMenuItem(
                                          value: row,
                                          child: Text(row.title),
                                        ),
                                    ],
                                    child: const Padding(
                                      padding: EdgeInsets.all(10),
                                      child: Text('历史会话 ▾'),
                                    ),
                                  ),
                                ),
                            Expanded(
                              child: PmConversationScreen(
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
                          ],
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

/// Opens native inbox (or compose when [composeTo] is set).
Future<void> openPmPage(BuildContext context, {String? composeTo}) async {
  await Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => PmPage(composeTo: composeTo)));
}
