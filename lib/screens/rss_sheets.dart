import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/rss_models.dart';
import '../models/schedule_models.dart';
import '../state/rss_controller.dart';
import '../widgets/subject_widgets.dart';

Future<void> showRssSourcesSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 720),
    builder: (_) => const _RssSourcesSheet(),
  );
}

Future<void> showRssBindSheet(
  BuildContext context, {
  required ScheduleItem item,
  required SeasonKey season,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 720),
    builder: (_) => _RssBindSheet(item: item, season: season),
  );
}

Future<void> showRssUpdatesSheet(
  BuildContext context, {
  int? subjectId,
  String? subjectName,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 720),
    builder: (_) =>
        _RssUpdatesSheet(subjectId: subjectId, subjectName: subjectName),
  );
}

class _RssSourcesSheet extends ConsumerStatefulWidget {
  const _RssSourcesSheet();

  @override
  ConsumerState<_RssSourcesSheet> createState() => _RssSourcesSheetState();
}

class _RssSourcesSheetState extends ConsumerState<_RssSourcesSheet> {
  final _nameController = TextEditingController();
  final _urlController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(rssProvider);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          children: [
            Text('更新源（种子站 RSS）', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              '添加 Mikan / 动漫花园等订阅链接。只有绑定到新番表的番才会产生提醒。',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '名称（可空）',
                hintText: '例如：Mikan 我的订阅',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: 'RSS 链接',
                hintText: 'https://…',
              ),
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _add(),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: _add,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('添加'),
                ),
                const SizedBox(width: 10),
                FilledButton.tonalIcon(
                  onPressed: state.refreshing
                      ? null
                      : () => ref
                            .read(rssProvider.notifier)
                            .refreshAll(force: true),
                  icon: state.refreshing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded),
                  label: Text(state.refreshing ? '检查中…' : '检查更新'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              '已添加（${state.sources.length}）',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (state.sources.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: EmptyState(
                  icon: Icons.rss_feed_rounded,
                  title: '还没有更新源',
                  message: '从种子站复制 RSS 订阅地址粘贴到上方。',
                ),
              )
            else
              for (final source in state.sources)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Icon(
                      source.enabled
                          ? Icons.rss_feed_rounded
                          : Icons.rss_feed_outlined,
                    ),
                    title: Text(source.name),
                    subtitle: Text(
                      [
                        source.url,
                        if (source.lastFetchAt != null)
                          '上次：${_fmtTime(source.lastFetchAt!)}',
                        if (source.lastError.isNotEmpty)
                          '错误：${source.lastError}',
                      ].join('\n'),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                    isThreeLine: true,
                    trailing: IconButton(
                      tooltip: '删除',
                      icon: Icon(
                        Icons.delete_outline_rounded,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      onPressed: () => ref
                          .read(rssProvider.notifier)
                          .deleteSource(source.id),
                    ),
                  ),
                ),
            const SizedBox(height: 12),
            Text(
              '当前绑定 ${state.bindings.length} 条 · 未读提醒 ${state.totalUnread}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        );
      },
    );
  }

  Future<void> _add() async {
    await ref
        .read(rssProvider.notifier)
        .addSource(name: _nameController.text, url: _urlController.text);
    if (!mounted) return;
    if (ref.read(rssProvider).sources.isNotEmpty) {
      _urlController.clear();
    }
  }
}

class _RssBindSheet extends ConsumerStatefulWidget {
  const _RssBindSheet({required this.item, required this.season});

  final ScheduleItem item;
  final SeasonKey season;

  @override
  ConsumerState<_RssBindSheet> createState() => _RssBindSheetState();
}

class _RssBindSheetState extends ConsumerState<_RssBindSheet> {
  int? _sourceId;
  late final TextEditingController _keywords;
  late final TextEditingController _exclude;

  @override
  void initState() {
    super.initState();
    _keywords = TextEditingController(text: widget.item.displayName);
    _exclude = TextEditingController(text: '合集,NC-OP,NC-ED,NCOP,NCED,SP,特典');
  }

