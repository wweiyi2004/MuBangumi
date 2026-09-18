import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/storage/community_draft_store.dart';
export '../core/storage/community_draft_store.dart' show communityDraftKey;

import 'turnstile_dialog.dart';
import 'community_rich_content.dart';

typedef CommunitySubmit =
    Future<void> Function(String title, String content, String token);
typedef CommunityTokenProvider = Future<String?> Function(BuildContext context);

/// Optional in-memory draft for callers without a persistent account key.
class CommunityDraft {
  String title = '';
  String content = '';
  void clear() {
    title = '';
    content = '';
  }
}

/// Blog-only fields share the same versioned draft write as its BBCode body.
class CommunityBlogDraft {
  CommunityBlogDraft({this.tags = const [], this.isPublic = true});
  List<String> tags;
  bool isPublic;
  String encode(String content) => jsonEncode({
    'version': 1,
    'body': content,
    'tags': tags,
    'public': isPublic,
  });
  String restore(String encoded) {
    final json = jsonDecode(encoded);
    if (json is! Map ||
        json['version'] != 1 ||
        json['body'] is! String ||
        json['tags'] is! List ||
        !(json['tags'] as List).every((tag) => tag is String) ||
        json['public'] is! bool) {
      throw const FormatException('日志草稿格式无效');
    }
    tags = List<String>.from(json['tags'] as List);
    isPublic = json['public'] as bool;
    return json['body'] as String;
  }
}

Future<bool> showCommunityComposer(
  BuildContext context, {
  required String heading,
  required CommunitySubmit onSubmit,
  bool requireTitle = false,
  String contentLabel = '内容',
  String? warning,
  String? replyContext,
  int? maxLength,
  CommunityDraft? draft,
  String? draftKey,
  CommunityDraftRepository? draftStore,
  bool Function()? isAccountCurrent,
  CommunityTokenProvider? tokenProvider,
  String initialTitle = '',
  String initialContent = '',
  bool requireVerification = true,
  String submitLabel = '发送',
  CommunityBlogDraft? blogDraft,
}) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _CommunityComposerDialog(
        heading: heading,
        onSubmit: onSubmit,
        requireTitle: requireTitle,
        contentLabel: contentLabel,
        warning: warning,
        replyContext: replyContext,
        maxLength: maxLength,
        tokenProvider: tokenProvider ?? showTurnstileDialog,
        initialTitle: initialTitle,
        initialContent: initialContent,
        requireVerification: requireVerification,
        submitLabel: submitLabel,
        blogDraft: blogDraft,
        draft: draft,
        draftKey: draftKey,
        draftStore: draftStore ?? CommunityDraftStore.shared,
        isAccountCurrent: isAccountCurrent,
      ),
    ) ??
    false;

class _CommunityComposerDialog extends StatefulWidget {
  const _CommunityComposerDialog({
    required this.heading,
    required this.onSubmit,
    required this.requireTitle,
    required this.contentLabel,
    required this.tokenProvider,
    this.warning,
    this.replyContext,
    this.maxLength,
    this.draft,
    this.draftKey,
    required this.draftStore,
    this.isAccountCurrent,
    required this.initialTitle,
    required this.initialContent,
    required this.requireVerification,
    required this.submitLabel,
    this.blogDraft,
  });

  final String heading;
  final CommunitySubmit onSubmit;
  final String initialTitle;
  final String initialContent;
  final bool requireVerification;
  final String submitLabel;
  final CommunityBlogDraft? blogDraft;
  final bool requireTitle;
  final String contentLabel;
  final CommunityTokenProvider tokenProvider;
  final String? warning;
  final String? replyContext;
  final int? maxLength;
  final CommunityDraft? draft;
  final String? draftKey;
  final CommunityDraftRepository draftStore;
  final bool Function()? isAccountCurrent;

  @override
  State<_CommunityComposerDialog> createState() =>
      _CommunityComposerDialogState();
}

class _CommunityComposerDialogState extends State<_CommunityComposerDialog> {
  late final _titleController = TextEditingController(
    text: widget.draft?.title ?? widget.initialTitle,
  );
  late final _contentController = TextEditingController(
    text: widget.draft?.content ?? widget.initialContent,
  );
  late final _tagsController = TextEditingController(
    text: widget.blogDraft?.tags.join(' '),
  );
  String _lastBlogMetadata = '';
  bool _sent = false;
  bool _preview = false;
  bool _submitting = false;
  String? _error;
  String? _draftError;
  bool _restoring = false;
  bool _closing = false;
  bool _savingDraft = false;
  bool _draftSaved = false;
  bool _allowPop = false;
  bool _dirty = false;
  int _draftRevision = 0;
  int _storedRevision = 0;
  bool _loadedDraft = false;
  Future<void> _draftWrites = Future.value();
  String _lastTitle = '';
  String _lastContent = '';
  Timer? _saveTimer;
  late final AppLifecycleListener _lifecycle;

