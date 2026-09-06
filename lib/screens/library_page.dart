import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/layout/app_layout.dart';
import '../models/bangumi_models.dart';
import '../state/session_controller.dart';
import '../widgets/episode_grid_sheet.dart';
import '../widgets/subject_widgets.dart';
import 'subject_detail_screen.dart';

enum _ProgressFilter { all, notStarted, inProgress, completed }

enum _LibrarySort { updated, title, rating, progress }

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  SubjectType? _subjectType = SubjectType.anime;
  CollectionType? _type = CollectionType.doing;
  _ProgressFilter _progress = _ProgressFilter.all;
  _LibrarySort _sort = _LibrarySort.updated;
  int _minimumRating = 0;
  String _query = '';
  Timer? _searchDebounce;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 180), () {
      if (mounted) setState(() => _query = value);
    });
  }

  int get _activeFilters =>
      (_progress == _ProgressFilter.all ? 0 : 1) +
      (_sort == _LibrarySort.updated ? 0 : 1) +
      (_minimumRating == 0 ? 0 : 1);

  SubjectType get _labelType => _subjectType ?? SubjectType.anime;

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

    return LayoutBuilder(
      builder: (context, constraints) {
        final phone = constraints.maxWidth < AppLayout.phone;
        final columns = constraints.maxWidth >= 1050
            ? 3
            : constraints.maxWidth >= 640
            ? 2
            : 1;
        final pagePad = AppLayout.pagePadding(context);
        return RefreshIndicator(
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
                          Text(
                            '我的收藏',
                            style: AppLayout.pageTitleStyle(context),
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
                          if (isLoadingCollections && collections.isEmpty) ...[
                            const SizedBox(height: 10),
                            const LinearProgressIndicator(minHeight: 3),
                          ],
                          SizedBox(height: phone ? 16 : 24),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
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
                                        icon: const Icon(Icons.tune_rounded),
                                      )
                                    : FilledButton.tonalIcon(
                                        onPressed: _showFilters,
                                        icon: const Icon(Icons.tune_rounded),
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
                                  onSelected: (_) => setState(() {
                                    _subjectType = null;
                                    _progress = _ProgressFilter.all;
                                  }),
                                ),
                                const SizedBox(width: 8),
                                for (final type in SubjectType.values) ...[
                                  ChoiceChip(
                                    avatar: Icon(
                                      subjectTypeIcon(type),
                                      size: 16,
                                    ),
                                    label: Text(type.label),
                                    selected: _subjectType == type,
                                    onSelected: (_) => setState(() {
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
                                      setState(() => _type = null),
                                ),
                                const SizedBox(width: 8),
                                for (final type in CollectionType.values) ...[
                                  ChoiceChip(
                                    label: Text(type.labelFor(_labelType)),
                                    selected: _type == type,
                                    onSelected: (_) =>
                                        setState(() => _type = type),
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
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  '已启用：',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.labelMedium,
                                ),
                                if (_progress != _ProgressFilter.all)
                                  Chip(label: Text(_progressLabel(_progress))),
                                if (_minimumRating > 0)
                                  Chip(label: Text('个人评分 ≥ $_minimumRating')),
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
                                mainAxisExtent: subjectTileHeight(context),
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
                              subject: collection.subject,
                              collection: collection,
                              showTypeBadge: _subjectType == null,
                              busy: updating.contains(collection.subjectId),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => SubjectDetailScreen(
                                    subject: collection.subject,
                                  ),
                                ),
                              ),
                              onEpisodeGrid: supportsEpisodes
                                  ? () => showEpisodeGridSheet(
                                      context,
                                      ref,
                                      collection,
                                    )
                                  : null,
                              onNextEpisode:
                                  supportsEpisodes &&
                                      collection.type == CollectionType.doing
                                  ? () async {
                                      final error = await ref
                                          .read(sessionProvider.notifier)
                                          .markNextEpisode(collection);
                                      if (context.mounted) {
                                        showAppMessage(
                                          context,
                                          error ?? '已看完下一集',
                                        );
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
                      setState(() {
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

  void _resetFilters() => setState(() {
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
