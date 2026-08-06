import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/bangumi_endpoints.dart';
import '../core/network/bangumi_support.dart';
import '../models/bangumi_models.dart';
import '../state/session_controller.dart';
import '../widgets/episode_grid_sheet.dart';
import '../widgets/subject_widgets.dart';
import 'character_detail_screen.dart';
import 'person_detail_screen.dart';
import 'subject_detail_screen.dart';

enum DiscoverSearchTarget { subject, character, person }

/// Opens a standalone discover surface pre-filtered by [tag].
void openDiscoverTagSearch(
  BuildContext context, {
  required String tag,
  SubjectType subjectType = SubjectType.anime,
}) {
  final value = tag.trim();
  if (value.isEmpty) return;
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text('标签 · $value')),
        body: DiscoverPage(
          initialTag: value,
          initialSubjectType: subjectType,
        ),
      ),
    ),
  );
}

class DiscoverPage extends ConsumerStatefulWidget {
  const DiscoverPage({
    super.key,
    this.initialTag = '',
    this.initialSubjectType,
  });

  final String initialTag;
  final SubjectType? initialSubjectType;

  @override
  ConsumerState<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends ConsumerState<DiscoverPage> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _debounce;
  List<Subject> _subjects = const [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;
  int _requestId = 0;
  int _offset = 0;
  static const _pageSize = 24;

  late SubjectType _subjectType;
  late int _browseYear;
  late int _browseQuarter; // anime/real only
  String _browseSort = 'rank'; // date | rank for non-season browse
  String _searchSort = 'match';
  int _minimumRating = 0;
  int _startYear = 0;
  late String _tag;
  DiscoverSearchTarget _searchTarget = DiscoverSearchTarget.subject;
  List<CharacterDetail> _characters = const [];
  List<PersonDetail> _persons = const [];

  bool get _searching => _searchController.text.trim().isNotEmpty;
  bool get _searchingSubjects =>
      _searching && _searchTarget == DiscoverSearchTarget.subject;
  bool get _searchingCharacters =>
      _searching && _searchTarget == DiscoverSearchTarget.character;
  bool get _searchingPersons =>
      _searching && _searchTarget == DiscoverSearchTarget.person;

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

  String get _searchHint => switch (_searchTarget) {
    DiscoverSearchTarget.character => '搜索角色，例如：鲁路修',
    DiscoverSearchTarget.person => '搜索人物，例如：福山润',
    DiscoverSearchTarget.subject => switch (_subjectType) {
      SubjectType.anime => '搜索动画，例如：迷宫饭',
      SubjectType.book => '搜索书籍，例如：葬送的芙莉莲',
      SubjectType.music => '搜索音乐，例如：YOASOBI',
      SubjectType.game => '搜索游戏，例如：艾尔登法环',
      SubjectType.real => '搜索三次元，例如：孤独的美食家',
    },
  };

  int get _activeFilterCount {
    var count = 0;
    if (_searchingSubjects) {
      if (_searchSort != 'match') count++;
      if (_minimumRating > 0) count++;
      if (_startYear > 0) count++;
      if (_tag.trim().isNotEmpty) count++;
    } else if (_searching) {
      // Character/person search has no extra filters yet.
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
    _subjectType = widget.initialSubjectType ?? SubjectType.anime;
    _tag = widget.initialTag.trim();
    if (_tag.isNotEmpty) {
      // Tag deep-link: use the tag as keyword so search path applies filters.
      _searchController.text = _tag;
    }
    _scrollController.addListener(_onScroll);
    Future.microtask(_runCurrentQuery);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _loading || _loadingMore) return;
    if (_scrollController.position.extentAfter < 480) {
      unawaited(_loadMore());
    }
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
      switch (_searchTarget) {
        case DiscoverSearchTarget.subject:
          unawaited(_search(keyword));
        case DiscoverSearchTarget.character:
          unawaited(_searchCharacters(keyword));
        case DiscoverSearchTarget.person:
          unawaited(_searchPersons(keyword));
      }
      return;
    }
    setState(() {
      _characters = const [];
      _persons = const [];
    });
    unawaited(_loadBrowse());
  }

