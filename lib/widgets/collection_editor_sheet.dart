import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/bangumi_models.dart';
import '../state/session_controller.dart';
import 'subject_widgets.dart';

/// Full collection editor: status, score, comment, tags, privacy.
Future<bool> showCollectionEditorSheet(
  BuildContext context, {
  required Subject subject,
  UserCollection? collection,
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
    ),
  );
  return result == true;
}

class _CollectionEditorSheet extends ConsumerStatefulWidget {
  const _CollectionEditorSheet({
    required this.subject,
    required this.collection,
  });

  final Subject subject;
  final UserCollection? collection;

  @override
  ConsumerState<_CollectionEditorSheet> createState() =>
      _CollectionEditorSheetState();
}

class _CollectionEditorSheetState
    extends ConsumerState<_CollectionEditorSheet> {
  late CollectionType _type;
  late int _rate;
  late final TextEditingController _comment;
  late final TextEditingController _tags;
  late bool _private;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    final c = widget.collection;
    _type = c?.type ?? CollectionType.wish;
    _rate = c?.rate ?? 0;
    _comment = TextEditingController(text: c?.comment ?? '');
    _tags = TextEditingController(text: (c?.tags ?? const []).join(' '));
    _private = c?.private ?? false;
  }

  @override
  void dispose() {
    _comment.dispose();
    _tags.dispose();
    super.dispose();
  }

  List<String> get _parsedTags => _tags.text
      .split(RegExp(r'[\s,，;；]+'))
      .map((t) => t.trim())
      .where((t) => t.isNotEmpty)
      .toList();

  Future<void> _save() async {
    setState(() => _saving = true);
    final error = await ref
        .read(sessionProvider.notifier)
        .changeCollection(
          widget.subject,
          _type,
          rate: _rate,
          comment: _comment.text.trim(),
          tags: _parsedTags,
          private: _private,
          completeEpisodesWhenDone: true,
        );
    if (!mounted) return;
    setState(() => _saving = false);
    if (error != null) {
      showAppMessage(context, error);
      return;
    }
    showAppMessage(context, '收藏已保存');
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final subject = widget.subject;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 4, 20, bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('管理收藏', style: Theme.of(context).textTheme.titleLarge),
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
                    color: const Color(0xFFF3A646),
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
            const SizedBox(height: 14),
            TextField(
              controller: _comment,
              maxLines: 3,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: '吐槽 / 短评',
                alignLabelWithHint: true,
                hintText: '可选，写给自己的一句话',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _tags,
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
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_rounded),
              label: Text(_saving ? '保存中…' : '保存'),
            ),
          ],
        ),
      ),
    );
  }
}
