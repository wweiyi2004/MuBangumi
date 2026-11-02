import 'package:flutter/material.dart';

import '../core/theme/anime_icon.dart';
import 'community_rich_content.dart';

/// Log-specific presentation; submission and durable drafts stay with the composer.
class BlogComposerPage extends StatefulWidget {
  const BlogComposerPage({
    super.key,
    required this.heading,
    required this.submitLabel,
    required this.titleController,
    required this.contentController,
    required this.tags,
    required this.isPublic,
    required this.editable,
    required this.submitting,
    required this.onClose,
    required this.onSubmit,
    required this.onChanged,
    required this.onTagsChanged,
    required this.onPublicChanged,
    required this.toolbar,
    required this.feedback,
    this.maxLength,
  });

  final String heading, submitLabel;
  final TextEditingController titleController, contentController;
  final List<String> tags;
  final bool isPublic, editable, submitting;
  final VoidCallback? onClose, onSubmit;
  final VoidCallback onChanged;
  final ValueChanged<List<String>> onTagsChanged;
  final ValueChanged<bool> onPublicChanged;
  final Widget toolbar, feedback;
  final int? maxLength;

  @override
  State<BlogComposerPage> createState() => _BlogComposerPageState();
}

class _BlogComposerPageState extends State<BlogComposerPage> {
  bool _formatting = false, _preview = false;

  Future<void> _editTags() async {
    final tags = await showDialog<List<String>>(
      context: context,
      builder: (_) => _BlogTagsDialog(initial: widget.tags),
    );
    if (mounted && widget.editable && tags != null) widget.onTagsChanged(tags);
  }