  bool get _locked => _submitting || _restoring || _closing;
  bool get _editable => !_locked && (widget.draftKey == null || _loadedDraft);

  @override
  void initState() {
    super.initState();
    _restoring = widget.draftKey != null;
    _lastTitle = _titleController.text;
    _lastContent = _contentController.text;
    _lastBlogMetadata = widget.blogDraft?.encode('') ?? '';
    _titleController.addListener(_onEdit);
    _contentController.addListener(_onEdit);
    _lifecycle = AppLifecycleListener(
      onInactive: () {
        if (_dirty && !_restoring && !_sent) unawaited(_saveDraft());
      },
    );
    if (_restoring) unawaited(_restoreDraft());
  }

  Future<void> _restoreDraft() async {
    try {
      final slot = await widget.draftStore.loadVersioned(widget.draftKey!);
      final draft = slot.data;
      if (!mounted) return;
      _storedRevision = slot.revision;
      if (draft != null) {
        final body = widget.blogDraft?.restore(draft.content) ?? draft.content;
        _titleController.text = draft.title;
        _contentController.text = body;
        _tagsController.text = widget.blogDraft?.tags.join(' ') ?? '';
        _draftSaved = true;
      }
      _loadedDraft = true;
      _draftError = null;
      _lastTitle = _titleController.text;
      _lastContent = _contentController.text;
      _lastBlogMetadata = widget.blogDraft?.encode('') ?? '';
    } catch (_) {
      if (mounted) _draftError = '草稿读取失败，可重试读取';
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  void _onEdit() {
    if (_restoring || _sent) return;
    if (_lastTitle == _titleController.text &&
        _lastContent == _contentController.text &&
        _lastBlogMetadata == (widget.blogDraft?.encode('') ?? '')) {
      return;
    }
    _lastTitle = _titleController.text;
    _lastContent = _contentController.text;
    _lastBlogMetadata = widget.blogDraft?.encode('') ?? '';
    _dirty = true;
    _draftRevision++;
    _draftSaved = false;
    _saveTimer?.cancel();
    if (widget.draftKey != null) {
      _saveTimer = Timer(const Duration(milliseconds: 350), () {
        unawaited(_saveDraft());
      });
    }
  }

  Future<void> _persistDraft(String key, CommunityDraftData draft) {
    final next = _draftWrites.then((_) async {
      _storedRevision = await widget.draftStore.saveVersioned(
        key,
        draft,
        expectedRevision: _storedRevision,
      );
    });
    _draftWrites = next.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return next;
  }

  Future<bool> _saveDraft() async {
    _saveTimer?.cancel();
    final key = widget.draftKey;
    if (key == null || _sent || !_dirty) return true;
    if (!_loadedDraft) {
      if (mounted) setState(() => _draftError = '请先重试读取草稿');
      return false;
    }
    final revision = _draftRevision;
    final draft = (
      title: _titleController.text,
      content:
          widget.blogDraft?.encode(_contentController.text) ??
          _contentController.text,
    );
    if (mounted) setState(() => _savingDraft = true);
    try {
      await _persistDraft(key, draft);
      if (mounted && revision == _draftRevision) {
        setState(() {
          _dirty = false;
          _draftSaved = true;
          _draftError = null;
        });
      }
      return true;
    } catch (error) {
      if (mounted) {
        setState(
          () => _draftError = error is CommunityDraftConflict
              ? '草稿已在其他操作中更新，请先复制当前输入，再关闭并重新打开'
              : '草稿保存失败，请重试',
        );
      }
      return false;
    } finally {
      if (mounted && revision == _draftRevision) {
        setState(() => _savingDraft = false);
      }
    }
  }

  Future<void> _close() async {
    if (_locked) return;
    setState(() => _closing = true);
    final saved = await _saveDraft();
    if (!mounted) return;
    setState(() => _closing = false);
    if (saved) {
      setState(() => _allowPop = true);
      // Rebuild PopScope before completing a system-back request.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop(false);
      });
    }
  }

  bool get _canSubmit {
    if (widget.draftKey != null && !_loadedDraft) return false;
    if (_contentController.text.trim().isEmpty) return false;
    if (widget.requireTitle && _titleController.text.trim().isEmpty) {
      return false;
    }
    final maxLength = widget.maxLength;
    return maxLength == null || _contentController.text.length <= maxLength;
  }

