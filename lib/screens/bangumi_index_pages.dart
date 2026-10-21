import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/theme/anime_icon.dart';
import '../core/network/community_service.dart';
import '../core/sharing/share_content.dart';
import '../models/bangumi_index.dart';
import '../models/bangumi_models.dart';
import '../models/community_topic_submission.dart';
import '../navigation/app_destination.dart';
import '../state/service_providers.dart';
import '../state/session_controller.dart';
import '../widgets/community_rich_content.dart';
import '../widgets/content_share_sheet.dart';
import '../widgets/subject_widgets.dart';

class BangumiIndexListPage extends ConsumerStatefulWidget {
  const BangumiIndexListPage({
    super.key,
    this.username,
    this.embedded = false,
    this.usePrimaryScrollController = false,
  });
  final String? username;
  final bool embedded, usePrimaryScrollController;
  @override
  ConsumerState<BangumiIndexListPage> createState() => _IndexListState();
}

class _IndexListState extends ConsumerState<BangumiIndexListPage> {
  late final _service = ref.read(communityServiceProvider);
  late BangumiIndexMode _mode = widget.username == null
      ? BangumiIndexMode.hot
      : BangumiIndexMode.created;
  final _items = <BangumiIndex>[];
  bool _loading = false, _more = true;
  String? _error;
  int _offset = 0, _generation = 0;
  @override
  void initState() {
    super.initState();
    _service.accountChanges.addListener(_accountChanged);
    Future<void>.microtask(() => _load(reset: true));
  }

  void _accountChanged() {
    _generation++;
    scheduleMicrotask(() {
      if (mounted) unawaited(_load(reset: true));
    });
  }

  @override
  void dispose() {
    _service.accountChanges.removeListener(_accountChanged);
    _generation++;
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant BangumiIndexListPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.username != widget.username) {
      _generation++;
      _items.clear();
      scheduleMicrotask(() {
        if (mounted) unawaited(_load(reset: true));
      });
    }
  }

  Future<void> _load({bool reset = false}) async {
    if (!reset && (_loading || !_more)) return;
    final request = ++_generation, identity = _service.identityRevision;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _offset = 0;
        _items.clear();
        _more = true;
      }
    });
    try {
      final page = await _service.loadIndexes(
        mode: _mode,
        username: widget.username,
        offset: _offset,
        refresh: reset,
      );
      if (!mounted ||
          request != _generation ||
          identity != _service.identityRevision) {
        return;
      }
      setState(() {
        final seen = _items.map((item) => item.id).toSet();
        _items.addAll(page.data.where((item) => seen.add(item.id)));
        final count = page.rawCount ?? page.data.length;
        _offset += count;
        _more = count > 0 && _offset < page.total;
      });
    } catch (error) {
      if (mounted && request == _generation) {
        setState(
          () => _error = error.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted && request == _generation) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    final identity = _service.identityRevision;
    final id = await _showIndexEditor(context, _service);
    if (!mounted || id == null || identity != _service.identityRevision) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => IndexDetailRoute(indexId: id)),
    );
    if (mounted) unawaited(_load(reset: true));
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(sessionProvider.select((state) => state.user?.id));
    final modes = widget.username == null
        ? BangumiIndexMode.values
        : const [BangumiIndexMode.created, BangumiIndexMode.collected];
    final content = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final mode in modes)
                      ChoiceChip(
                        label: Text(switch (mode) {
                          BangumiIndexMode.hot => '热门',
                          BangumiIndexMode.latest => '最新',
                          BangumiIndexMode.created => '创建的',
                          BangumiIndexMode.collected => '收藏的',
                        }),
                        selected: _mode == mode,
                        onSelected: (_) {
                          setState(() => _mode = mode);
                          _load(reset: true);
                        },
                      ),
                  ],
                ),
              ),
              if (_service.isAuthenticated)
                IconButton(
                  tooltip: '创建番剧单',
                  onPressed: _create,
                  icon: const AnimeIcon(Icons.playlist_add_rounded),
                ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _load(reset: true),
            child: ListView.builder(
              primary: widget.usePrimaryScrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 36),
              itemCount: _items.length + 1,
              itemBuilder: (context, index) {
                if (index == _items.length) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        if (_loading) const CircularProgressIndicator(),
                        if (_error != null) Text(_error!),
                        if (!_loading && _items.isEmpty && _error == null)
                          const Text('暂无目录，可创建自己的番剧单'),
                        if (!_loading && (_more || _error != null))
                          TextButton(
                            onPressed: () => _load(reset: _items.isEmpty),
                            child: Text(_error == null ? '加载更多' : '重试'),
                          ),
                      ],
                    ),
                  );
                }
                final item = _items[index];
                return Card(
                  child: ListTile(
                    leading: AnimeIcon(
                      item.isPrivate
                          ? Icons.lock_outline_rounded
                          : Icons.list_alt_rounded,
                    ),
                    title: Text(item.title),
                    subtitle: Text(
                      '${item.total} 项 · ${item.collects} 人收藏${item.owner == null ? '' : ' · ${item.owner!.displayName}'}${item.isPrivate ? ' · 私密' : ''}',
                    ),
                    trailing: const AnimeIcon(Icons.chevron_right_rounded),
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => IndexDetailRoute(indexId: item.id),
                        ),
                      );
                      if (mounted) unawaited(_load(reset: true));
                    },
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
    return widget.embedded
        ? content
        : Scaffold(
            appBar: AppBar(title: const Text('番剧单 · 目录')),
            body: content,
          );
  }
}