  Future<void> _chooseVisibility() async {
    final value = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  '谁可以看',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              for (final public in [true, false])
                ListTile(
                  leading: AnimeIcon(
                    public
                        ? Icons.public_rounded
                        : Icons.people_outline_rounded,
                  ),
                  title: Text(public ? '所有人可见' : '仅好友可见'),
                  selected: widget.isPublic == public,
                  trailing: widget.isPublic == public
                      ? const AnimeIcon(Icons.check_rounded)
                      : null,
                  onTap: () => Navigator.pop(context, public),
                ),
            ],
          ),
        ),
      ),
    );
    if (mounted && widget.editable && value != null) {
      widget.onPublicChanged(value);
    }
  }

  void _toggleFormatting() {
    setState(() {
      _preview = false;
      _formatting = !_formatting;
    });
  }

  Future<void> _insertImage() async {
    final selection = widget.contentController.selection;
    final url = await showDialog<String>(
      context: context,
      builder: (_) => const _BlogImageDialog(),
    );
    if (!mounted || !widget.editable || url == null) return;
    final text = widget.contentController.text;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    final image = '[img]$url[/img]';
    widget.contentController.value = TextEditingValue(
      text: text.replaceRange(start, end, image),
      selection: TextSelection.collapsed(offset: start + image.length),
    );
    setState(() => _preview = false);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), scheme = theme.colorScheme;
    final count = widget.contentController.text.characters.length;
    final border = OutlineInputBorder(
      borderSide: BorderSide.none,
      borderRadius: BorderRadius.circular(8),
    );
    InputDecoration input(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        color: scheme.onSurfaceVariant.withValues(alpha: .65),
      ),
      border: border,
      enabledBorder: border,
      focusedBorder: border,
      disabledBorder: border,
      filled: false,
      contentPadding: EdgeInsets.zero,
    );
    return Scaffold(
      key: const Key('blog-composer-page'),
      backgroundColor: scheme.surfaceContainer,
      appBar: AppBar(
        backgroundColor: scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        leadingWidth: 76,
        leading: TextButton(
          style: TextButton.styleFrom(foregroundColor: scheme.onSurface),
          onPressed: widget.onClose,
          child: const Text('取消'),
        ),
        title: Text(
          widget.heading,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: FilledButton(
              key: const Key('blog-publish'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(68, 40),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: widget.onSubmit,
              child: widget.submitting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(widget.submitLabel),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bodyHeight = (constraints.maxHeight * .42).clamp(
              180.0,
              400.0,
            );
            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _card(
                        context,
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (_preview) ...[
                                Text(
                                  widget.titleController.text.trim().isEmpty
                                      ? '日志预览'
                                      : widget.titleController.text,
                                  style: theme.textTheme.titleLarge,
                                ),
                                const SizedBox(height: 16),
                                ConstrainedBox(
                                  constraints: BoxConstraints(
                                    minHeight: bodyHeight,
                                  ),
                                  child:
                                      widget.contentController.text
                                          .trim()
                                          .isEmpty
                                      ? Text(
                                          '写下正文后，就可以在这里预览。',
                                          style: TextStyle(
                                            color: scheme.onSurfaceVariant,
                                          ),
                                        )
                                      : CommunityRichContent(
                                          widget.contentController.text,
                                        ),
                                ),
                              ] else ...[
                                Semantics(
                                  label: '日志标题',
                                  child: TextField(
                                    key: const Key('blog-title'),
                                    controller: widget.titleController,
                                    enabled: widget.editable,
                                    style: theme.textTheme.titleLarge,
                                    textInputAction: TextInputAction.next,
                                    maxLength: 80,
                                    decoration: input(
                                      '给这篇日志起个标题',
                                    ).copyWith(counterText: ''),
                                    onChanged: (_) => widget.onChanged(),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  child: Divider(
                                    height: 1,
                                    color: scheme.outlineVariant.withValues(
                                      alpha: .4,
                                    ),
                                  ),
                                ),
                                ConstrainedBox(
                                  constraints: BoxConstraints(
                                    minHeight: bodyHeight,
                                  ),
                                  child: Semantics(
                                    label: '日志正文',
                                    child: TextField(
                                      key: const Key('blog-body'),
                                      controller: widget.contentController,
                                      enabled: widget.editable,
                                      textAlignVertical: TextAlignVertical.top,
                                      minLines: 7,
                                      maxLines: null,
                                      maxLength: widget.maxLength,
                                      textCapitalization:
                                          TextCapitalization.sentences,
                                      style: theme.textTheme.bodyLarge,
                                      decoration: input(
                                        '分享新鲜事，或写下刚看完的感受…',
                                      ).copyWith(counterText: ''),
                                      onChanged: (_) => widget.onChanged(),
                                    ),
                                  ),
                                ),
                              ],
                              if (_formatting && !_preview) ...[
                                const SizedBox(height: 12),
                                widget.toolbar,
                              ],
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  TextButton.icon(
                                    onPressed: widget.editable
                                        ? _insertImage
                                        : null,
                                    icon: const AnimeIcon(
                                      Icons.image_outlined,
                                      size: 20,
                                    ),
                                    label: const Text('图片'),
                                  ),
                                  TextButton.icon(
                                    onPressed: widget.editable
                                        ? _toggleFormatting
                                        : null,
                                    icon: const AnimeIcon(
                                      Icons.text_fields_rounded,
                                      size: 20,
                                    ),
                                    label: const Text('排版'),
                                  ),
                                  TextButton.icon(
                                    onPressed: () =>
                                        setState(() => _preview = !_preview),
                                    icon: AnimeIcon(
                                      _preview
                                          ? Icons.edit_outlined
                                          : Icons.preview_outlined,
                                      size: 20,
                                    ),
                                    label: Text(_preview ? '继续编辑' : '预览正文'),
                                  ),
                                ],
                              ),
                              Align(
                                alignment: Alignment.centerRight,
                                child: Text(
                                  '$count 字',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _card(
                        context,
                        Column(
                          children: [
                            ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 4,
                              ),
                              leading: const AnimeIcon(Icons.sell_outlined),
                              title: const Text('添加标签'),
                              subtitle: Text(
                                widget.tags.isEmpty
                                    ? '为日志添加关键词'
                                    : widget.tags
                                          .map((tag) => '#$tag')
                                          .join('  '),
                              ),
                              trailing: const AnimeIcon(
                                Icons.chevron_right_rounded,
                              ),
                              onTap: widget.editable ? _editTags : null,
                            ),
                            Divider(
                              height: 1,
                              indent: 60,
                              endIndent: 20,
                              color: scheme.outlineVariant.withValues(
                                alpha: .4,
                              ),
                            ),
                            ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 4,
                              ),
                              leading: const AnimeIcon(
                                Icons.visibility_outlined,
                              ),
                              title: const Text('权限设置'),
                              subtitle: Text(
                                widget.isPublic ? '所有人可见' : '仅好友可见',
                              ),
                              trailing: const AnimeIcon(
                                Icons.chevron_right_rounded,
                              ),
                              onTap: widget.editable ? _chooseVisibility : null,
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
                        child: widget.feedback,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _card(BuildContext context, Widget child) => Material(
    color: Theme.of(context).colorScheme.surface,
    borderRadius: BorderRadius.circular(22),
    clipBehavior: Clip.antiAlias,
    child: child,
  );
}

class _BlogImageDialog extends StatefulWidget {
  const _BlogImageDialog();
  @override
  State<_BlogImageDialog> createState() => _BlogImageDialogState();
}

class _BlogImageDialogState extends State<_BlogImageDialog> {
  final _controller = TextEditingController();
  String? _error;
  void _insert() {
    final value = _controller.text.trim();
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !const ['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty) {
      setState(() => _error = '请输入有效的 http 或 https 图片链接');
      return;
    }
    Navigator.pop(context, value);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('插入图片'),
    content: TextField(
      controller: _controller,
      autofocus: true,
      keyboardType: TextInputType.url,
      onSubmitted: (_) => _insert(),
      decoration: InputDecoration(
        labelText: '图片链接',
        hintText: 'https://…',
        helperText: '粘贴图片的公开链接',
        errorText: _error,
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _insert, child: const Text('插入')),
    ],
  );
}

class _BlogTagsDialog extends StatefulWidget {
  const _BlogTagsDialog({required this.initial});
  final List<String> initial;
  @override
  State<_BlogTagsDialog> createState() => _BlogTagsDialogState();
}

class _BlogTagsDialogState extends State<_BlogTagsDialog> {
  late final _controller = TextEditingController(
    text: widget.initial.join(' '),
  );
  List<String> get _tags => _controller.text
      .split(RegExp(r'\s+'))
      .where((tag) => tag.isNotEmpty)
      .toSet()
      .toList();
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tags = _tags;
    return AlertDialog(
      title: const Text('添加标签'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        minLines: 1,
        maxLines: 4,
        decoration: InputDecoration(
          labelText: '标签',
          helperText: '空格分隔，最多 10 个',
          errorText: tags.length > 10 ? '最多添加 10 个标签' : null,
        ),
        onChanged: (_) => setState(() {}),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: tags.length > 10
              ? null
              : () {
                  final current = _tags;
                  if (current.length <= 10) Navigator.pop(context, current);
                },
          child: const Text('完成'),
        ),
      ],
    );
  }
}
