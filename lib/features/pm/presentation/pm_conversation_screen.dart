import '../../../state/service_providers.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../../../widgets/social_chat_style.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/pm_models.dart';
import '../../../core/network/pm_service.dart';
import '../../../widgets/pm_draft_editor.dart';
import '../../../core/storage/pm_draft_store.dart';
import 'pm_session_listener.dart';
import '../../../state/session_controller.dart';
import 'pm_chat_widgets.dart';
import 'pm_avatar.dart';
import '../../../state/pm_send_queue_controller.dart';
import '../../../models/pm_send_command.dart';
import 'pm_send_queue_view.dart';

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
      PmConversationScreenState();
}

/// The mailbox shell uses [prepareToLeave] before changing selection and
/// [invalidateWebsiteSession] to suspend the selected chat on account changes.
/// Request, input and draft state otherwise remain private to this screen.
class PmConversationScreenState extends ConsumerState<PmConversationScreen> {
  late final _service = widget.service ?? pmServiceFor(context);
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
  final _seenSent = <String>{};

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
    watchPmSession(ref, invalidateWebsiteSession);
    _scroll.addListener(() {
      final show = _scroll.hasClients && _scroll.position.extentBefore > 180;
      if (mounted && show != _showLatest) setState(() => _showLatest = show);
    });
    ref.listenManual(pmSendQueueProvider(_service), (_, queue) {
      final fresh = queue.entries
          .where(
            (e) =>
                e.conversationId == widget.conversationId &&
                e.status == PmSendStatus.sent &&
                !_seenSent.contains(e.id),
          )
          .toList();
      _seenSent.addAll(fresh.map((e) => e.id));
      if (fresh.isNotEmpty &&
          _input.text.isEmpty &&
          !_sending &&
          !_loading &&
          !_sessionChanged) {
        unawaited(_load());
      }
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

  void invalidateWebsiteSession() {
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
      String canonical(PmConversationDetail value) =>
          requestedThread?.isNotEmpty == true
          ? requestedThread!
          : value.threads
                    .where((t) => t.current && t.id.isNotEmpty)
                    .firstOrNull
                    ?.id ??
                value.form.related;
      if (_detail != null &&
          _input.text.isNotEmpty &&
          requestedThread == _loadedThread &&
          canonical(detail) != canonical(_detail!)) {
        setState(() => _loading = false);
        return;
      }
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
        (_loading && !ref.read(pmSendQueueProvider(_service)).supported) ||
        _error != null ||
        editing?.ready != true ||
        draft == null) {
      return;
    }
    final requestId = _requestId;
    setState(() => _sending = true);
    try {
      final queue = ref.read(pmSendQueueProvider(_service));
      if (queue.supported) {
        final command = await queue.enqueue(
          draft,
          receiver: detail.form.msgReceivers,
          related: detail.form.related,
        );
        if (command != null &&
            mounted &&
            !_sessionChanged &&
            draft.data.body.isEmpty &&
            _input.text == text) {
          _input.clear();
        }
        if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
        return;
      }
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
      onSessionInvalidated: invalidateWebsiteSession,
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
            backgroundColor: SocialChatStyle.paper(context),
            surfaceTintColor: Colors.transparent,
            scrolledUnderElevation: 0,
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
                PmAvatar(
                  url: editing.ownerVerified ? avatar : '',
                  name: editing.ownerVerified ? title : '私聊',
                  radius: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        editing.ownerVerified ? title : '私聊',
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
                          color: SocialChatStyle.canvas(context),
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
                    PmComposerBar(
                      controller: _input,
                      focusNode: _focus,
                      sending: _sending,
                      enabled:
                          detail != null &&
                          !_sending &&
                          (!_loading ||
                              ref
                                  .read(pmSendQueueProvider(_service))
                                  .supported) &&
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
    final queue = ref.watch(pmSendQueueProvider(_service));
    final queued = queue.entries
        .where(
          (command) =>
              command.conversationId == widget.conversationId &&
              command.status != PmSendStatus.cancelled &&
              (_threadId == null ||
                  _threadId!.isEmpty ||
                  command.threadId == _threadId) &&
              !(command.status == PmSendStatus.sent &&
                  command.baseline >= 0 &&
                  detail != null &&
                  PmSendQueueController.matchingMessages(detail, command.body) >
                      command.baseline),
        )
        .toList();
    if (messages.isEmpty && queued.isEmpty) {
      return const Center(child: Text('暂无消息'));
    }
    final selfAvatar = ref.watch(
      sessionProvider.select((state) => state.user?.avatarUrl ?? ''),
    );
    return ListView.builder(
      controller: _scroll,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
      itemCount: messages.length + queued.length,
      itemBuilder: (context, index) {
        if (index < queued.length) {
          final command = queued[queued.length - 1 - index];
          return PmQueuedBubble(
            key: ValueKey('queued-${command.id}'),
            command: command,
            queue: queue,
            avatar: selfAvatar,
          );
        }
        final messageIndex = messages.length - 1 - (index - queued.length);
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
            PmChatBubble(
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