class BangumiIndexDetailPage extends ConsumerStatefulWidget {
  const BangumiIndexDetailPage({super.key, required this.indexId});
  final int indexId;
  @override
  ConsumerState<BangumiIndexDetailPage> createState() => _IndexDetailState();
}

class _IndexDetailState extends ConsumerState<BangumiIndexDetailPage> {
  late final _service = ref.read(communityServiceProvider);
  BangumiIndex? _index;
  final _entries = <BangumiIndexEntry>[];
  bool _loading = false, _busy = false, _more = true, _animeOnly = true;
  String? _error;
  int _generation = 0, _offset = 0;
  @override
  void initState() {
    super.initState();
    _service.accountChanges.addListener(_accountChanged);
    Future<void>.microtask(() => _load(reset: true));
  }

  void _accountChanged() {
    _generation++;
    scheduleMicrotask(() {
      if (!mounted) return;
      setState(() {
        _index = null;
        _entries.clear();
        _busy = false;
      });
      unawaited(_load(reset: true));
    });
  }

  @override
  void dispose() {
    _service.accountChanges.removeListener(_accountChanged);
    _generation++;
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (!reset && (_loading || !_more)) return;
    final generation = ++_generation, identity = _service.identityRevision;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _offset = 0;
        _entries.clear();
        _more = true;
      }
    });
    try {
      final detail = reset || _index == null
          ? await _service.loadIndex(widget.indexId, refresh: reset)
          : _index!;
      final page = await _service.loadIndexEntries(
        widget.indexId,
        offset: _offset,
        animeOnly: _animeOnly,
        refresh: reset,
      );
      if (!mounted ||
          generation != _generation ||
          identity != _service.identityRevision) {
        return;
      }
      setState(() {
        _index = detail;
        final seen = _entries.map((entry) => entry.id).toSet();
        _entries.addAll(page.data.where((entry) => seen.add(entry.id)));
        final received = page.rawCount ?? page.data.length;
        _offset += received;
        _more = received > 0 && _offset < page.total;
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(
          () => _error = error.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _write(Future<void> Function() action) async {
    if (_busy) return;
    final identity = _service.identityRevision;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted && identity == _service.identityRevision) {
        await _load(reset: true);
      }
    } catch (error) {
      if (mounted && identity == _service.identityRevision) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    } finally {
      if (mounted && identity == _service.identityRevision) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _add() async {
    final identity = _service.identityRevision;
    final subject = await showModalBottomSheet<Subject>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const _IndexSubjectPicker(),
    );
    if (!mounted || subject == null || identity != _service.identityRevision) {
      return;
    }
    await _write(() => _service.addIndexSubject(widget.indexId, subject.id));
  }

  Future<void> _delete() async {
    final identity = _service.identityRevision;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('删除番剧单？'),
        content: const Text('目录及其中的推荐语将从官网删除，请确认已保留需要的内容。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (!mounted ||
        confirmed != true ||
        identity != _service.identityRevision ||
        _busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await _service.deleteIndex(widget.indexId);
      if (mounted && identity == _service.identityRevision) {
        Navigator.pop(context);
      }
    } catch (error) {
      if (mounted && identity == _service.identityRevision) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted && identity == _service.identityRevision) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _entryActions(BangumiIndexEntry entry) async {
    final identity = _service.identityRevision;
    final order = TextEditingController(text: '${entry.order}'),
        comment = TextEditingController(text: entry.comment);
    try {
      final action = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('编辑目录条目'),
          scrollable: true,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: order,
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true,
                ),
                decoration: const InputDecoration(labelText: '排序值（越小越靠前）'),
              ),
              TextField(
                controller: comment,
                maxLines: 4,
                decoration: const InputDecoration(labelText: '推荐语 / 备注'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'remove'),
              child: const Text('移除条目'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, 'save'),
              child: const Text('保存'),
            ),
          ],
        ),
      );
      if (!mounted || action == null || identity != _service.identityRevision) {
        return;
      }
      if (action == 'remove') {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('从番剧单移除？'),
            content: const Text('作品的收藏状态会保留。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('移除'),
              ),
            ],
          ),
        );
        if (!mounted ||
            confirmed != true ||
            identity != _service.identityRevision) {
          return;
        }
        await _write(() => _service.removeIndexEntry(widget.indexId, entry.id));
      } else {
        final value = int.tryParse(order.text);
        if (value == null) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('请输入整数排序值')));
          return;
        }
        await _write(
          () => _service.updateIndexEntry(
            widget.indexId,
            entry,
            order: value,
            comment: comment.text,
          ),
        );
      }
    } finally {
      order.dispose();
      comment.dispose();
    }
  }

  void _share() {
    final index = _index;
    if (index == null || index.isPrivate) return;
    final subjects = _entries
        .map((e) => e.subject)
        .whereType<Subject>()
        .toList();
    final cover =
        subjects.where((s) => s.imageUrl.isNotEmpty).firstOrNull?.imageUrl ??
        '';
    showContentShareSheet(
      context,
      ShareContent(
        title: index.title,
        subtitle: index.owner?.displayName ?? '',
        excerpt: [
          plainShareText(index.description),
          if (subjects.isNotEmpty)
            subjects.take(3).map((s) => s.displayName).join(' / '),
        ].where((s) => s.isNotEmpty).join('\n'),
        imageUrl: cover,
        detail: '番剧单 · 精选作品',
        metrics: [
          ShareMetric('收录作品', '${index.total}'),
          ShareMetric('收藏人数', '${index.collects}'),
        ],
        url: 'https://bgm.tv/index/${index.id}',
        fileKey: 'index-${index.id}',
        isTimeline: cover.isEmpty,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(sessionProvider.select((state) => state.user));
    final index = _index;
    final owner = index != null && index.ownerId == user?.id;
    return Scaffold(
      appBar: AppBar(
        title: const Text('番剧单 · 目录'),
        actions: [
          if (owner)
            IconButton(
              tooltip: '删除番剧单',
              onPressed: _busy ? null : _delete,
              icon: const AnimeIcon(Icons.delete_outline_rounded),
            ),
          IconButton(
            tooltip: '在官网打开目录',
            onPressed: () => launchUrl(
              Uri.parse('https://bgm.tv/index/${widget.indexId}'),
              mode: LaunchMode.externalApplication,
            ),
            icon: const AnimeIcon(Icons.open_in_new_rounded),
          ),
          if (index != null && !index.isPrivate)
            IconButton(
              tooltip: '分享番剧单',
              onPressed: _share,
              icon: const AnimeIcon(Icons.ios_share_rounded),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(reset: true),
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          itemCount: _entries.length + 2,
          itemBuilder: (context, position) {
            if (position == 0) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (index != null) ...[
                    Text(
                      index.title,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${index.total} 项 · ${index.collects} 人收藏${index.isPrivate ? ' · 仅自己可见' : ''}',
                    ),
                    if (index.owner != null)
                      TextButton(
                        onPressed: () =>
                            openUserProfileFromCommunity(context, index.owner!),
                        child: Text('创建者：${index.owner!.displayName}'),
                      ),
                    if (index.description.isNotEmpty)
                      CommunityRichContent(index.description),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        key: const Key('index-action-row'),
                        spacing: 6,
                        children: [
                          if (!index.isPrivate)
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                              ),
                              onPressed: _share,
                              icon: const AnimeIcon(
                                Icons.ios_share_rounded,
                                size: 18,
                              ),
                              label: const Text('分享'),
                            ),
                          if (_service.isAuthenticated)
                            FilledButton.tonalIcon(
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                              ),
                              onPressed: _busy
                                  ? null
                                  : () => _write(
                                      () => _service.collectIndex(
                                        widget.indexId,
                                        !index.collected,
                                      ),
                                    ),
                              icon: AnimeIcon(
                                index.collected
                                    ? Icons.bookmark_rounded
                                    : Icons.bookmark_border_rounded,
                              ),
                              label: Text(index.collected ? '已收藏' : '收藏'),
                            ),
                          if (owner)
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                              ),
                              onPressed: _busy
                                  ? null
                                  : () async {
                                      final identity =
                                          _service.identityRevision;
                                      final result = await _showIndexEditor(
                                        context,
                                        _service,
                                        original: index,
                                      );
                                      if (mounted &&
                                          result != null &&
                                          identity ==
                                              _service.identityRevision) {
                                        _load(reset: true);
                                      }
                                    },
                              icon: const AnimeIcon(Icons.edit_rounded),
                              label: const Text('编辑'),
                            ),
                          if (owner)
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                              ),
                              onPressed: _busy ? null : _add,
                              icon: const AnimeIcon(Icons.add_rounded),
                              label: const Text('添加'),
                            ),
                        ],
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('动画'),
                          selected: _animeOnly,
                          onSelected: (_) {
                            setState(() => _animeOnly = true);
                            _load(reset: true);
                          },
                        ),
                        ChoiceChip(
                          label: const Text('全部条目'),
                          selected: !_animeOnly,
                          onSelected: (_) {
                            setState(() => _animeOnly = false);
                            _load(reset: true);
                          },
                        ),
                      ],
                    ),
                  ],
                ],
              );
            }
            if (position == _entries.length + 1) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    if (_loading) const CircularProgressIndicator(),
                    if (_error != null) Text(_error!),
                    if (!_loading && _entries.isEmpty && _error == null)
                      const Text('此筛选下暂无作品，试试“全部条目”'),
                    if (!_loading && (_more || _error != null))
                      TextButton(
                        onPressed: () => _load(reset: _index == null),
                        child: Text(_error == null ? '加载更多' : '重试'),
                      ),
                  ],
                ),
              );
            }
            final entry = _entries[position - 1];
            final subject = entry.subject;
            return Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListTile(
                    contentPadding: const EdgeInsets.all(12),
                    leading: subject == null
                        ? const AnimeIcon(Icons.visibility_off_outlined)
                        : SubjectCover(
                            subject: subject,
                            width: 52,
                            height: 78,
                            borderRadius: 8,
                          ),
                    title: Text(subject?.displayName ?? '条目暂时不可见 / 已移除'),
                    subtitle: subject == null
                        ? null
                        : Text(
                            '${subject.type.label}${subject.score > 0 ? ' · ${subject.score.toStringAsFixed(1)} 分' : ''}',
                          ),
                    trailing: owner
                        ? IconButton(
                            tooltip: '编辑条目备注与顺序',
                            onPressed: _busy
                                ? null
                                : () => _entryActions(entry),
                            icon: const AnimeIcon(Icons.more_horiz_rounded),
                          )
                        : const AnimeIcon(Icons.chevron_right_rounded),
                    onTap: subject == null
                        ? null
                        : () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => SubjectRoute(subject: subject),
                            ),
                          ),
                  ),
                  if (entry.comment.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: CommunityRichContent(entry.comment),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

Future<int?> _showIndexEditor(
  BuildContext context,
  CommunityService service, {
  BangumiIndex? original,
}) => showDialog<int>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _IndexEditor(service: service, original: original),
);

