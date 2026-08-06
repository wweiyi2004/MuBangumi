import 'package:flutter/material.dart';

import 'turnstile_dialog.dart';

typedef CommunitySubmit =
    Future<void> Function(String title, String content, String token);

Future<bool> showCommunityComposer(
  BuildContext context, {
  required String heading,
  required CommunitySubmit onSubmit,
  bool requireTitle = false,
  String contentLabel = '内容',
  int? maxLength,
}) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _CommunityComposerDialog(
        heading: heading,
        onSubmit: onSubmit,
        requireTitle: requireTitle,
        contentLabel: contentLabel,
        maxLength: maxLength,
      ),
    ) ??
    false;

class _CommunityComposerDialog extends StatefulWidget {
  const _CommunityComposerDialog({
    required this.heading,
    required this.onSubmit,
    required this.requireTitle,
    required this.contentLabel,
    this.maxLength,
  });

  final String heading;
  final CommunitySubmit onSubmit;
  final bool requireTitle;
  final String contentLabel;
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
    final token = await showTurnstileDialog(context);
    if (!mounted) return;
    if (token == null || token.trim().isEmpty) {
      setState(() => _error = '未完成人机验证，请重试发送');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
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
