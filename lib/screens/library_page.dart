import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/layout/app_layout.dart';
import '../core/storage/browsing_store.dart';
import '../models/bangumi_models.dart';
import '../models/episode_edit.dart';
import '../models/library_batch.dart';
import 'library_batch_page.dart';
import '../widgets/episode_undo_message.dart';
import '../state/session_controller.dart';
import '../state/local_data_state.dart';
import '../widgets/episode_grid_sheet.dart';
import '../widgets/subject_widgets.dart';
import '../widgets/collection_sync_status.dart';
import 'subject_detail_screen.dart';

enum _ProgressFilter { all, notStarted, inProgress, completed }

enum _LibrarySort { updated, title, rating, progress }

/// Statistics count every subject type, so their destinations start untyped.
Future<void> openCollectionLibrary(
  BuildContext context, {
  required CollectionType? collectionType,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute<void>(
    builder: (_) => Scaffold(
      appBar: AppBar(title: const Text('我的收藏')),
      body: LibraryPage(
        initialSubjectType: null,
        initialCollectionType: collectionType,
        showTitle: false,
        rememberFilters: false,
      ),
    ),
  ),
);

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({
    super.key,
    this.initialSubjectType = SubjectType.anime,
    this.initialCollectionType = CollectionType.doing,
    this.showTitle = true,
    this.rememberFilters = true,
  });

  final SubjectType? initialSubjectType;
  final CollectionType? initialCollectionType;
  final bool showTitle;
  final bool rememberFilters;

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  late SubjectType? _subjectType;
  late CollectionType? _type;
  _ProgressFilter _progress = _ProgressFilter.all;
  _LibrarySort _sort = _LibrarySort.updated;
  int _minimumRating = 0;
  String _query = '';
  Timer? _searchDebounce;
  final _queryController = TextEditingController();
  String? _account;
  int _preferenceRevision = 0;
  bool _saveErrorShown = false;
  bool _selectionMode = false;
  final _selected = <int>{};

  @override
  void initState() {
    super.initState();
    _subjectType = widget.initialSubjectType;
    _type = widget.initialCollectionType;
    ref.listenManual(localBrowsingEpochProvider, (_, _) {
      if (mounted) _bindAccount(ref.read(sessionProvider).user?.username);
    });
    ref.listenManual(sessionProvider.select((state) => state.user?.id), (
      previous,
      next,
    ) {
      if (mounted && previous != next) {
        setState(() {
          _selected.clear();
          _selectionMode = false;
        });
      }
    });
    ref.listenManual(sessionProvider.select((state) => state.collections), (
      _,
      next,
    ) {
      final available = {for (final item in next) item.subjectId};
      if (mounted && _selected.any((id) => !available.contains(id))) {
        setState(() => _selected.removeWhere((id) => !available.contains(id)));
      }
    });
    ref.listenManual(
      sessionProvider.select((state) => state.user?.username),
      (previous, next) => _bindAccount(next),
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _queryController.dispose();
    _preferenceRevision++;
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _preferenceRevision++;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 180), () {
      if (mounted) setState(() => _query = value);
    });
  }

  void _bindAccount(String? account) {
    _account = account;
    final revision = ++_preferenceRevision;
    _searchDebounce?.cancel();
    _queryController.clear();
    setState(() {
      _query = '';
      _selected.clear();
      _selectionMode = false;
      _subjectType = widget.initialSubjectType;
      _type = widget.initialCollectionType;
      _progress = _ProgressFilter.all;
      _sort = _LibrarySort.updated;
      _minimumRating = 0;
      _saveErrorShown = false;
    });
    if (widget.rememberFilters && account != null && account.isNotEmpty) {
      unawaited(_restorePreferences(account, revision));
    }
  }

  Future<void> _restorePreferences(String account, int revision) async {
    try {
      final data = await ref
          .read(browsingRepositoryProvider)
          .readLibrary(account);
      if (!mounted ||
          revision != _preferenceRevision ||
          account != _account ||
          data == null) {
        return;
      }
      setState(() {
        if (data.containsKey('subject_type')) {
          _subjectType = data['subject_type'] == null
              ? null
              : SubjectType.values
                        .where((type) => type.value == data['subject_type'])
                        .firstOrNull ??
                    widget.initialSubjectType;
        }
        if (data.containsKey('collection_type')) {
          _type = data['collection_type'] == null
              ? null
              : CollectionType.values
                        .where((type) => type.value == data['collection_type'])
                        .firstOrNull ??
                    widget.initialCollectionType;
        }
        _sort =
            _LibrarySort.values
                .where((sort) => sort.name == data['sort'])
                .firstOrNull ??
            _LibrarySort.updated;
        _progress =
            _ProgressFilter.values
                .where((progress) => progress.name == data['progress'])
                .firstOrNull ??
            _ProgressFilter.all;
        if (_subjectType != null &&
            !_subjectType!.hasEpisodes &&
            !_subjectType!.hasVolumes) {
          _progress = _ProgressFilter.all;
        }
        _minimumRating =
            data['minimum_rating'] is int &&
                const [0, 6, 7, 8, 9].contains(data['minimum_rating'])
            ? data['minimum_rating'] as int
            : 0;
      });
    } catch (_) {
      // Optional preferences never block browsing the loaded collection.
    }
  }

  void _changeFilters(VoidCallback change) {
    _preferenceRevision++;
    setState(change);
    final account = _account;
    if (!widget.rememberFilters || account == null || account.isEmpty) return;
    unawaited(
      _savePreferences(account, {
        'subject_type': _subjectType?.value,
        'collection_type': _type?.value,
        'progress': _progress.name,
        'sort': _sort.name,
        'minimum_rating': _minimumRating,
      }),
    );
  }

  Future<void> _savePreferences(
    String account,
    Map<String, dynamic> settings,
  ) async {
    try {
      await ref.read(browsingRepositoryProvider).saveLibrary(account, settings);
      if (mounted && account == _account) _saveErrorShown = false;
    } catch (_) {
      if (!mounted || account != _account || _saveErrorShown) return;
      _saveErrorShown = true;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('筛选已应用，但暂时无法记住设置')));
    }
  }

  int get _activeFilters =>
      (_progress == _ProgressFilter.all ? 0 : 1) +
      (_sort == _LibrarySort.updated ? 0 : 1) +
      (_minimumRating == 0 ? 0 : 1);

  String _statusLabel(CollectionType type) => _subjectType != null
      ? type.labelFor(_subjectType!)
      : switch (type) {
          CollectionType.wish => '计划中',
          CollectionType.doing => '进行中',
          CollectionType.done => '已完成',
          CollectionType.onHold => '搁置',
          CollectionType.dropped => '抛弃',
        };

  List<UserCollection> _filterItems(List<UserCollection> collections) {
    final keyword = _query.trim().toLowerCase();
    final items = collections.where((item) {
      final matchSubject =
          _subjectType == null || item.subject.type == _subjectType;
      final matchType = _type == null || item.type == _type;
      final matchQuery =
          keyword.isEmpty ||
          item.subject.name.toLowerCase().contains(keyword) ||
          item.subject.nameCn.toLowerCase().contains(keyword);
      final matchRating = item.rate >= _minimumRating;
      return matchSubject &&
          matchType &&
          matchQuery &&
          matchRating &&
          _matchesProgress(item);
    }).toList();
    _sortItems(items);
    return items;
  }

  void _toggleSelection(int subjectId) => setState(() {
    if (!_selected.add(subjectId)) _selected.remove(subjectId);
  });

  Future<void> _openBatch(LibraryBatchKind kind) async {
    final session = ref.read(sessionProvider.notifier);
    final actor = session.batchAccount;
    if (actor == null || _selected.isEmpty) return;
    final selected = {
      for (final item in ref.read(sessionProvider).collections)
        if (_selected.contains(item.subjectId)) item.subjectId: item,
    }.values.toList();
    FocusManager.instance.primaryFocus?.unfocus();
    final completed = await openLibraryBatchPage(
      context,
      selected: selected,
      kind: kind,
    );
    if (!mounted || !session.isCurrentBatchAccount(actor)) return;
    setState(() {
      _selected.removeAll(completed ?? {});
      if (_selected.isEmpty) _selectionMode = false;
    });
  }

  Widget _batchToolbar(List<UserCollection> visible, bool canBatch) {
    final visibleIds = visible.map((item) => item.subjectId).toSet();
    final outside = _selected.difference(visibleIds).length;
    final allVisible =
        visibleIds.isNotEmpty && _selected.containsAll(visibleIds);
    return SafeArea(
      top: false,
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '已选 ${_selected.length} 部${outside > 0 ? ' · $outside 部在当前筛选外' : ''}',
                key: const ValueKey('library-selected-count'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Text('长按作品可查看完整名称', style: Theme.of(context).textTheme.bodySmall),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  TextButton(
                    onPressed: visibleIds.isEmpty
                        ? null
                        : () => setState(() {
                            if (allVisible) {
                              _selected.removeAll(visibleIds);
                            } else {
                              _selected.addAll(visibleIds);
                            }
                          }),
                    child: Text(allVisible ? '取消当前选择' : '全选当前结果'),
                  ),
                  TextButton(
                    onPressed: _selected.isEmpty
                        ? null
                        : () => setState(_selected.clear),
                    child: const Text('清空选择'),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _selected.clear();
                      _selectionMode = false;
                    }),
                    child: const Text('退出多选'),
                  ),
                  FilledButton.tonal(
                    onPressed: (_selected.isEmpty || !canBatch)
                        ? null
                        : () => _openBatch(LibraryBatchKind.collection),
                    child: const Text('改状态'),
                  ),
                  FilledButton.tonal(
                    onPressed: (_selected.isEmpty || !canBatch)
                        ? null
                        : () => _openBatch(LibraryBatchKind.schedule),
                    child: const Text('加入新番表'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final collections = ref.watch(
      sessionProvider.select((state) => state.collections),
    );
    final isLoadingCollections = ref.watch(
      sessionProvider.select((state) => state.isLoadingCollections),
    );
    final updating = ref.watch(
      sessionProvider.select((state) => state.updatingSubjects),
    );
    final typedCount = collections
        .where(
          (item) => _subjectType == null || item.subject.type == _subjectType,
        )
        .length;
    final items = _filterItems(collections);
    final canBatch = ref.watch(
      sessionProvider.select(
        (state) =>
            state.user != null &&
            state.phase == SessionPhase.signedIn &&
            !state.isAuthenticating,
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final phone = constraints.maxWidth < AppLayout.phone;
        final columns = constraints.maxWidth >= 1050
            ? 3
            : constraints.maxWidth >= 640
            ? 2
            : 1;
        final pagePad = AppLayout.pagePadding(context);
        return Column(
          children: [
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => ref.read(sessionProvider.notifier).refresh(),
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        pagePad,
                        AppLayout.pageTopPadding(context),
                        pagePad,
                        0,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1220),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: double.infinity,
                                  child: Wrap(
                                    alignment: WrapAlignment.spaceBetween,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      if (widget.showTitle)
                                        Text(
                                          '我的收藏',
                                          style: AppLayout.pageTitleStyle(
                                            context,
                                          ),
                                        ),
                                      TextButton.icon(
                                        key: const ValueKey(
                                          'library-selection-toggle',
                                        ),
                                        onPressed: !canBatch
                                            ? null
                                            : () => setState(() {
                                                _selectionMode =
                                                    !_selectionMode;
                                                if (!_selectionMode) {
                                                  _selected.clear();
                                                }
                                              }),
                                        icon: const Icon(
                                          Icons.checklist_rounded,
                                        ),
                                        label: Text(
                                          _selectionMode ? '结束多选' : '批量整理',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  phone
                                      ? '找到 ${items.length} 部'
                                            '${isLoadingCollections ? ' · 同步中' : ''}'
                                      : '找到 ${items.length} 部 · '
                                            '当前类型 $typedCount 部 · '
                                            '全部 ${collections.length} 部'
                                            '${isLoadingCollections ? ' · 同步中' : ''}',
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                    fontSize: phone ? 13 : null,
                                  ),
                                ),
                                const CollectionSyncStatus(),
                                if (isLoadingCollections &&
                                    collections.isEmpty) ...[
                                  const SizedBox(height: 10),
                                  const LinearProgressIndicator(minHeight: 3),
                                ],
                                SizedBox(height: phone ? 16 : 24),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: _queryController,
                                        onChanged: _onQueryChanged,
                                        decoration: InputDecoration(
                                          hintText: '在收藏中搜索',
                                          isDense: phone,
                                          prefixIcon: const Icon(
                                            Icons.search_rounded,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Badge.count(
                                      count: _activeFilters,
                                      isLabelVisible: _activeFilters > 0,
                                      child: phone
                                          ? IconButton.filledTonal(
                                              tooltip: '筛选',
                                              onPressed: _showFilters,
                                              icon: const Icon(
                                                Icons.tune_rounded,
                                              ),
                                            )
                                          : FilledButton.tonalIcon(
                                              onPressed: _showFilters,
                                              icon: const Icon(
                                                Icons.tune_rounded,
                                              ),
                                              label: const Text('筛选'),
                                            ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: [
                                      ChoiceChip(
                                        label: const Text('全部类型'),
                                        selected: _subjectType == null,
                                        onSelected: (_) => _changeFilters(() {
                                          _subjectType = null;
                                          _progress = _ProgressFilter.all;
                                        }),
                                      ),
                                      const SizedBox(width: 8),
                                      for (final type
                                          in SubjectType.values) ...[
                                        ChoiceChip(
                                          avatar: Icon(
                                            subjectTypeIcon(type),
                                            size: 16,
                                          ),
                                          label: Text(type.label),
                                          selected: _subjectType == type,
                                          onSelected: (_) => _changeFilters(() {
                                            _subjectType = type;
                                            if (!type.hasEpisodes &&
                                                !type.hasVolumes) {
                                              _progress = _ProgressFilter.all;
                                            }
                                          }),
                                        ),
                                        const SizedBox(width: 8),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: [
                                      ChoiceChip(
                                        label: const Text('全部状态'),
                                        selected: _type == null,
                                        onSelected: (_) =>
                                            _changeFilters(() => _type = null),
                                      ),
                                      const SizedBox(width: 8),
                                      for (final type
                                          in CollectionType.values) ...[
                                        ChoiceChip(
                                          label: Text(_statusLabel(type)),
                                          selected: _type == type,
                                          onSelected: (_) => _changeFilters(
                                            () => _type = type,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                      ],
                                    ],
                                  ),
                                ),
                                if (_activeFilters > 0) ...[
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Text(
                                        '已启用：',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.labelMedium,
                                      ),
                                      if (_progress != _ProgressFilter.all)
                                        Chip(
                                          label: Text(
                                            _progressLabel(_progress),
                                          ),
                                        ),
                                      if (_minimumRating > 0)
                                        Chip(
                                          label: Text('个人评分 ≥ $_minimumRating'),
                                        ),
                                      if (_sort != _LibrarySort.updated)
                                        Chip(label: Text(_sortLabel(_sort))),
                                      TextButton(
                                        onPressed: _resetFilters,
                                        child: const Text('清除'),
                                      ),
                                    ],
                                  ),
                                ],
                                const SizedBox(height: 18),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (items.isEmpty)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: EmptyState(
                            icon: Icons.filter_alt_off_outlined,
                            title: '没有符合条件的收藏',
                            message: '换个类型、分类、搜索词或清除筛选条件试试看。',
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(pagePad, 0, pagePad, 60),
                        sliver: SliverLayoutBuilder(
                          builder: (context, constraints) {
                            final width = constraints.crossAxisExtent;
                            final contentWidth = width > 1220 ? 1220.0 : width;
                            final side = (width - contentWidth) / 2;
                            return SliverPadding(
                              padding: EdgeInsets.symmetric(
                                horizontal: side > 0 ? side : 0,
                              ),
                              sliver: SliverGrid(
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: columns,
                                      mainAxisExtent: subjectTileHeight(
                                        context,
                                      ),
                                      mainAxisSpacing: 14,
                                      crossAxisSpacing: 14,
                                    ),
                                delegate: SliverChildBuilderDelegate((
                                  context,
                                  index,
                                ) {
                                  final collection = items[index];
                                  final supportsEpisodes =
                                      collection.subject.type.hasEpisodes;
                                  return SubjectTile(
                                    key: ValueKey(
                                      'library-subject-${collection.subjectId}',
                                    ),
                                    selected: _selectionMode
                                        ? _selected.contains(
                                            collection.subjectId,
                                          )
                                        : null,
                                    onSelectionChanged: _selectionMode
                                        ? () => _toggleSelection(
                                            collection.subjectId,
                                          )
                                        : null,
                                    subject: collection.subject,
                                    collection: collection,
                                    showTypeBadge: _subjectType == null,
                                    busy: updating.contains(
                                      collection.subjectId,
                                    ),
                                    onTap: _selectionMode
                                        ? () => _toggleSelection(
                                            collection.subjectId,
                                          )
                                        : () => Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  SubjectDetailScreen(
                                                    subject: collection.subject,
                                                  ),
                                            ),
                                          ),
                                    onEpisodeGrid:
                                        supportsEpisodes && !_selectionMode
                                        ? () => showEpisodeGridSheet(
                                            context,
                                            ref,
                                            collection,
                                          )
                                        : null,
                                    onNextEpisode:
                                        supportsEpisodes &&
                                            !_selectionMode &&
                                            collection.type ==
                                                CollectionType.doing
                                        ? () async {
                                            EpisodeUndo? undo;
                                            final controller = ref.read(
                                              sessionProvider.notifier,
                                            );
                                            final error = await controller
                                                .markNextEpisode(
                                                  collection,
                                                  onUndoReady: (value) =>
                                                      undo = value,
                                                );
                                            if (context.mounted) {
                                              if (error != null) {
                                                showAppMessage(context, error);
                                              } else if (undo != null) {
                                                showEpisodeUndoMessage(
                                                  context,
                                                  controller,
                                                  undo!,
                                                );
                                              }
                                            }
                                          }
                                        : null,
                                  );
                                }, childCount: items.length),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (_selectionMode) _batchToolbar(items, canBatch),
          ],
        );
      },
    );
  }

  bool _matchesProgress(UserCollection item) {
    if (_progress == _ProgressFilter.all) return true;
    final type = item.subject.type;
    if (type.hasEpisodes) {
      final watched = item.episodeStatus;
      final total = item.subject.episodeCount;
      return switch (_progress) {
        _ProgressFilter.all => true,
        _ProgressFilter.notStarted => watched == 0,
        _ProgressFilter.inProgress =>
          watched > 0 && (total == 0 || watched < total),
        _ProgressFilter.completed => total > 0 && watched >= total,
      };
    }
    if (type.hasVolumes) {
      final read = item.volumeStatus;
      final total = item.subject.volumeCount;
      return switch (_progress) {
        _ProgressFilter.all => true,
        _ProgressFilter.notStarted => read == 0,
        _ProgressFilter.inProgress => read > 0 && (total == 0 || read < total),
        _ProgressFilter.completed => total > 0 && read >= total,
      };
    }
    return _progress == _ProgressFilter.all;
  }

  void _sortItems(List<UserCollection> items) {
    switch (_sort) {
      case _LibrarySort.updated:
        items.sort((a, b) {
          final aTime = a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bTime = b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bTime.compareTo(aTime);
        });
      case _LibrarySort.title:
        items.sort(
          (a, b) => a.subject.displayName.compareTo(b.subject.displayName),
        );
      case _LibrarySort.rating:
        items.sort((a, b) => b.rate.compareTo(a.rate));
      case _LibrarySort.progress:
        items.sort((a, b) => _progressValue(b).compareTo(_progressValue(a)));
    }
  }

  double _progressValue(UserCollection item) {
    if (item.subject.type.hasEpisodes) {
      final total = item.subject.episodeCount;
      return total > 0
          ? item.episodeStatus / total
          : item.episodeStatus.toDouble();
    }
    if (item.subject.type.hasVolumes) {
      final total = item.subject.volumeCount;
      return total > 0
          ? item.volumeStatus / total
          : item.volumeStatus.toDouble();
    }
    return 0;
  }

  Future<void> _showFilters() async {
    _preferenceRevision++;
    final account = _account;
    var progress = _progress;
    var sort = _sort;
    var minimumRating = _minimumRating;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 620),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            24,
            4,
            24,
            24 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('筛选与排序', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 24),
              Text('进度', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final value in _ProgressFilter.values)
                    ChoiceChip(
                      label: Text(_progressLabel(value)),
                      selected: progress == value,
                      onSelected: (_) => setSheetState(() => progress = value),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              Text('最低个人评分', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final value in [0, 6, 7, 8, 9])
                    ChoiceChip(
                      label: Text(value == 0 ? '不限' : '$value 分以上'),
                      selected: minimumRating == value,
                      onSelected: (_) =>
                          setSheetState(() => minimumRating = value),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              Text('排序', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final value in _LibrarySort.values)
                    ChoiceChip(
                      label: Text(_sortLabel(value)),
                      selected: sort == value,
                      onSelected: (_) => setSheetState(() => sort = value),
                    ),
                ],
              ),
              const SizedBox(height: 30),
              Row(
                children: [
                  TextButton(
                    onPressed: () => setSheetState(() {
                      progress = _ProgressFilter.all;
                      sort = _LibrarySort.updated;
                      minimumRating = 0;
                    }),
                    child: const Text('重置'),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: () {
                      if (!mounted || account != _account) {
                        Navigator.pop(sheetContext);
                        return;
                      }
                      _changeFilters(() {
                        _progress = progress;
                        _sort = sort;
                        _minimumRating = minimumRating;
                      });
                      Navigator.pop(sheetContext);
                    },
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('应用筛选'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _resetFilters() => _changeFilters(() {
    _progress = _ProgressFilter.all;
    _sort = _LibrarySort.updated;
    _minimumRating = 0;
  });

  String _progressLabel(_ProgressFilter value) => switch (value) {
    _ProgressFilter.all => '不限',
    _ProgressFilter.notStarted => '尚未开始',
    _ProgressFilter.inProgress => '进行中',
    _ProgressFilter.completed => '已完成',
  };

  String _sortLabel(_LibrarySort value) => switch (value) {
    _LibrarySort.updated => '最近更新',
    _LibrarySort.title => '按标题',
    _LibrarySort.rating => '按我的评分',
    _LibrarySort.progress => '按完成度',
  };
}
