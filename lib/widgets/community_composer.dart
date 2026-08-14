import 'package:flutter/material.dart';

import 'turnstile_dialog.dart';

typedef CommunitySubmit =
    Future<void> Function(String title, String content, String token);
typedef CommunityTokenProvider = Future<String?> Function(BuildContext context);

Future<bool> showCommunityComposer(
  BuildContext context, {
  required String heading,
  required CommunitySubmit onSubmit,
  bool requireTitle = false,
  String contentLabel = '内容',
  String? warning,
  int? maxLength,
  CommunityTokenProvider tokenProvider = showTurnstileDialog,
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
        maxLength: maxLength,
        tokenProvider: tokenProvider,
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
    this.maxLength,
  });

  final String heading;
  final CommunitySubmit onSubmit;
  final bool requireTitle;
  final String contentLabel;
  final CommunityTokenProvider tokenProvider;
  final String? warning;
  final int? maxLength;

  @override
  State<_CommunityComposerDialog> createState() =>
      _CommunityComposerDialogState();
}

class _CommunityComposerDialogState extends State<_CommunityComposerDialog> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  bool _submitting = false;
  String? _error;

  bool get _canSubmit {
    if (_contentController.text.trim().isEmpty) return false;
    if (widget.requireTitle && _titleController.text.trim().isEmpty) {
      return false;
    }
    final maxLength = widget.maxLength;
    return maxLength == null || _contentController.text.length <= maxLength;
  }

  Future<void> _submit() async {
    if (!_canSubmit || _submitting) return;
    // Lock the button before the await so rapid taps cannot open several
    // Turnstile dialogs and trigger duplicate submissions.
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final token = await widget.tokenProvider(context);
      if (!mounted) return;
      if (token == null || token.trim().isEmpty) {
        setState(() {
          _submitting = false;
          _error = '未完成人机验证，请重新点击发送';
        });
        return;
      }
      await widget.onSubmit(
        _titleController.text.trim(),
        _contentController.text.trim(),
        token.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
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

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_submitting,
    child: AlertDialog(
      title: Text(widget.heading),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.requireTitle) ...[
                TextField(
                  controller: _titleController,
                  enabled: !_submitting,
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
              BbCodeToolbar(
                controller: _contentController,
                enabled: !_submitting,
                onChanged: () => setState(() {}),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _contentController,
                enabled: !_submitting,
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
          onPressed: _submitting
              ? null
              : () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          onPressed: _canSubmit && !_submitting ? _submit : null,
          icon: _submitting
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.send_rounded),
          label: Text(_submitting ? '发送中' : '发送'),
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
