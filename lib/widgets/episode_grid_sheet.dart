import 'package:flutter/material.dart';
import 'readable_subject_title.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/bangumi_support.dart';
import '../core/storage/snapshot_cache.dart';
import '../models/bangumi_models.dart';
import '../state/session_controller.dart';
import 'subject_widgets.dart';

Future<void> showEpisodeGridSheet(
  BuildContext context,
  WidgetRef ref,
  UserCollection collection,
) async {
  await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 760),
    builder: (_) => FractionallySizedBox(
      heightFactor: .86,
      child: _EpisodeGridPanel(collection: collection),
    ),
  );
}

class _EpisodeGridPanel extends ConsumerStatefulWidget {
  const _EpisodeGridPanel({required this.collection});

  final UserCollection collection;

  @override
  ConsumerState<_EpisodeGridPanel> createState() => _EpisodeGridPanelState();
}

class _EpisodeGridPanelState extends ConsumerState<_EpisodeGridPanel> {
  List<UserEpisodeCollection> _episodes = const [];
  final Set<int> _updating = {};
  bool _loading = true;
  String? _error;
  int? _typeFilter;

  /// True once the user changed any episode status in this sheet session.
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final cache = SnapshotCache.shared;
    final cached = await cache.readEpisodeCollections(
      widget.collection.subjectId,
    );
    if (!mounted) return;
    if (cached != null && cached.isNotEmpty) {
      final localCached = await ref
          .read(sessionProvider.notifier)
          .applyPendingEpisodeChanges(widget.collection.subjectId, cached);
      if (!mounted) return;
      setState(() {
        _episodes = localCached;
        _loading = false;
      });
    }
    try {
      var episodes = await ref
          .read(bangumiApiProvider)
          .getEpisodeCollections(
            widget.collection.subjectId,
            episodeType: null,
          );
      episodes = await ref
          .read(sessionProvider.notifier)
          .applyPendingEpisodeChanges(widget.collection.subjectId, episodes);
      if (!mounted) return;
      setState(() {
        _episodes = episodes;
        _loading = false;
      });
      await cache.writeEpisodeCollections(
        widget.collection.subjectId,
        episodes,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_episodes.isEmpty) _error = error.toString();
      });
    }
  }

  List<UserEpisodeCollection> get _visible {
    if (_typeFilter == null) return _episodes;
    return [
      for (final item in _episodes)
        if (item.episode.type == _typeFilter) item,
    ];
  }

  List<int> get _types {
    final set = <int>{};
    for (final item in _episodes) {
      set.add(item.episode.type);
    }
    final list = set.toList()..sort();
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final watched = visible.where((item) => item.type == 2).length;
    // Route drag-down / system back also carries the changed flag so an
    // edited grid is never silently dropped.
    return PopScope<bool>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.of(context).pop(_changed);
      },
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 4, 10, 14),
            child: Row(
              children: [
                SubjectCover(
                  subject: widget.collection.subject,
                  width: 46,
                  height: 62,
                  borderRadius: 9,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ReadableSubjectTitle(
                        widget.collection.subject.displayName,
                        maxLines: 1,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _loading
                            ? '正在读取章节状态…'
                            : '看过 $watched / ${visible.length}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '关闭',
                  onPressed: () => Navigator.pop(context, _changed),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (_types.length > 1)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Row(
                children: [
                  ChoiceChip(
                    label: const Text('全部'),
                    selected: _typeFilter == null,
                    onSelected: (_) => setState(() => _typeFilter = null),
                  ),
                  const SizedBox(width: 8),
                  for (final type in _types) ...[
                    ChoiceChip(
                      label: Text(BangumiSupport.episodeTypeLabel(type)),
                      selected: _typeFilter == type,
                      onSelected: (_) => setState(() => _typeFilter = type),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 10),
            child: Row(
              children: [
                _Legend(
                  color: Theme.of(context).colorScheme.primary,
                  label: '看过',
                ),
                const SizedBox(width: 16),
                _Legend(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  label: '想看',
                ),
                const SizedBox(width: 16),
                _Legend(
                  color: Colors.transparent,
                  label: '未标记',
                  outlined: true,
                ),
                const Spacer(),
                Text(
                  '点击切换 · 长按更多',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Expanded(child: _buildContent(context)),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return EmptyState(
        icon: Icons.cloud_off_outlined,
        title: '章节状态加载失败',
        message: _error!,
        action: FilledButton.tonalIcon(
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('重试'),
        ),
      );
    }
    final visible = _visible;
    if (visible.isEmpty) {
      return const EmptyState(
        icon: Icons.grid_view_rounded,
        title: '暂无可点的格子',
        message: '这个条目还没有章节数据，或当前类型筛选为空。',
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(22, 10, 22, 30),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 78,
        mainAxisExtent: 58,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
      ),
      itemCount: visible.length,
      itemBuilder: (context, index) {
        final item = visible[index];
        final realIndex = _episodes.indexWhere(
          (e) => e.episode.id == item.episode.id,
        );
        return _EpisodeCell(
          item: item,
          busy: _updating.contains(item.episode.id),
          onTap: () => _setStatus(realIndex, item.type == 2 ? 0 : 2),
          onLongPress: () => _chooseStatus(realIndex),
        );
      },
    );
  }

  Future<void> _chooseStatus(int index) async {
    final item = _episodes[index];
    final type = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('第 ${_number(item.episode.number)} 话'),
        children: [
          _statusOption(
            context,
            2,
            '看过',
            Icons.check_circle_rounded,
            item.type,
          ),
          _statusOption(context, 1, '想看', Icons.schedule_rounded, item.type),
          _statusOption(context, 3, '抛弃', Icons.block_rounded, item.type),
          _statusOption(
            context,
            0,
            '未标记',
            Icons.remove_circle_outline,
            item.type,
          ),
        ],
      ),
    );
    if (type != null && type != item.type) await _setStatus(index, type);
  }

  Widget _statusOption(
    BuildContext context,
    int value,
    String label,
    IconData icon,
    int current,
  ) => SimpleDialogOption(
    onPressed: () => Navigator.pop(context, value),
    child: ListTile(
      leading: Icon(icon),
      title: Text(label),
      trailing: current == value ? const Icon(Icons.check_rounded) : null,
    ),
  );

  Future<void> _setStatus(int index, int type) async {
    final item = _episodes[index];
    if (_updating.contains(item.episode.id)) return;
    setState(() {
      _updating.add(item.episode.id);
      _episodes[index] = item.copyWith(type: type);
    });
    final error = await ref
        .read(sessionProvider.notifier)
        .setEpisode(
          subjectId: widget.collection.subjectId,
          episodeId: item.episode.id,
          type: type,
          previousType: item.type,
          trackGlobalBusy: false,
        );
    if (!mounted) return;
    setState(() {
      _updating.remove(item.episode.id);
      if (error != null) {
        _episodes[index] = item;
      } else {
        _changed = true;
      }
    });
    if (error != null) {
      showAppMessage(context, error);
    }
  }

  String _number(double value) =>
      value % 1 == 0 ? value.toInt().toString() : value.toStringAsFixed(1);
}

class _EpisodeCell extends StatelessWidget {
  const _EpisodeCell({
    required this.item,
    required this.busy,
    required this.onTap,
    required this.onLongPress,
  });

  final UserEpisodeCollection item;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (background, foreground, border) = switch (item.type) {
      2 => (colors.primary, colors.onPrimary, colors.primary),
      1 => (
        colors.secondaryContainer,
        colors.onSecondaryContainer,
        colors.secondaryContainer,
      ),
      3 => (
        colors.errorContainer,
        colors.onErrorContainer,
        colors.errorContainer,
      ),
      _ => (Colors.white, colors.onSurface, colors.outlineVariant),
    };
    final number = item.episode.number % 1 == 0
        ? item.episode.number.toInt().toString()
        : item.episode.number.toStringAsFixed(1);
    return Tooltip(
      message: item.episode.displayName,
      child: Material(
        color: background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: busy ? null : onTap,
          onLongPress: busy ? null : onLongPress,
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      number,
                      style: TextStyle(
                        color: foreground,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      item.type == 2
                          ? '看过'
                          : item.type == 1
                          ? '想看'
                          : item.type == 3
                          ? '抛弃'
                          : 'EP',
                      style: TextStyle(
                        color: foreground.withValues(alpha: .78),
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),
              if (busy)
                Positioned(
                  right: 5,
                  top: 5,
                  child: SizedBox.square(
                    dimension: 9,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: foreground,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({
    required this.color,
    required this.label,
    this.outlined = false,
  });

  final Color color;
  final String label;
  final bool outlined;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 11,
        height: 11,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: outlined
              ? Border.all(color: Theme.of(context).colorScheme.outline)
              : null,
        ),
      ),
      const SizedBox(width: 5),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}
