import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/bangumi_models.dart';
import '../state/session_controller.dart';
import '../widgets/episode_grid_sheet.dart';
import '../widgets/subject_widgets.dart';
import 'subject_detail_screen.dart';

class DiscoverPage extends ConsumerStatefulWidget {
  const DiscoverPage({super.key});

  @override
  ConsumerState<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends ConsumerState<DiscoverPage> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  List<Subject> _subjects = const [];
  bool _loading = true;
  String? _error;
  int _requestId = 0;

  SubjectType _subjectType = SubjectType.anime;
  late int _browseYear;
  late int _browseQuarter; // anime/real only
  String _browseSort = 'rank'; // date | rank for non-season browse
  String _searchSort = 'match';
  int _minimumRating = 0;
  int _startYear = 0;
  String _tag = '';

  bool get _searching => _searchController.text.trim().isNotEmpty;

  /// TV-like seasonal browse (year + quarter).
  bool get _supportsSeason =>
      _subjectType == SubjectType.anime || _subjectType == SubjectType.real;

  String get _yearFilterLabel => switch (_subjectType) {
    SubjectType.book => '最早出版年份',
    SubjectType.music => '最早发售年份',
    SubjectType.game => '最早发售年份',
    SubjectType.real => '最早播出年份',
    SubjectType.anime => '最早播出年份',
  };

  List<String> get _suggestedTags => switch (_subjectType) {
    SubjectType.anime => const ['原创', '漫画改', '小说改', '科幻', '日常', '治愈'],
    SubjectType.book => const ['漫画', '小说', '轻小说', '画集', '科幻'],
    SubjectType.music => const ['OP', 'ED', 'OST', '专辑', '角色歌'],
    SubjectType.game => const ['Galgame', 'RPG', 'ACT', 'PC', 'NS'],
    SubjectType.real => const ['日剧', '美剧', '综艺', '纪录片'],
  };

  String get _searchHint => switch (_subjectType) {
    SubjectType.anime => '搜索动画，例如：迷宫饭',
    SubjectType.book => '搜索书籍，例如：葬送的芙莉莲',
    SubjectType.music => '搜索音乐，例如：YOASOBI',
    SubjectType.game => '搜索游戏，例如：艾尔登法环',
    SubjectType.real => '搜索三次元，例如：孤独的美食家',
  };