  Future<void> _searchCharacters(String keyword, {bool append = false}) async {
    final requestId = append ? _requestId : ++_requestId;
    final offset = append ? _offset : 0;
    setState(() {
      if (append) {
        _loadingMore = true;
      } else {
        _loading = true;
        _error = null;
        _offset = 0;
        _hasMore = true;
        _subjects = const [];
        _persons = const [];
      }
    });
    try {
      final items = await ref
          .read(bangumiApiProvider)
          .searchCharacters(keyword, limit: _pageSize, offset: offset);
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _characters = append ? [..._characters, ...items] : items;
        _offset = offset + items.length;
        _hasMore = items.length >= _pageSize;
        _loading = false;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        if (!append) {
          _error = error.toString().replaceFirst('Exception: ', '');
        }
      });
    }
  }

  Future<void> _searchPersons(String keyword, {bool append = false}) async {
    final requestId = append ? _requestId : ++_requestId;
    final offset = append ? _offset : 0;
    setState(() {
      if (append) {
        _loadingMore = true;
      } else {
        _loading = true;
        _error = null;
        _offset = 0;
        _hasMore = true;
        _subjects = const [];
        _characters = const [];
      }
    });
    try {
      final items = await ref
          .read(bangumiApiProvider)
          .searchPersons(keyword, limit: _pageSize, offset: offset);
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _persons = append ? [..._persons, ...items] : items;
        _offset = offset + items.length;
        _hasMore = items.length >= _pageSize;
        _loading = false;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        if (!append) {
          _error = error.toString().replaceFirst('Exception: ', '');
        }
      });
    }
  }

  Future<void> _loadBrowse({bool append = false}) async {
    final requestId = append ? _requestId : ++_requestId;
    final offset = append ? _offset : 0;
    setState(() {
      if (append) {
        _loadingMore = true;
      } else {
        _loading = true;
        _error = null;
        _offset = 0;
        _hasMore = true;
      }
    });
    try {
      final api = ref.read(bangumiApiProvider);
      final subjects = _supportsSeason
          ? await api.browseSubjects(
              type: _subjectType,
              year: _browseYear,
              month: _browseQuarter * 3 + 1,
              sort: 'rank',
              limit: _pageSize,
              offset: offset,
            )
          : await api.browseSubjects(
              type: _subjectType,
              year: _browseYear,
              sort: _browseSort,
              limit: _pageSize,
              offset: offset,
            );
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _subjects = append ? [..._subjects, ...subjects] : subjects;
        _offset = offset + subjects.length;
        _hasMore = subjects.length >= _pageSize;
        _loading = false;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        if (!append) {
          _error = error.toString().replaceFirst('Exception: ', '');
        }
      });
    }
  }

  Future<void> _search(String keyword, {bool append = false}) async {
    final requestId = append ? _requestId : ++_requestId;
    final offset = append ? _offset : 0;
    setState(() {
      if (append) {
        _loadingMore = true;
      } else {
        _loading = true;
        _error = null;
        _offset = 0;
        _hasMore = true;
        _characters = const [];
        _persons = const [];
      }
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
            limit: _pageSize,
            offset: offset,
          );
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _subjects = append ? [..._subjects, ...subjects] : subjects;
        _offset = offset + subjects.length;
        _hasMore = subjects.length >= _pageSize;
        _loading = false;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        if (!append) {
          _error = error.toString().replaceFirst('Exception: ', '');
        }
      });
    }
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _loadingMore || _loading) return;
    final keyword = _searchController.text.trim();
    if (keyword.isNotEmpty) {
      switch (_searchTarget) {
        case DiscoverSearchTarget.subject:
          await _search(keyword, append: true);
        case DiscoverSearchTarget.character:
          await _searchCharacters(keyword, append: true);
        case DiscoverSearchTarget.person:
          await _searchPersons(keyword, append: true);
      }
    } else {
      await _loadBrowse(append: true);
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
      controller: _scrollController,
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
                switch (_searchTarget) {
                  DiscoverSearchTarget.character => '搜索角色 · 点进角色详情',
                  DiscoverSearchTarget.person => '搜索人物 · 点进人物详情',
                  DiscoverSearchTarget.subject =>
                    '按类型浏览与搜索 · 当前：${_subjectType.label}',
                },
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
                      onPressed: _searchTarget == DiscoverSearchTarget.subject
                          ? _showFilters
                          : null,
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
                    for (final target in DiscoverSearchTarget.values) ...[
                      ChoiceChip(
                        label: Text(switch (target) {
                          DiscoverSearchTarget.subject => '条目',
                          DiscoverSearchTarget.character => '角色',
                          DiscoverSearchTarget.person => '人物',
                        }),
                        selected: _searchTarget == target,
                        onSelected: (_) {
                          if (_searchTarget == target) return;
                          setState(() {
                            _searchTarget = target;
                            _error = null;
                          });
                          _runCurrentQuery();
                        },
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
              if (_searchTarget == DiscoverSearchTarget.subject) ...[
                const SizedBox(height: 12),
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
              ],
              const SizedBox(height: 18),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    _searchingCharacters
                        ? '角色搜索结果'
                        : _searchingPersons
                        ? '人物搜索结果'
                        : _searchingSubjects
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
                  if (_searchingSubjects && _searchSort != 'match')
                    Chip(label: Text(_searchSortLabel(_searchSort))),
                  if (_searchingSubjects && _minimumRating > 0)
                    Chip(label: Text('评分 ≥ $_minimumRating')),
                  if (_searchingSubjects && _startYear > 0)
                    Chip(label: Text('$_startYear 年后')),
                  if (_searchingSubjects && _tag.trim().isNotEmpty)
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
              else if (_searchingCharacters && _characters.isEmpty)
                _EmptyDiscoverState(
                  searching: true,
                  subjectType: _subjectType,
                  activeFilterCount: 0,
                  keyword: _searchController.text.trim(),
                  onClearFilters: () {},
                  onClearSearch: () {
                    _searchController.clear();
                    setState(() {});
                    _runCurrentQuery();
                  },
                  onOpenFilters: () {},
                )
              else if (_searchingPersons && _persons.isEmpty)
                _EmptyDiscoverState(
                  searching: true,
                  subjectType: _subjectType,
                  activeFilterCount: 0,
                  keyword: _searchController.text.trim(),
                  onClearFilters: () {},
                  onClearSearch: () {
                    _searchController.clear();
                    setState(() {});
                    _runCurrentQuery();
                  },
                  onOpenFilters: () {},
                )
              else if (!_searchingCharacters &&
                  !_searchingPersons &&
                  _subjects.isEmpty)
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
              else ...[
                if (_searchingCharacters)
                  for (final character in _characters)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: _DiscoverMonoThumb(url: character.imageUrl),
                      title: Text(character.displayName),
                      subtitle: character.name != character.displayName
                          ? Text(character.name)
                          : null,
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => CharacterDetailScreen(
                            characterId: character.id,
                            seedName: character.displayName,
                            seedImageUrl: character.imageUrl,
                          ),
                        ),
                      ),
                    )
                else if (_searchingPersons)
                  for (final person in _persons)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: _DiscoverMonoThumb(
                        url: person.imageUrl,
                        round: true,
                      ),
                      title: Text(person.displayName),
                      subtitle: person.career.isEmpty
                          ? (person.name != person.displayName
                                ? Text(person.name)
                                : null)
                          : Text(person.career.join(' / ')),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => PersonDetailScreen(
                            personId: person.id,
                            seedName: person.displayName,
                            seedImageUrl: person.imageUrl,
                          ),
                        ),
                      ),
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
                            ? () => showEpisodeGridSheet(
                                  context,
                                  ref,
                                  collection,
                                )
                            : null,
                      );
                    },
                  ),
                if (_hasMore) ...[
                  const SizedBox(height: 16),
                  Center(
                    child: _loadingMore
                        ? const SizedBox.square(
                            dimension: 28,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : TextButton.icon(
                            onPressed: _loadMore,
                            icon: const Icon(Icons.expand_more_rounded),
                            label: const Text('加载更多'),
                          ),
                  ),
                ],
              ],
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
            if (!searching || activeFilterCount > 0)
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

class _DiscoverMonoThumb extends StatelessWidget {
  const _DiscoverMonoThumb({required this.url, this.round = false});

  final String url;
  final bool round;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final child = url.isEmpty
        ? ColoredBox(
            color: scheme.surfaceContainerHighest,
            child: Icon(
              round ? Icons.person_rounded : Icons.face_rounded,
              size: 20,
            ),
          )
        : Image.network(
            BangumiEndpoints.imageUrl(url),
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => ColoredBox(
              color: scheme.surfaceContainerHighest,
              child: const Icon(Icons.broken_image_outlined, size: 18),
            ),
          );
    if (round) {
      return CircleAvatar(
        radius: 22,
        backgroundColor: scheme.surfaceContainerHighest,
        child: ClipOval(child: SizedBox(width: 44, height: 44, child: child)),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(width: 44, height: 60, child: child),
    );
  }
}