class _IndexEditor extends StatefulWidget {
  const _IndexEditor({required this.service, this.original});
  final CommunityService service;
  final BangumiIndex? original;
  @override
  State<_IndexEditor> createState() => _IndexEditorState();
}

class _IndexEditorState extends State<_IndexEditor> {
  late final _title = TextEditingController(text: widget.original?.title ?? '');
  late final _desc = TextEditingController(
    text: widget.original?.description ?? '',
  );
  late final int _identity;
  @override
  void initState() {
    super.initState();
    _identity = widget.service.identityRevision;
  }

  late bool _private = widget.original?.isPrivate ?? false;
  bool _busy = false, _uncertain = false;
  String? _error;
  Future<void> _save() async {
    if (_busy || _uncertain) return;
    if (_identity != widget.service.identityRevision) {
      setState(() => _error = '账号已变化，请关闭后重新编辑');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await widget.service.saveIndex(
        original: widget.original,
        title: _title.text,
        description: _desc.text,
        isPrivate: _private,
      );
      if (mounted && _identity == widget.service.identityRevision) {
        Navigator.pop(context, id);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _uncertain = error is CommunitySubmissionUncertain;
          _error = _uncertain
              ? '创建结果待确认，请先关闭并核对自己创建的目录，避免重复创建。'
              : error.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.original == null ? '创建番剧单' : '编辑番剧单'),
    scrollable: true,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _title,
          maxLength: 80,
          decoration: const InputDecoration(labelText: '标题'),
        ),
        TextField(
          controller: _desc,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(labelText: '介绍 / 推荐理由'),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('仅自己可见'),
          value: _private,
          onChanged: _busy ? null : (value) => setState(() => _private = value),
        ),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('关闭'),
      ),
      FilledButton(
        onPressed: _busy || _uncertain ? null : _save,
        child: Text(_busy ? '保存中…' : '保存'),
      ),
    ],
  );
}

