import '../../../state/service_providers.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/pm_models.dart';
import '../../../core/network/pm_service.dart';
import '../../../widgets/pm_draft_editor.dart';
import '../../../core/storage/pm_draft_store.dart';
import 'pm_session_listener.dart';
import '../../../core/layout/app_layout.dart';
import '../../../state/pm_send_queue_controller.dart';

class PmComposeScreen extends ConsumerStatefulWidget {
  const PmComposeScreen({super.key, this.toUser, this.service, this.draftId});

  final String? toUser;
  final PmService? service;
  final String? draftId;

  @override
  ConsumerState<PmComposeScreen> createState() => _PmComposeScreenState();
}

class _PmComposeScreenState extends ConsumerState<PmComposeScreen> {
  late final _service = widget.service ?? pmServiceFor(context);
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
    watchPmSession(ref, _onWebsiteSessionChanged);
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
      final queue = ref.read(pmSendQueueProvider(_service));
      if (queue.supported) {
        final command = await queue.enqueue(
          draft,
          receiver: params.msgReceivers,
        );
        if (command == null || !mounted || _sessionChanged) return;
        editing.allowPop();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已加入发送队列，正在后台发送')));
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).pop(true);
        });
        return;
      }
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
