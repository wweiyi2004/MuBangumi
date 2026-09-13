import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/pm_service.dart';
import '../core/storage/pm_draft_store.dart';
import '../state/pm_draft_controller.dart';
import '../state/session_controller.dart';
import '../state/website_session_controller.dart';
import '../screens/website_login_screen.dart';

Future<PmDraft?> pickPmComposeDraft(
  BuildContext context,
  WidgetRef ref,
  PmService service, {
  String? excludeId,
}) async {
  final user = ref.read(sessionProvider).user;
  if (user == null) return null;
  final identity = await service.verifyDraftOwner(user);
  if (!context.mounted || ref.read(sessionProvider).user?.id != user.id) {
    return null;
  }
  if (!await ref
      .read(websiteSessionProvider.notifier)
      .bindVerifiedUser(
        authenticationKey: identity.authenticationKey,
        userId: user.id,
      )) {
    return null;
  }
  if (!context.mounted) return null;
  final drafts = await ref.read(pmDraftRepositoryProvider).listCompose(user.id);
  if (!context.mounted || ref.read(sessionProvider).user?.id != user.id) {
    return null;
  }
  return showModalBottomSheet<PmDraft>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => Consumer(
      builder: (context, ref, _) {
        final account = ref.watch(
          sessionProvider.select((state) => state.user?.id),
        );
        final website = ref.watch(websiteSessionProvider);
        final same =
            account == user.id &&
            website.snapshot?.authenticationKey == identity.authenticationKey;
        final items = drafts.where((draft) => draft.id != excludeId).toList();
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .7,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    '其他短信草稿',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (!same)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('登录已变化，请返回后重试'),
                  )
                else if (items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('没有其他未发送草稿'),
                  )
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final draft = items[index];
                        return ListTile(
                          title: Text(
                            draft.title.trim().isEmpty ? '未命名短信' : draft.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '收件人：${draft.recipient.isEmpty ? '未填写' : draft.recipient}\n${draft.body}',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () {
                            if (ref.read(sessionProvider).user?.id == user.id &&
                                ref
                                        .read(websiteSessionProvider)
                                        .snapshot
                                        ?.authenticationKey ==
                                    identity.authenticationKey) {
                              Navigator.pop(context, draft);
                            }
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class PmDraftEditing {
  PmDraftEditing({
    required this.controller,
    required this.ownerVerified,
    required this.status,
    required this.suspend,
    required this.allowPop,
    required this.newCompose,
    required this.restart,
    required this.editingAllowed,
  });
  final PmDraftController? controller;
  final bool ownerVerified;
  final Widget status;
  final VoidCallback suspend;
  final VoidCallback allowPop;
  final Future<void> Function() newCompose;
  final Future<void> Function() restart;
  final bool editingAllowed;
  bool get ready =>
      editingAllowed &&
      ownerVerified &&
      controller?.ready == true &&
      controller?.sent != true;
  bool get canStartNew =>
      editingAllowed && ownerVerified && controller?.sent != true;
  Future<bool> flush() async => controller != null && await controller!.flush();
}

/// Shared lifecycle and account guard for both private-message editors.
class PmDraftEditor extends ConsumerStatefulWidget {
  const PmDraftEditor({
    super.key,
    required this.service,
    required this.kind,
    required this.body,
    required this.builder,
    required this.onSessionInvalidated,
    this.recipient,
    this.title,
    this.initialRecipient,
    this.draftId,
    this.conversationId = '',
    this.threadId = '',
    this.contextReady = true,
    this.replyRecipient = '',
    this.replyTitle = '',
    this.onRestored,
    this.onOwnerVerified,
    this.onSentCleanup,
    this.sentElsewhere = false,
    this.onClose,
  });
  final PmService service;
  final PmDraftKind kind;
  final TextEditingController? recipient;
  final TextEditingController? title;
  final TextEditingController body;
  final String? initialRecipient;
  final String? draftId;
  final String conversationId;
  final String threadId;
  final bool contextReady;
  final String replyRecipient;
  final String replyTitle;
  final VoidCallback onSessionInvalidated;
  final VoidCallback? onRestored;
  final VoidCallback? onOwnerVerified;
  final VoidCallback? onSentCleanup;
  final bool sentElsewhere;

  /// Embedded chats close their pane after flushing instead of popping the page.
  final Future<void> Function()? onClose;
  final Widget Function(BuildContext, PmDraftEditing) builder;
  @override
  ConsumerState<PmDraftEditor> createState() => _PmDraftEditorState();
}

class _PmDraftEditorState extends ConsumerState<PmDraftEditor> {
  PmDraftController? _draft;
  bool _ownerVerified = false;
  bool _opening = true;
  bool _applying = false;
  bool _closing = false;
  bool _allowPop = false;
  bool _invalidating = false;
  String? _error;
  int _generation = 0;
  String? _lastDraftId;
  int? _lastOwnerId;
  late final AppLifecycleListener _lifecycle;
  List<TextEditingController> get _fields => [
    if (widget.recipient != null) widget.recipient!,
    if (widget.title != null) widget.title!,
    widget.body,
  ];

  @override
  void initState() {
    super.initState();
    for (final field in _fields) {
      field.addListener(_onEdit);
    }
    _lifecycle = AppLifecycleListener(
      onInactive: () {
        if (_draft?.dirty == true) unawaited(_draft!.flush());
      },
    );
    ref.listenManual(sessionProvider.select((state) => state.user?.id), (
      previous,
      next,
    ) {
      if (previous != next) _suspend(notifyParent: true);
    });
    ref.listenManual(websiteSessionProvider, (previous, next) {
      if (previous?.ready == true &&
          next.ready &&
          previous?.snapshot?.authenticationKey !=
              next.snapshot?.authenticationKey) {
        _suspend(notifyParent: true);
      }
    });
    unawaited(_open());
  }

  @override
  void didUpdateWidget(covariant PmDraftEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.threadId != widget.threadId ||
        oldWidget.conversationId != widget.conversationId ||
        oldWidget.contextReady != widget.contextReady ||
        oldWidget.draftId != widget.draftId) {
      unawaited(_open());
    }
  }

  void _onEdit() {
    if (_applying || _closing || !_ownerVerified) return;
    _draft?.edit(
      recipient: widget.recipient?.text ?? widget.replyRecipient,
      title: widget.title?.text ?? widget.replyTitle,
      body: widget.body.text,
    );
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  void _detach() {
    final old = _draft;
    _draft = null;
    old?.removeListener(_tick);
    old?.dispose();
  }

  void _suspend({bool notifyParent = false}) {
    if (!mounted || _invalidating) return;
    _invalidating = true;
    _generation++;
    _ownerVerified = false;
    _detach();
    _applying = true;
    for (final field in _fields) {
      field.clear();
    }
    _applying = false;
    setState(() {
      _opening = false;
      _error = '登录已变化，请重新核对；已保存草稿仍属于原账号';
    });
    if (notifyParent) widget.onSessionInvalidated();
    _invalidating = false;
  }

  Future<void> _open({bool fresh = false}) async {
    final generation = ++_generation;
    _detach();
    _applying = true;
    widget.body.clear();
    widget.title?.clear();
    if (widget.recipient != null) {
      widget.recipient!.text = fresh ? '' : widget.initialRecipient ?? '';
    }
    _applying = false;
    setState(() {
      _opening = true;
      _error = null;
      _ownerVerified = false;
    });
    final user = ref.read(sessionProvider).user;
    bool current() =>
        mounted &&
        generation == _generation &&
        ref.read(sessionProvider).user?.id == user?.id;
    try {
      if (user == null) throw StateError('请先登录应用账号，再恢复私信草稿');
      final identity = await widget.service.verifyDraftOwner(user);
      if (!current()) return;
      final bound = await ref
          .read(websiteSessionProvider.notifier)
          .bindVerifiedUser(
            authenticationKey: identity.authenticationKey,
            userId: identity.userId,
          );
      if (!current()) return;
      if (!bound) throw StateError('网站登录已变化或账号信息无法保存，请重试核对');
      _ownerVerified = true;
      widget.onOwnerVerified?.call();
      if (!widget.contextReady) return;
      final preferredId =
          widget.draftId ?? (_lastOwnerId == user.id ? _lastDraftId : null);
      final id = widget.kind == PmDraftKind.reply
          ? PmDraft.replyId(widget.conversationId, widget.threadId)
          : (!fresh && preferredId != null ? preferredId : PmDraft.newId());
      final draft = PmDraftController(
        ref.read(pmDraftRepositoryProvider),
        PmDraft(
          id: id,
          ownerId: user.id,
          kind: widget.kind,
          recipient: fresh
              ? ''
              : widget.initialRecipient ?? widget.replyRecipient,
          title: widget.replyTitle,
          conversationId: widget.conversationId,
          threadId: widget.threadId,
        ),
      );
      _draft = draft;
      draft.addListener(_tick);
      await draft.restore(
        findLatestCompose:
            widget.kind == PmDraftKind.compose && preferredId == null,
        recipient: widget.initialRecipient,
        fresh: fresh,
      );
      if (!current() || !identical(_draft, draft)) return;
      if (draft.ready) {
        _lastDraftId = draft.data.id;
        _lastOwnerId = user.id;
        _applying = true;
        widget.recipient?.text = draft.data.recipient;
        widget.title?.text = draft.data.title;
        widget.body.text = draft.data.body;
        _applying = false;
        widget.onRestored?.call();
      }
    } catch (error) {
      if (current()) {
        _error = error
            .toString()
            .replaceFirst('Bad state: ', '')
            .replaceFirst('Exception: ', '');
      }
    } finally {
      if (current()) setState(() => _opening = false);
    }
  }

  Future<void> _newCompose() async {
    if (_closing || _opening || widget.kind != PmDraftKind.compose) return;
    setState(() => _closing = true);
    final saved = _draft == null || await _draft!.flush();
    if (!mounted) return;
    setState(() => _closing = false);
    if (saved) await _open(fresh: true);
  }

  Future<void> _close() async {
    if (_closing) return;
    setState(() => _closing = true);
    final draft = _draft;
    final saved =
        draft == null ||
        (draft.sent ? await draft.markSent() : await draft.flush());
    if (!mounted) return;
    var leave = saved;
    if (!saved) {
      leave =
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(draft.sent ? '短信已发送' : '草稿尚未保存'),
              content: Text(
                draft.sent
                    ? '本地草稿清理失败，离开后请勿重复发送这条短信。'
                    : '可以留在页面重试，或不保存本次改动直接返回。',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('留在页面'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('直接返回'),
                ),
              ],
            ),
          ) ??
          false;
    }
    if (!mounted) return;
    if (!leave) {
      setState(() => _closing = false);
      return;
    }
    if (!saved) draft.abandonPendingEdits();
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Navigator.of(context).pop(draft?.sent == true || widget.sentElsewhere);
      }
    });
  }

  Future<void> _websiteLogin() async {
    final saved = await openWebsiteLoginScreen(context);
    if (mounted && saved == true) await _open();
  }

  Widget _status() {
    final draft = _draft;
    final message = _error ?? draft?.error;
    if (_opening) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text('正在恢复私信草稿…'),
      );
    }
    if (message != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: _closing
                      ? null
                      : () async {
                          if (_error != null || draft?.ready != true) {
                            await _open();
                          } else if (draft!.sent) {
                            final cleared = await draft.markSent();
                            if (!mounted ||
                                !identical(draft, _draft) ||
                                !cleared) {
                              return;
                            }
                            if (widget.kind == PmDraftKind.compose) {
                              setState(() => _allowPop = true);
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted) Navigator.of(context).pop(true);
                              });
                            } else {
                              await _open();
                              if (mounted) widget.onSentCleanup?.call();
                            }
                          } else {
                            await draft.flush();
                          }
                        },
                  child: Text(draft?.sent == true ? '重试清除' : '重试'),
                ),
                if (!_ownerVerified)
                  TextButton(
                    onPressed: _websiteLogin,
                    child: const Text('网站登录'),
                  ),
              ],
            ),
          ],
        ),
      );
    }
    if (draft == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        draft.sent
            ? '短信已发送'
            : draft.saving
            ? '正在保存草稿…'
            : draft.dirty
            ? '草稿尚未保存'
            : draft.saved
            ? '草稿已保存在本机'
            : '草稿会自动保存在本机',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _allowPop,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(widget.onClose?.call() ?? _close());
    },
    child: widget.builder(
      context,
      PmDraftEditing(
        controller: _draft,
        ownerVerified: _ownerVerified,
        status: _status(),
        suspend: () => _suspend(),
        allowPop: () {
          if (mounted) setState(() => _allowPop = true);
        },
        newCompose: _newCompose,
        restart: _open,
        editingAllowed: !_opening && !_closing && _error == null,
      ),
    ),
  );

  @override
  void dispose() {
    _generation++;
    _lifecycle.dispose();
    for (final field in _fields) {
      field.removeListener(_onEdit);
    }
    _detach();
    super.dispose();
  }
}