  int get _activeFilterCount {
    var count = 0;
    if (_searching) {
      if (_searchSort != 'match') count++;
      if (_minimumRating > 0) count++;
      if (_startYear > 0) count++;
      if (_tag.trim().isNotEmpty) count++;
    } else if (_supportsSeason) {
      final now = DateTime.now();
      final currentQuarter = (now.month - 1) ~/ 3;
      if (_browseYear != now.year || _browseQuarter != currentQuarter) count++;
    } else {
      final now = DateTime.now();
      if (_browseYear != now.year) count++;
      if (_browseSort != 'rank') count++;
    }
    return count;
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _browseYear = now.year;
    _browseQuarter = (now.month - 1) ~/ 3;
    Future.microtask(_runCurrentQuery);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), _runCurrentQuery);
    setState(() {});
  }

  void _selectSubjectType(SubjectType type) {
    if (_subjectType == type) return;
    setState(() {
      _subjectType = type;
      // Reset filters that often break cross-type search.
      _searchSort = 'match';
      _minimumRating = 0;
      _startYear = 0;
      _tag = '';
      _browseSort = 'rank';
      final now = DateTime.now();
      _browseYear = now.year;
      _browseQuarter = (now.month - 1) ~/ 3;
      _error = null;
    });
    _runCurrentQuery();
  }

  void _clearSearchFilters() {
    setState(() {
      _searchSort = 'match';
      _minimumRating = 0;
      _startYear = 0;
      _tag = '';
    });
  }

  void _clearBrowseFilters() {
    final now = DateTime.now();
    setState(() {
      _browseYear = now.year;
      _browseQuarter = (now.month - 1) ~/ 3;
      _browseSort = 'rank';
    });
  }

  void _runCurrentQuery() {
    final keyword = _searchController.text.trim();
    if (keyword.isNotEmpty) {
      unawaited(_search(keyword));
      return;
    }
    unawaited(_loadBrowse());
  }

  Future<void> _loadBrowse() async {
    final requestId = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(bangumiApiProvider);
      final subjects = _supportsSeason
          ? await api.browseSubjects(
              type: _subjectType,
              year: _browseYear,
              month: _browseQuarter * 3 + 1,
              sort: 'rank',
            )
          : await api.browseSubjects(
              type: _subjectType,
              year: _browseYear,
              sort: _browseSort,
            );
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _subjects = subjects;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _search(String keyword) async {
    final requestId = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tags = _tag
          .split(RegExp(r'[,，\s]+'))
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();
      final subjects = await ref
          .read(bangumiApiProvider)
          .searchSubjects(
            keyword,
            sort: _searchSort,
            minimumRating: _minimumRating,
            startYear: _startYear,
            tags: tags,
            subjectType: _subjectType,
          );
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _subjects = subjects;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final collections = ref.watch(
      sessionProvider.select((state) => state.collections),
    );
    final collectionMap = {
      for (final item in collections) item.subjectId: item,
    };

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 60),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1220),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('发现', style: Theme.of(context).textTheme.headlineLarge),
              const SizedBox(height: 6),
              Text(
                '按类型浏览与搜索 · 当前：${_subjectType.label}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: _onSearchChanged,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) {
                        _debounce?.cancel();
                        _runCurrentQuery();
                      },
                      decoration: InputDecoration(
                        hintText: _searchHint,
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _searching
                            ? IconButton(
                                tooltip: '清空搜索',
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {});
                                  _runCurrentQuery();
                                },
                                icon: const Icon(Icons.close_rounded),
                              )
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Badge.count(
                    count: _activeFilterCount,
                    isLabelVisible: _activeFilterCount > 0,
                    child: FilledButton.tonalIcon(
                      onPressed: _showFilters,
                      icon: const Icon(Icons.tune_rounded),
                      label: const Text('筛选'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final type in SubjectType.values) ...[
                      ChoiceChip(
                        avatar: Icon(subjectTypeIcon(type), size: 16),
                        label: Text(type.label),
                        selected: _subjectType == type,
                        onSelected: (_) => _selectSubjectType(type),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    _searching
                        ? '${_subjectType.label}搜索结果'
                        : _supportsSeason
                        ? '${_subjectType.label}季度榜'
                        : '${_subjectType.label}年度榜',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  if (!_searching && _supportsSeason)
                    Chip(
                      label: Text(
                        '$_browseYear · ${_quarterLabel(_browseQuarter)}',
                      ),
                    ),
                  if (!_searching && !_supportsSeason) ...[
                    Chip(label: Text('$_browseYear 年')),
                    Chip(label: Text(_browseSortLabel(_browseSort))),
                  ],
                  if (_searching && _searchSort != 'match')
                    Chip(label: Text(_searchSortLabel(_searchSort))),
                  if (_searching && _minimumRating > 0)
                    Chip(label: Text('评分 ≥ $_minimumRating')),
                  if (_searching && _startYear > 0)
                    Chip(label: Text('$_startYear 年后')),
                  if (_searching && _tag.trim().isNotEmpty)
                    Chip(label: Text('标签：${_tag.trim()}')),
                  if (_activeFilterCount > 0)
                    TextButton(
                      onPressed: () {
                        if (_searching) {
                          _clearSearchFilters();
                        } else {
                          _clearBrowseFilters();
                        }
                        _runCurrentQuery();
                      },
                      child: const Text('清除筛选'),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 100),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                SizedBox(
                  width: double.infinity,
                  child: EmptyState(
                    icon: Icons.cloud_off_outlined,
                    title: '没有连接上 Bangumi',
                    message: _error!,
                    action: FilledButton.tonalIcon(
                      onPressed: _runCurrentQuery,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('重试'),
                    ),
                  ),
                )
              else if (_subjects.isEmpty)
                _EmptyDiscoverState(
                  searching: _searching,
                  subjectType: _subjectType,
                  activeFilterCount: _activeFilterCount,
                  keyword: _searchController.text.trim(),
                  onClearFilters: () {
                    if (_searching) {
                      _clearSearchFilters();
                    } else {
                      _clearBrowseFilters();
                    }
                    _runCurrentQuery();
                  },
                  onClearSearch: () {
                    _searchController.clear();
                    _clearSearchFilters();
                    setState(() {});
                    _runCurrentQuery();
                  },
                  onOpenFilters: _showFilters,
                )
              else
                SubjectGrid(
                  itemCount: _subjects.length,
                  itemBuilder: (context, index) {
                    final subject = _subjects[index];
                    final collection = collectionMap[subject.id];
                    final supportsEpisodes = subject.type.hasEpisodes;
                    return SubjectTile(
                      subject: subject,
                      collection: collection,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              SubjectDetailScreen(subject: subject),
                        ),
                      ),
                      onEpisodeGrid: collection != null && supportsEpisodes
                          ? () =>
                                showEpisodeGridSheet(context, ref, collection)
                          : null,
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showFilters() async {
    var browseYear = _browseYear;
    var browseQuarter = _browseQuarter;
    var browseSort = _browseSort;
    var searchSort = _searchSort;
    var minimumRating = _minimumRating;
    var startYear = _startYear;
    final tagController = TextEditingController(text: _tag);
    final currentYear = DateTime.now().year;
    final yearChoices = [
      for (var year = currentYear + 1; year >= currentYear - 8; year--) year,
    ];
    final startYearChoices = <int>{
      0,
      currentYear,
      currentYear - 1,
      currentYear - 3,
      currentYear - 5,
      2020,
      2015,
      2010,
    }.toList()..sort((a, b) => b.compareTo(a));

    final applied = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 680),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            24,
            4,
            24,
            24 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_subjectType.label}筛选',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                _searching
                    ? '当前为搜索模式：以下条件作用于关键词搜索。'
                    : _supportsSeason
                    ? '当前为季度浏览：可按年份和季度查看排行。'
                    : '当前为年度浏览：可按年份与排序查看热门作品。',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (!_searching) ...[
                const SizedBox(height: 22),
                Text(
                  _supportsSeason ? '季度浏览' : '年度浏览',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final year in yearChoices)
                      ChoiceChip(
                        label: Text('$year'),
                        selected: browseYear == year,
                        onSelected: (_) =>
                            setSheetState(() => browseYear = year),
                      ),
                  ],
                ),
                if (_supportsSeason) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var quarter = 0; quarter < 4; quarter++)
                        ChoiceChip(
                          label: Text(_quarterLabel(quarter)),
                          selected: browseQuarter == quarter,
                          onSelected: (_) =>
                              setSheetState(() => browseQuarter = quarter),
                        ),
                    ],
                  ),
                ] else ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final sort in ['rank', 'date'])
                        ChoiceChip(
                          label: Text(_browseSortLabel(sort)),
                          selected: browseSort == sort,
                          onSelected: (_) =>
                              setSheetState(() => browseSort = sort),
                        ),
                    ],
                  ),
                ],
              ],
              if (_searching) ...[
                const SizedBox(height: 22),
                Text('搜索排序', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final sort in ['match', 'heat', 'rank', 'score'])
                      ChoiceChip(
                        label: Text(_searchSortLabel(sort)),
                        selected: searchSort == sort,
                        onSelected: (_) =>
                            setSheetState(() => searchSort = sort),
                      ),
                  ],
                ),
                const SizedBox(height: 22),
                Text(
                  '最低 Bangumi 评分',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final rating in [0, 6, 7, 8, 9])
                      ChoiceChip(
                        label: Text(rating == 0 ? '不限' : '$rating 分以上'),
                        selected: minimumRating == rating,
                        onSelected: (_) =>
                            setSheetState(() => minimumRating = rating),
                      ),
                  ],
                ),
                const SizedBox(height: 22),
                Text(
                  _yearFilterLabel,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final year in startYearChoices)
                      ChoiceChip(
                        label: Text(year == 0 ? '不限' : '$year 年后'),
                        selected: startYear == year,
                        onSelected: (_) =>
                            setSheetState(() => startYear = year),
                      ),
                  ],
                ),
                const SizedBox(height: 22),
                TextField(
                  controller: tagController,
                  decoration: InputDecoration(
                    labelText: '标签',
                    hintText: '例如：${_suggestedTags.take(2).join('、')}',
                    prefixIcon: const Icon(Icons.sell_outlined),
                    helperText: '多个标签用逗号分隔；标签过窄容易搜不到结果',
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final tag in _suggestedTags)
                      ActionChip(
                        label: Text(tag),
                        onPressed: () {
                          final current = tagController.text.trim();
                          if (current.isEmpty) {
                            tagController.text = tag;
                          } else if (!current
                              .split(RegExp(r'[,，\s]+'))
                              .contains(tag)) {
                            tagController.text = '$current，$tag';
                          }
                          setSheetState(() {});
                        },
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 28),
              Row(
                children: [
                  TextButton(
                    onPressed: () => setSheetState(() {
                      final now = DateTime.now();
                      browseYear = now.year;
                      browseQuarter = (now.month - 1) ~/ 3;
                      browseSort = 'rank';
                      searchSort = 'match';
                      minimumRating = 0;
                      startYear = 0;
                      tagController.clear();
                    }),
                    child: const Text('重置'),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: () {
                      setState(() {
                        _browseYear = browseYear;
                        _browseQuarter = browseQuarter;
                        _browseSort = browseSort;
                        _searchSort = searchSort;
                        _minimumRating = minimumRating;
                        _startYear = startYear;
                        _tag = tagController.text.trim();
                      });
                      Navigator.pop(sheetContext, true);
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
    tagController.dispose();
    if (applied == true && mounted) _runCurrentQuery();
  }

  String _quarterLabel(int quarter) => switch (quarter) {
    0 => '冬季（1月）',
    1 => '春季（4月）',
    2 => '夏季（7月）',
    _ => '秋季（10月）',
  };

  String _searchSortLabel(String sort) => switch (sort) {
    'heat' => '热度',
    'rank' => '排名',
    'score' => '评分',
    _ => '匹配度',
  };

  String _browseSortLabel(String sort) => switch (sort) {
    'date' => '最新',
    _ => '排名',
  };
}

class _EmptyDiscoverState extends StatelessWidget {
  const _EmptyDiscoverState({
    required this.searching,
    required this.subjectType,
    required this.activeFilterCount,
    required this.keyword,
    required this.onClearFilters,
    required this.onClearSearch,
    required this.onOpenFilters,
  });

  final bool searching;
  final SubjectType subjectType;
  final int activeFilterCount;
  final String keyword;
  final VoidCallback onClearFilters;
  final VoidCallback onClearSearch;
  final VoidCallback onOpenFilters;

  @override
  Widget build(BuildContext context) {
    final title = searching ? '没有找到相关${subjectType.label}' : '这里暂时没有内容';
    final message = searching
        ? activeFilterCount > 0
              ? '关键词「$keyword」在当前筛选下没有结果。可清除筛选，或换更短关键词。'
              : '关键词「$keyword」没有匹配的${subjectType.label}。试试换类型，或缩短关键词。'
        : '当前浏览条件下没有条目，试试换年份/季度，或直接搜索作品名。';

    return SizedBox(
      width: double.infinity,
      child: EmptyState(
        icon: Icons.search_off_rounded,
        title: title,
        message: message,
        action: Wrap(
          spacing: 10,
          runSpacing: 10,
          alignment: WrapAlignment.center,
          children: [
            if (searching && activeFilterCount > 0)
              FilledButton.tonalIcon(
                onPressed: onClearFilters,
                icon: const Icon(Icons.filter_alt_off_rounded),
                label: const Text('清除筛选'),
              ),
            if (searching)
              FilledButton.tonalIcon(
                onPressed: onClearSearch,
                icon: const Icon(Icons.clear_rounded),
                label: const Text('清空搜索'),
              ),
            if (!searching && activeFilterCount > 0)
              FilledButton.tonalIcon(
                onPressed: onClearFilters,
                icon: const Icon(Icons.restart_alt_rounded),
                label: const Text('重置浏览条件'),
              ),
            OutlinedButton.icon(
              onPressed: onOpenFilters,
              icon: const Icon(Icons.tune_rounded),
              label: const Text('调整筛选'),
            ),
          ],
        ),
      ),
    );
  }
}
