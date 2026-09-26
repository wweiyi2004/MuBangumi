import 'package:flutter/material.dart';
import 'readable_subject_title.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/bangumi_support.dart';
import '../models/bangumi_models.dart';
import '../models/episode_edit.dart';
import 'episode_undo_message.dart';
import '../state/session_controller.dart';
import 'subject_widgets.dart';
import '../core/theme/app_tokens.dart';

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
      child: ScaffoldMessenger(
        child: Scaffold(body: _EpisodeGridPanel(collection: collection)),
      ),
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
  int _loadGeneration = 0;
  late final int? _accountId;
  bool get _sameAccount =>
      mounted && ref.read(sessionProvider).user?.id == _accountId;

  /// True once the user changed any episode status in this sheet session.
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _accountId = ref.read(sessionProvider).user?.id;
    ref.listenManual(sessionProvider.select((state) => state.user?.id), (
      _,
      next,
    ) {
      if (next != _accountId && mounted) {
        _loadGeneration++;
        setState(() {
          _episodes = const [];
          _loading = false;
          _error = '登录已变化，请重新打开章节';
        });
      }
    });
    ref.listenManual(sessionProvider.select((state) => state.lastEpisodeEdit), (
      _,
      change,
    ) {
      if (!_sameAccount ||
          change == null ||
          change.subjectId != widget.collection.subjectId) {
        return;
      }
      setState(() {
        _episodes = [
          for (final item in _episodes)
            item.episode.id == change.episodeId
                ? item.copyWith(type: change.type)
                : item,
        ];
      });
    });
    Future.microtask(_load);
  }

  Future<void> _load() async {
    if (!_sameAccount) return;
    final generation = ++_loadGeneration;
    bool current() => _sameAccount && generation == _loadGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    final session = ref.read(sessionProvider.notifier);
    try {
      final cached = await session.readEpisodeSnapshot(
        widget.collection.subjectId,
      );
      if (!current()) return;
      if (cached != null && cached.isNotEmpty) {
        setState(() {
          _episodes = cached;
          _loading = false;
        });
      }
    } catch (_) {}
    try {
      final episodes = await session.loadEpisodeCollections(
        widget.collection.subjectId,
      );
      if (!current()) return;
      setState(() {
        _episodes = episodes;
        _loading = false;
      });
    } catch (error) {
      if (!current()) return;
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
            child: Wrap(
              spacing: 16,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _Legend(
                  color: Theme.of(context).colorScheme.primary,
                  label: '看过',
                ),
                _Legend(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  label: '想看',
                ),
                _Legend(
                  color: Colors.transparent,
                  label: '未标记',
                  outlined: true,
                ),
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
          onPressed: _sameAccount ? _load : null,
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
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 78,
        mainAxisExtent: 38 + MediaQuery.textScalerOf(context).scale(20),
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
    if (!mounted || !_sameAccount) return;
    final currentIndex = _episodes.indexWhere(
      (entry) => entry.episode.id == item.episode.id,
    );
    if (currentIndex >= 0 &&
        type != null &&
        type != _episodes[currentIndex].type) {
      await _setStatus(currentIndex, type);
    }
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
    if (!_sameAccount || index < 0 || index >= _episodes.length) return;
    final item = _episodes[index];
    if (!_sameAccount || _updating.contains(item.episode.id)) return;
    setState(() {
      _updating.add(item.episode.id);
      _episodes[index] = item.copyWith(type: type);
    });
    EpisodeUndo? undo;
    final controller = ref.read(sessionProvider.notifier);
    final error = await controller.setEpisode(
      subjectId: widget.collection.subjectId,
      episodeId: item.episode.id,
      type: type,
      previousType: item.type,
      episode: item.episode,
      onUndoReady: (value) => undo = value,
      trackGlobalBusy: false,
    );
    if (!mounted || !_sameAccount) return;
    setState(() {
      _updating.remove(item.episode.id);
      if (error != null) {
        _episodes = [
          for (final entry in _episodes)
            entry.episode.id == item.episode.id ? item : entry,
        ];
      } else {
        _changed = true;
      }
    });
    if (error != null) {
      showAppMessage(context, error);
    } else if (undo != null) {
      showEpisodeUndoMessage(context, controller, undo!);
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
      _ => (colors.surface, colors.onSurface, colors.outlineVariant),
    };
    final number = item.episode.number % 1 == 0
        ? item.episode.number.toInt().toString()
        : item.episode.number.toStringAsFixed(1);
    return Tooltip(
      message: item.episode.displayName,
      child: Material(
        color: background,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.medium,
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