  Future<void> _submit() async {
    if (!_canSubmit || _locked) return;
    // Lock the button before the await so rapid taps cannot open several
    // Turnstile dialogs and trigger duplicate submissions.
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      _checkAccount();
      final token = widget.requireVerification
          ? await widget.tokenProvider(context)
          : '';
      if (!mounted) return;
      _checkAccount();
      if (widget.requireVerification &&
          (token == null || token.trim().isEmpty)) {
        setState(() {
          _submitting = false;
          _error = '未完成人机验证，请重新点击发送';
        });
        return;
      }
      await widget.onSubmit(
        _titleController.text.trim(),
        _contentController.text.trim(),
        token?.trim() ?? '',
      );
      _sent = true;
      _saveTimer?.cancel();
      widget.draft?.clear();
      try {
        if (widget.draftKey case final key?) {
          await _persistDraft(key, (title: '', content: ''));
        }
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('发送成功，但本地草稿未能清除，请勿重复发送')),
          );
        }
      }
      if (mounted) {
        setState(() => _allowPop = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).pop(true);
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = error
            .toString()
            .replaceFirst('Exception: ', '')
            .replaceFirst('FormatException: ', '');
      });
    }
  }

  void _checkAccount() {
    if (widget.isAccountCurrent?.call() == false) {
      throw const FormatException('登录账号已变化，请返回原账号后继续编辑和发送');
    }
  }

  @override
  void dispose() {
    _tagsController.dispose();
    _saveTimer?.cancel();
    _lifecycle.dispose();
    if (!_sent && _dirty && _loadedDraft && widget.draftKey != null) {
      unawaited(
        _persistDraft(widget.draftKey!, (
          title: _titleController.text,
          content:
              widget.blogDraft?.encode(_contentController.text) ??
              _contentController.text,
        )).catchError((Object _) {}),
      );
    }
    if (!_sent) {
      widget.draft?.title = _titleController.text;
      widget.draft?.content = _contentController.text;
    }
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _allowPop || (widget.draftKey == null && !_submitting),
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(_close());
    },
    child: AlertDialog(
      title: Text(widget.heading),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_restoring) const LinearProgressIndicator(),
              if (widget.replyContext case final excerpt?) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    excerpt,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (widget.requireTitle) ...[
                TextField(
                  controller: _titleController,
                  enabled: _editable,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: '标题',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
              ],
              if (widget.warning case final warning?) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.history_rounded, size: 19),
                      const SizedBox(width: 8),
                      Expanded(child: Text(warning)),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
              if (widget.blogDraft case final blog?) ...[
                TextField(
                  controller: _tagsController,
                  enabled: _editable,
                  decoration: const InputDecoration(
                    labelText: '标签',
                    helperText: '空格分隔，最多 10 个',
                  ),
                  onChanged: (value) {
                    blog.tags = value
                        .split(RegExp(r'\s+'))
                        .where((tag) => tag.isNotEmpty)
                        .toList();
                    _onEdit();
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('公开日志'),
                  subtitle: Text(blog.isPublic ? '所有人可见' : '仅好友可见'),
                  value: blog.isPublic,
                  onChanged: !_editable
                      ? null
                      : (value) {
                          setState(() => blog.isPublic = value);
                          _onEdit();
                        },
                ),
              ],
              BbCodeToolbar(
                controller: _contentController,
                enabled: _editable,
                onChanged: () => setState(() {}),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => setState(() => _preview = !_preview),
                  icon: Icon(
                    _preview ? Icons.edit_outlined : Icons.preview_outlined,
                  ),
                  label: Text(_preview ? '继续编辑' : '预览正文'),
                ),
              ),
              const SizedBox(height: 8),
              if (_preview)
                CommunityRichContent(_contentController.text)
              else
                TextField(
                  controller: _contentController,
                  enabled: _editable,
                  autofocus: !widget.requireTitle,
                  minLines: 5,
                  maxLines: 12,
                  maxLength: widget.maxLength,
                  decoration: InputDecoration(
                    labelText: widget.contentLabel,
                    alignLabelWithHint: true,
                    border: const OutlineInputBorder(),
                    helperText: '支持 Bangumi BBCode',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              if (widget.draftKey != null) ...[
                const SizedBox(height: 8),
                if (_draftError != null)
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        _draftError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      TextButton(
                        onPressed: _locked
                            ? null
                            : () async {
                                if (_dirty) {
                                  await _saveDraft();
                                } else {
                                  setState(() => _restoring = true);
                                  await _restoreDraft();
                                }
                              },
                        child: const Text('重试'),
                      ),
                    ],
                  )
                else
                  Text(
                    _restoring
                        ? '正在读取草稿…'
                        : _savingDraft || _dirty
                        ? '正在保存草稿…'
                        : _draftSaved
                        ? '草稿已保存在本机'
                        : '草稿会自动保存在本机',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _locked ? null : _close,
          child: Text(
            (widget.draft != null || widget.draftKey != null) &&
                    (_titleController.text.isNotEmpty ||
                        _contentController.text.isNotEmpty)
                ? '稍后再写'
                : '取消',
          ),
        ),
        if (_draftError != null && !_locked)
          TextButton(
            onPressed: () {
              _dirty = false;
              _saveTimer?.cancel();
              setState(() => _allowPop = true);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) Navigator.of(context).pop(false);
              });
            },
            child: const Text('不保存并关闭'),
          ),
        FilledButton.icon(
          onPressed: _canSubmit && !_locked ? _submit : null,
          icon: _submitting
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.send_rounded),
          label: Text(
            _submitting ? '${widget.submitLabel}中' : widget.submitLabel,
          ),
        ),
      ],
    ),
  );
}