class _IndexSubjectPicker extends ConsumerStatefulWidget {
  const _IndexSubjectPicker();
  @override
  ConsumerState<_IndexSubjectPicker> createState() =>
      _IndexSubjectPickerState();
}

class _IndexSubjectPickerState extends ConsumerState<_IndexSubjectPicker> {
  final _query = TextEditingController();
  late final _owner = ref.read(sessionProvider).user?.id;
  List<Subject>? _results;
  bool _loading = false;
  String? _error;
  int _generation = 0;
  Future<void> _search() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(bangumiApiProvider);
      final text = _query.text.trim(), id = int.tryParse(_query.text.trim());
      final result = id == null
          ? await api.searchSubjects(
              text,
              subjectType: SubjectType.anime,
              limit: 20,
            )
          : [await api.getSubject(id)];
      if (mounted && generation == _generation) {
        setState(() => _results = result);
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error = '搜索暂时失败，请重试');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    if (session.user?.id != _owner) {
      return const SafeArea(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('账号已变化，请返回重新选择'),
        ),
      );
    }
    final subjects =
        _results ?? session.collections.map((item) => item.subject).toList();
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .8,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _query,
                onSubmitted: (_) => _search(),
                decoration: InputDecoration(
                  hintText: '搜索动画名称 / 条目 ID',
                  suffixIcon: IconButton(
                    tooltip: '搜索作品',
                    onPressed: _loading ? null : _search,
                    icon: const AnimeIcon(Icons.search_rounded),
                  ),
                ),
              ),
            ),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null) Text(_error!),
            Expanded(
              child: ListView.builder(
                itemCount: subjects.length,
                itemBuilder: (context, index) => ListTile(
                  title: Text(subjects[index].displayName),
                  subtitle: Text(subjects[index].name),
                  onTap: () => Navigator.pop(context, subjects[index]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