  @override
  void dispose() {
    _keywords.dispose();
    _exclude.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(rssProvider);
    final existing = state.bindings
        .where((b) => b.subjectId == widget.item.subjectId)
        .toList();
    final sources = state.sources;
    // The FormField owns the displayed selection (initialValue); _sourceId
    // only tracks explicit user changes. Default to the first source so the
    // save action works without touching the dropdown.
    final effectiveSourceId =
        _sourceId ?? (sources.isEmpty ? null : sources.first.id);

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 8,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('绑定更新源', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              widget.item.displayName,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            if (sources.isEmpty)
              EmptyState(
                icon: Icons.rss_feed_rounded,
                title: '还没有更新源',
                message: '请先添加种子站 RSS，再回来绑定。',
                action: FilledButton(
                  onPressed: () {
                    Navigator.pop(context);
                    showRssSourcesSheet(context);
                  },
                  child: const Text('去添加源'),
                ),
              )
            else ...[
              DropdownButtonFormField<int>(
                initialValue: effectiveSourceId,
                decoration: const InputDecoration(labelText: '更新源'),
                items: [
                  for (final source in sources)
                    DropdownMenuItem(
                      value: source.id,
                      child: Text(source.name),
                    ),
                ],
                onChanged: (value) => setState(() => _sourceId = value),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _keywords,
                decoration: const InputDecoration(
                  labelText: '标题需包含（关键词）',
                  helperText: '种子标题需包含这些词才会提醒；默认用番名',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _exclude,
                decoration: const InputDecoration(
                  labelText: '排除词（可选）',
                  helperText: '标题含任一排除词则忽略',
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: effectiveSourceId == null
                    ? null
                    : () async {
                        await ref
                            .read(rssProvider.notifier)
                            .bindSubject(
                              sourceId: effectiveSourceId,
                              item: widget.item,
                              season: widget.season,
                              matchKeywords: _keywords.text,
                              excludeKeywords: _exclude.text,
                            );
                        if (context.mounted) Navigator.pop(context);
                      },
                child: const Text('保存绑定'),
              ),
            ],
            if (existing.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('已有绑定', style: Theme.of(context).textTheme.titleSmall),
              for (final binding in existing)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    state.sources
                            .where((s) => s.id == binding.sourceId)
                            .map((s) => s.name)
                            .firstOrNull ??
                        '源 #${binding.sourceId}',
                  ),
                  subtitle: Text('关键词：${binding.matchKeywords}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.link_off_rounded),
                    tooltip: '解除',
                    onPressed: () =>
                        ref.read(rssProvider.notifier).unbind(binding.id),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RssUpdatesSheet extends ConsumerStatefulWidget {
  const _RssUpdatesSheet({this.subjectId, this.subjectName});

  final int? subjectId;
  final String? subjectName;

  @override
  ConsumerState<_RssUpdatesSheet> createState() => _RssUpdatesSheetState();
}

class _RssUpdatesSheetState extends ConsumerState<_RssUpdatesSheet> {
  late Future<List<RssItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<RssItem>> _load() {
    final notifier = ref.read(rssProvider.notifier);
    if (widget.subjectId != null) {
      return notifier.itemsForSubject(widget.subjectId!);
    }
    return notifier.recentItems();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.subjectName == null
                          ? '更新提醒'
                          : '${widget.subjectName} · 更新',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  if (widget.subjectId != null)
                    TextButton(
                      onPressed: () async {
                        await ref
                            .read(rssProvider.notifier)
                            .markSubjectRead(widget.subjectId!);
                        setState(() => _future = _load());
                      },
                      child: const Text('全部已读'),
                    ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<List<RssItem>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final items = snapshot.data ?? const [];
                  if (items.isEmpty) {
                    return const EmptyState(
                      icon: Icons.notifications_none_rounded,
                      title: '暂无更新',
                      message: '绑定源并点「检查更新」后，匹配到的种子会出现在这里。',
                    );
                  }
                  return ListView.separated(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        tileColor: item.read
                            ? null
                            : Theme.of(context).colorScheme.primaryContainer
                                  .withValues(alpha: .35),
                        leading: Icon(
                          item.read
                              ? Icons.article_outlined
                              : Icons.fiber_new_rounded,
                        ),
                        title: Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          [
                            if (item.publishedAt != null)
                              _fmtTime(item.publishedAt!),
                            if (!item.read) '未读',
                          ].join(' · '),
                        ),
                        trailing: const Icon(Icons.open_in_new_rounded),
                        onTap: () async {
                          await ref
                              .read(rssProvider.notifier)
                              .markItemRead(item.id);
                          final uri = Uri.tryParse(item.link);
                          if (uri != null) {
                            await launchUrl(
                              uri,
                              mode: LaunchMode.externalApplication,
                            );
                          }
                          if (mounted) setState(() => _future = _load());
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

String _fmtTime(DateTime time) {
  final local = time.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