void applyBbCode(
  TextEditingController controller, {
  required String tag,
  String? closingTag,
}) {
  final text = controller.text;
  final selection = controller.selection;
  final rawStart = selection.isValid ? selection.start : text.length;
  final rawEnd = selection.isValid ? selection.end : text.length;
  final start = rawStart.clamp(0, text.length).toInt();
  final end = rawEnd.clamp(start, text.length).toInt();
  final open = '[$tag]';
  final close = closingTag ?? '[/$tag]';
  final selected = text.substring(start, end);
  final replacement = '$open$selected$close';
  final cursorStart = start + open.length;
  controller.value = TextEditingValue(
    text: text.replaceRange(start, end, replacement),
    selection: selected.isEmpty
        ? TextSelection.collapsed(offset: cursorStart)
        : TextSelection(
            baseOffset: cursorStart,
            extentOffset: cursorStart + selected.length,
          ),
  );
}

class BbCodeToolbar extends StatelessWidget {
  const BbCodeToolbar({
    super.key,
    required this.controller,
    this.enabled = true,
    this.onChanged,
  });

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback? onChanged;

  void _apply(String tag) {
    applyBbCode(controller, tag: tag);
    onChanged?.call();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    ignoring: !enabled,
    child: Opacity(
      opacity: enabled ? 1 : .5,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _BbButton(label: 'B', tooltip: '粗体', onTap: () => _apply('b')),
            _BbButton(label: 'I', tooltip: '斜体', onTap: () => _apply('i')),
            _BbButton(label: 'U', tooltip: '下划线', onTap: () => _apply('u')),
            _BbButton(label: 'S', tooltip: '删除线', onTap: () => _apply('s')),
            _BbButton(label: '链接', tooltip: '链接', onTap: () => _apply('url')),
            _BbButton(label: '图片', tooltip: '图片', onTap: () => _apply('img')),
            _BbButton(label: '引用', tooltip: '引用', onTap: () => _apply('quote')),
            PopupMenuButton<String>(
              tooltip: '文字颜色',
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('颜色'),
              ),
              onSelected: (color) {
                applyBbCode(
                  controller,
                  tag: 'color=$color',
                  closingTag: 'color',
                );
                onChanged?.call();
              },
              itemBuilder: (_) => [
                for (final entry in const {
                  'red': '红色',
                  'green': '绿色',
                  'blue': '蓝色',
                  'orange': '橙色',
                  'purple': '紫色',
                }.entries)
                  PopupMenuItem(value: entry.key, child: Text(entry.value)),
              ],
            ),
            PopupMenuButton<String>(
              tooltip: '文字对齐',
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('对齐'),
              ),
              onSelected: (value) {
                applyBbCode(
                  controller,
                  tag: 'align=$value',
                  closingTag: 'align',
                );
                onChanged?.call();
              },
              itemBuilder: (_) => [
                for (final entry in const {
                  'left': '左对齐',
                  'center': '居中',
                  'right': '右对齐',
                }.entries)
                  PopupMenuItem(value: entry.key, child: Text(entry.value)),
              ],
            ),
            _BbButton(
              label: '剧透',
              tooltip: '剧透遮罩',
              onTap: () => _apply('mask'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _BbButton extends StatelessWidget {
  const _BbButton({
    required this.label,
    required this.tooltip,
    required this.onTap,
  });

  final String label;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 6),
    child: Tooltip(
      message: tooltip,
      child: ActionChip(
        visualDensity: VisualDensity.compact,
        label: Text(label),
        onPressed: onTap,
      ),
    ),
  );
}
