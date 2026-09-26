import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/bangumi_models.dart';
import '../models/library_batch.dart';
import '../state/session_controller.dart';
import '../state/short_review_draft.dart';
import 'subject_widgets.dart';
import '../core/theme/app_tokens.dart';

/// Full collection editor: status, score, comment, tags, privacy.
Future<bool> showCollectionEditorSheet(
  BuildContext context, {
  required Subject subject,
  UserCollection? collection,
  bool focusComment = false,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => _CollectionEditorSheet(
      subject: subject,
      collection: collection,
      focusComment: focusComment,
    ),
  );
  return result == true;
}

class _CollectionEditorSheet extends ConsumerStatefulWidget {
  const _CollectionEditorSheet({
    required this.subject,
    required this.collection,
    this.focusComment = false,
  });

  final Subject subject;
  final UserCollection? collection;
  final bool focusComment;

  @override
  ConsumerState<_CollectionEditorSheet> createState() =>
      _CollectionEditorSheetState();
}

class _CollectionEditorSheetState
    extends ConsumerState<_CollectionEditorSheet> {
  late CollectionType _type;
  late int _rate;
  late int _volumeStatus;
  late int _episodeStatus;
  late final TextEditingController _comment;
  final _commentFocus = FocusNode();
  final _tagsFocus = FocusNode();
  late final TextEditingController _tags;
  late bool _private;
  var _saving = false;
  late final LibraryBatchAccount? _account;
  late final int _revision;
  ShortReviewDraft? _draft;
  late final AppLifecycleListener _lifecycle;
  bool _allowPop = false, _closing = false;

  bool get _isBook => widget.subject.type.hasVolumes;

  @override
  void initState() {
    super.initState();
    final session = ref.read(sessionProvider.notifier);
    _account = session.batchAccount;
    _revision = session.collectionMutationRevision(widget.subject.id);
    final c = widget.collection;
    _type = c?.type ?? CollectionType.wish;
    _rate = c?.rate ?? 0;
    _volumeStatus = c?.volumeStatus ?? 0;
    _episodeStatus = c?.episodeStatus ?? 0;
    _comment = TextEditingController(text: c?.comment ?? '');
    _tags = TextEditingController(text: (c?.tags ?? const []).join(' '));
    _private = c?.private ?? false;
    final account = _account;
    if (account != null) {
      _draft = ShortReviewDraft(
        ref.read(shortReviewDraftRepositoryProvider),
        ownerId: account.userId,
        subjectId: widget.subject.id,
        original: _comment.text,
      )..addListener(_draftChanged);
      unawaited(_restoreDraft());
    }
    _comment.addListener(_commentChanged);
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        if (state != AppLifecycleState.resumed) unawaited(_draft?.flush());
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _draft?.removeListener(_draftChanged);
    _draft?.dispose();
    _comment.removeListener(_commentChanged);
    _comment.dispose();
    _tags.dispose();
    _commentFocus.dispose();
    _tagsFocus.dispose();
    super.dispose();
  }

  void _draftChanged() {
    if (mounted) setState(() {});
  }

  void _commentChanged() {
    _draft?.edit(_comment.text);
  }

  Future<void> _restoreDraft() async {
    await _draft?.restore();
    if (!mounted || _draft?.ready != true) return;
    _comment.removeListener(_commentChanged);
    _comment.text = _draft!.text;
    _comment.addListener(_commentChanged);
    // Initially disabled while loading; autofocus must run after re-enabling.
    if (widget.focusComment) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            !_tagsFocus.hasFocus &&
            _draft?.conflictingText == null &&
            ModalRoute.of(context)?.isCurrent == true &&
            ref.read(sessionProvider).user?.id == _account?.userId) {
          _commentFocus.requestFocus();
        }
      });
    }
  }

  Future<void> _close([bool result = false]) async {
    if (_closing || _saving) return;
    _closing = true;
    final draft = _draft;
    final ok =
        draft == null ||
        !draft.ready ||
        (draft.submitted ? await draft.markSubmitted() : await draft.flush());
    _closing = false;
    if (!mounted || !ok) return;
    setState(() => _allowPop = true);
    Navigator.pop(context, result);
  }

  Widget _draftStatus() {
    final draft = _draft;
    if (draft == null) return const SizedBox.shrink();
    if (draft.conflictingText != null) {
      return Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('已保存的短评有变化，另有未发送草稿'),
          TextButton(
            onPressed: () {
              draft.recoverConflict();
              _comment.text = draft.text;
            },
            child: const Text('恢复草稿'),
          ),
          TextButton(
            onPressed: () {
              draft.conflictingText = null;
              draft.edit(_comment.text);
            },
            child: const Text('保留当前短评'),
          ),
        ],
      );
    }
    if (draft.error != null) {
      return Row(
        children: [
          Expanded(child: Text(draft.error!)),
          TextButton(
            onPressed: () async {
              if (!draft.ready) {
                await _restoreDraft();
              } else if (draft.submitted) {
                await _close(true);
              } else {
                await draft.flush();
              }
            },
            child: const Text('重试'),
          ),
        ],
      );
    }
    return Text(
      !draft.ready
          ? '正在读取草稿…'
          : draft.saving || draft.dirty
          ? '正在保存短评草稿…'
          : draft.saved
          ? '已恢复或保存短评草稿 · 仅本机可见'
          : '短评自动保存为本机草稿',
      style: Theme.of(context).textTheme.bodySmall,
    );
  }

  List<String> get _parsedTags => _tags.text
      .split(RegExp(r'[\s,，;；]+'))
      .map((t) => t.trim())
      .where((t) => t.isNotEmpty)
      .toList();

  Future<void> _save() async {
    final account = _account;
    if (account == null ||
        !ref.read(sessionProvider.notifier).isCurrentBatchAccount(account)) {
      showAppMessage(context, '登录状态已变化，请关闭面板后重新编辑');
      return;
    }
    if (_draft?.conflictingText != null) {
      showAppMessage(context, '请先选择恢复草稿或保留当前短评');
      return;
    }
    if (_draft?.submitted == true) {
      await _close(true);
      return;
    }
    if (_saving || _closing) return;
    setState(() => _saving = true);
    if (_draft != null && !await _draft!.flush()) {
      if (mounted) setState(() => _saving = false);
      return;
    }
    if (!mounted) return;
    final error = await ref
        .read(sessionProvider.notifier)
        .changeCollection(
          widget.subject,
          _type,
          expectedAccount: account,
          expectedRevision: _revision,
          rate: _rate,
          comment: _comment.text.trim(),
          tags: _parsedTags,
          private: _private,
          completeEpisodesWhenDone: true,
          episodeStatus: _isBook ? _episodeStatus : null,
          volumeStatus: _isBook ? _volumeStatus : null,
        );
    if (!mounted) return;
    setState(() => _saving = false);
    if (error != null) {
      showAppMessage(context, error);
      return;
    }
    final pending = ref.read(sessionProvider).pendingSyncCount;
    showAppMessage(context, pending > 0 ? '收藏已保存在本机，联网后自动同步' : '收藏已保存');
    final draft = _draft;
    if (draft != null && !await draft.markSubmitted()) return;
    if (!mounted) return;
    setState(() => _allowPop = true);
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final subject = widget.subject;
    final ownerId = ref.watch(sessionProvider.select((s) => s.user?.id));
    if (_account != null && ownerId != _account.userId) {
      return PopScope<bool>(
        canPop: _allowPop,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) unawaited(_close());
        },
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('登录状态已变化，原账号短评草稿会保留'),
              TextButton(
                onPressed: () => _close(),
                child: const Text('保存草稿并关闭'),
              ),
              if (_draft?.error != null) Text(_draft!.error!),
            ],
          ),
        ),
      );
    }
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return PopScope<bool>(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_close());
      },
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 4, 20, bottom + 20),
        child: SingleChildScrollView(
          child: AbsorbPointer(
            absorbing: _saving,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '管理收藏',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      onPressed: _saving ? null : () => _close(),
                      tooltip: '保存草稿并关闭',
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  subject.displayName,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                Text('状态', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final type in CollectionType.values)
                      ChoiceChip(
                        label: Text(type.labelFor(subject.type)),
                        selected: _type == type,
                        onSelected: (_) => setState(() => _type = type),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Text('评分', style: Theme.of(context).textTheme.labelLarge),
                    const Spacer(),
                    Text(
                      _rate == 0 ? '未评分' : '$_rate 分',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.tertiary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: _rate.toDouble(),
                  min: 0,
                  max: 10,
                  divisions: 10,
                  label: _rate == 0 ? '未评分' : '$_rate',
                  onChanged: (value) => setState(() => _rate = value.round()),
                ),
                Wrap(
                  spacing: 6,
                  children: [
                    for (var i = 0; i <= 10; i++)
                      FilterChip(
                        label: Text(i == 0 ? '无' : '$i'),
                        selected: _rate == i,
                        onSelected: (_) => setState(() => _rate = i),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
                if (_isBook) ...[
                  const SizedBox(height: 14),
                  Text('阅读进度', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _ProgressStepper(
                          label: '卷',
                          value: _volumeStatus,
                          total: subject.volumeCount,
                          onChanged: (value) =>
                              setState(() => _volumeStatus = value),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _ProgressStepper(
                          label: '话',
                          value: _episodeStatus,
                          total: subject.episodeCount,
                          onChanged: (value) =>
                              setState(() => _episodeStatus = value),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 14),
                TextField(
                  controller: _comment,
                  focusNode: _commentFocus,
                  enabled:
                      !_saving &&
                      (_draft == null || _draft!.ready) &&
                      _draft?.submitted != true &&
                      _draft?.conflictingText == null,
                  autofocus: widget.focusComment,
                  maxLines: 3,
                  maxLength: 200,
                  decoration: const InputDecoration(
                    labelText: '吐槽 / 短评',
                    alignLabelWithHint: true,
                    hintText: '可选，写给自己的一句话',
                  ),
                ),
                _draftStatus(),
                const SizedBox(height: 8),
                TextField(
                  controller: _tags,
                  focusNode: _tagsFocus,
                  decoration: const InputDecoration(
                    labelText: '标签',
                    hintText: '空格或逗号分隔，例如：日常 治愈',
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('仅自己可见'),
                  subtitle: const Text('开启后收藏对他人隐藏'),
                  value: _private,
                  onChanged: (value) => setState(() => _private = value),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _saving || (_draft != null && !_draft!.ready)
                      ? null
                      : _save,
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_rounded),
                  label: Text(
                    _saving
                        ? '保存中…'
                        : _draft?.submitted == true
                        ? '清理草稿并关闭'
                        : '保存',
                  ),
                ),
                if (widget.collection != null) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () => launchUrl(
                      Uri.parse('https://bgm.tv/subject/${subject.id}'),
                      mode: LaunchMode.externalApplication,
                    ),
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: const Text('在官网移出收藏'),
                  ),
                  Text(
                    '如需删除收藏，请前往 Bangumi 官网。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProgressStepper extends StatelessWidget {
  const _ProgressStepper({
    required this.label,
    required this.value,
    required this.total,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int total;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: AppRadius.medium,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            total > 0 ? '$label · 共 $total' : label,
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              IconButton.filledTonal(
                onPressed: value > 0 ? () => onChanged(value - 1) : null,
                icon: const Icon(Icons.remove_rounded),
                visualDensity: VisualDensity.compact,
              ),
              Expanded(
                child: Text(
                  '$value',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton.filledTonal(
                onPressed: () => onChanged(value + 1),
                icon: const Icon(Icons.add_rounded),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
