import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/layout/app_layout.dart';
import '../core/network/bangumi_endpoints.dart';
import '../core/network/bangumi_meta_tags.dart';
import '../core/network/bangumi_support.dart';
import '../core/storage/snapshot_cache.dart';
import '../models/bangumi_models.dart';
import '../state/session_controller.dart';
import '../widgets/episode_grid_sheet.dart';
import '../widgets/subject_widgets.dart';
import 'character_detail_screen.dart';
import 'person_detail_screen.dart';
import 'score_trends_page.dart';
import 'subject_detail_screen.dart';

enum DiscoverSearchTarget { subject, character, person }

const discoverEarliestAnimeYear = 1906;
const _discoverEarliestOtherYear = 1900;

enum DiscoverQueryMode {
  browse,
  subjectSearch,
  characterPrompt,
  characterSearch,
  personPrompt,
  personSearch,
}

DiscoverQueryMode resolveDiscoverQueryMode({
  required DiscoverSearchTarget target,
  required String keyword,
  required String tag,
  List<String> metaTags = const [],
}) {
  final hasKeyword = keyword.trim().isNotEmpty;
  return switch (target) {
    DiscoverSearchTarget.subject =>
      hasKeyword || tag.trim().isNotEmpty || metaTags.isNotEmpty
          ? DiscoverQueryMode.subjectSearch
          : DiscoverQueryMode.browse,
    DiscoverSearchTarget.character =>
      hasKeyword
          ? DiscoverQueryMode.characterSearch
          : DiscoverQueryMode.characterPrompt,
    DiscoverSearchTarget.person =>
      hasKeyword
          ? DiscoverQueryMode.personSearch
          : DiscoverQueryMode.personPrompt,
  };
}

final discoverCollectionsProvider = Provider<List<UserCollection>>(
  (ref) => ref.watch(sessionProvider.select((state) => state.collections)),
);

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
        body: DiscoverPage(initialTag: value, initialSubjectType: subjectType),
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
  bool _loading = false;

  /// Background refresh while keeping previous list visible (stale-while-revalidate).
  bool _refreshing = false;
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
  List<String> _metaTags = const [];
  DiscoverSearchTarget _searchTarget = DiscoverSearchTarget.subject;
  List<CharacterDetail> _characters = const [];
  List<PersonDetail> _persons = const [];

  DiscoverQueryMode get _queryMode => resolveDiscoverQueryMode(
    target: _searchTarget,
    keyword: _searchController.text,
    tag: _tag,
    metaTags: _metaTags,
  );

  bool get _searching => switch (_queryMode) {
    DiscoverQueryMode.subjectSearch ||
    DiscoverQueryMode.characterSearch ||
    DiscoverQueryMode.personSearch => true,
    _ => false,
  };
  bool get _searchingSubjects => _queryMode == DiscoverQueryMode.subjectSearch;
  bool get _searchingCharacters =>
      _queryMode == DiscoverQueryMode.characterSearch;
  bool get _searchingPersons => _queryMode == DiscoverQueryMode.personSearch;

  /// TV-like seasonal browse (year + quarter).
  bool get _supportsSeason =>
      _subjectType == SubjectType.anime || _subjectType == SubjectType.real;

  int get _earliestDiscoverYear => _subjectType == SubjectType.anime
      ? discoverEarliestAnimeYear
      : _discoverEarliestOtherYear;

  String get _yearFilterLabel => switch (_subjectType) {
    SubjectType.book => '最早出版年份',
    SubjectType.music => '最早发售年份',
    SubjectType.game => '最早发售年份',
    SubjectType.real => '最早播出年份',
    SubjectType.anime => '最早播出年份',
  };

  List<String> get _suggestedTags => switch (_subjectType) {
    SubjectType.anime => const ['科幻', '日常', '治愈', '战斗', '恋爱'],
    SubjectType.book => const ['轻小说', '科幻'],
    SubjectType.music => const ['OP', 'ED', 'OST', '角色歌'],
    SubjectType.game => const ['Galgame', 'RPG', 'ACT'],
    SubjectType.real => const ['推理', '爱情'],
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
    if (_searchTarget != DiscoverSearchTarget.subject) return 0;
    var count = 0;
    if (_searchingSubjects) {
      if (_searchSort != 'match') count++;
      if (_minimumRating > 0) count++;
      if (_startYear > 0) count++;
      if (_tag.trim().isNotEmpty) count++;
      if (_metaTags.isNotEmpty) count += _metaTags.length;
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
    _scrollController.addListener(_onScroll);
    Future.microtask(() {
      unawaited(_startCurrentQuery());
    });
  }

  String get _browseCacheKey => SnapshotCache.discoverBrowseKey(
    type: _subjectType,
    year: _browseYear,
    quarter: _browseQuarter,
    sort: _browseSort,
    supportsSeason: _supportsSeason,
  );

  int _lastSuccessfulBrowseRequest = -1;

  Future<void> _hydrateBrowseCacheIfNeeded(int requestId) async {
    if (_queryMode != DiscoverQueryMode.browse) return;
    final key = _browseCacheKey;
    try {
      final cached = await ref
          .read(snapshotCacheProvider)
          .readDiscoverBrowse(key);
      if (!mounted || cached == null || cached.isEmpty) return;
      if (_browseCacheKey != key) return;
      if (_queryMode != DiscoverQueryMode.browse ||
          requestId != _requestId ||
          _lastSuccessfulBrowseRequest == requestId) {
        return;
      }
      final refreshing = _loading || _refreshing;
      setState(() {
        _subjects = cached;
        _offset = cached.length;
        _hasMore = cached.length >= _pageSize;
        _loading = false;
        _refreshing = refreshing;
        _error = null;
      });
    } catch (_) {
      // Disk cache is best-effort.
    }
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
    if (!_hasMore || _loading || _refreshing || _loadingMore) return;
    if (_scrollController.position.extentAfter < 480) {
      unawaited(_loadMore());
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _requestId++;
    final nextMode = resolveDiscoverQueryMode(
      target: _searchTarget,
      keyword: value,
      tag: _tag,
    );
    setState(() {
      _error = null;
      _offset = 0;
      _hasMore = false;
      _loadingMore = false;
      // Keep previous results visible; only full-spinner when nothing to show.
      final empty = switch (_searchTarget) {
        DiscoverSearchTarget.subject => _subjects.isEmpty,
        DiscoverSearchTarget.character => _characters.isEmpty,
        DiscoverSearchTarget.person => _persons.isEmpty,
      };
      _loading = switch (nextMode) {
        DiscoverQueryMode.characterPrompt ||
        DiscoverQueryMode.personPrompt => false,
        _ => empty,
      };
      _refreshing = switch (nextMode) {
        DiscoverQueryMode.characterPrompt ||
        DiscoverQueryMode.personPrompt => false,
        _ => !empty,
      };
    });
    _debounce = Timer(const Duration(milliseconds: 450), _startCurrentQuery);
  }

  Future<void> _startCurrentQuery() async {
    _runCurrentQuery();
    if (_queryMode == DiscoverQueryMode.browse) {
      unawaited(_hydrateBrowseCacheIfNeeded(_requestId));
    }
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
      _metaTags = const [];
      _browseSort = 'rank';
      final now = DateTime.now();
      _browseYear = now.year;
      _browseQuarter = (now.month - 1) ~/ 3;
      _error = null;
      _subjects = const [];
      _loading = false;
    });
    unawaited(_startCurrentQuery());
  }

  void _clearSearchFilters() {
    setState(() {
      _resetSearchFilters();
    });
  }

  void _resetSearchFilters() {
    _searchSort = 'match';
    _minimumRating = 0;
    _startYear = 0;
    _tag = '';
    _metaTags = const [];
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchController.clear();
    setState(_resetSearchFilters);
    unawaited(_startCurrentQuery());
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
    switch (_queryMode) {
      case DiscoverQueryMode.subjectSearch:
        unawaited(_search(keyword));
      case DiscoverQueryMode.characterSearch:
        unawaited(_searchCharacters(keyword));
      case DiscoverQueryMode.personSearch:
        unawaited(_searchPersons(keyword));
      case DiscoverQueryMode.browse:
        setState(() {
          _characters = const [];
          _persons = const [];
        });
        unawaited(_loadBrowse());
      case DiscoverQueryMode.characterPrompt:
        _showSearchPrompt(DiscoverSearchTarget.character);
      case DiscoverQueryMode.personPrompt:
        _showSearchPrompt(DiscoverSearchTarget.person);
    }
  }

  void _showSearchPrompt(DiscoverSearchTarget target) {
    _requestId++;
    setState(() {
      _loading = false;
      _refreshing = false;
      _loadingMore = false;
      _hasMore = false;
      _offset = 0;
      _error = null;
      _subjects = const [];
      _characters = const [];
      _persons = const [];
    });
  }

  Future<void> _searchCharacters(String keyword, {bool append = false}) async {
    final requestId = append ? _requestId : ++_requestId;
    final offset = append ? _offset : 0;
    setState(() {
      if (append) {
        _loadingMore = true;
      } else {
        final empty = _characters.isEmpty;
        _loading = empty;
        _refreshing = !empty;
        _error = null;
        if (empty) {
          _offset = 0;
          _hasMore = true;
        }
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
        _refreshing = false;
        _loadingMore = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _loading = false;
        _refreshing = false;
        _loadingMore = false;
        if (!append && _characters.isEmpty) {
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
        final empty = _persons.isEmpty;
        _loading = empty;
        _refreshing = !empty;
        _error = null;
        if (empty) {
          _offset = 0;
          _hasMore = true;
        }
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
        _refreshing = false;
        _loadingMore = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _loading = false;
        _refreshing = false;
        _loadingMore = false;
        if (!append && _persons.isEmpty) {
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
        final empty = _subjects.isEmpty;
        _loading = empty;
        _refreshing = !empty;
        _error = null;
        if (empty) {
          _offset = 0;
          _hasMore = true;
        }
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
        _refreshing = false;
        _loadingMore = false;
        _error = null;
      });
      _lastSuccessfulBrowseRequest = requestId;
      if (!append) {
        unawaited(
          ref
              .read(snapshotCacheProvider)
              .writeDiscoverBrowse(_browseCacheKey, subjects)
              .catchError((Object _) {}),
        );
      }
    } catch (error) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _loading = false;
        _refreshing = false;
        _loadingMore = false;
        // Keep stale list; only surface error when there is nothing to show.
        if (!append && _subjects.isEmpty) {
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
        final empty = _subjects.isEmpty;
        _loading = empty;
        _refreshing = !empty;
        _error = null;
        if (empty) {
          _offset = 0;
          _hasMore = true;
        }
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
            metaTags: _metaTags,
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
        _refreshing = false;
        _loadingMore = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _loading = false;
        _refreshing = false;
        _loadingMore = false;
        if (!append && _subjects.isEmpty) {
          _error = error.toString().replaceFirst('Exception: ', '');
        }
      });
    }
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _loadingMore || _loading || _refreshing) return;
    final keyword = _searchController.text.trim();
    switch (_queryMode) {
      case DiscoverQueryMode.subjectSearch:
        await _search(keyword, append: true);
      case DiscoverQueryMode.characterSearch:
        await _searchCharacters(keyword, append: true);
      case DiscoverQueryMode.personSearch:
        await _searchPersons(keyword, append: true);
      case DiscoverQueryMode.browse:
        await _loadBrowse(append: true);
      case DiscoverQueryMode.characterPrompt:
      case DiscoverQueryMode.personPrompt:
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final collections = ref.watch(discoverCollectionsProvider);
    final collectionMap = {
      for (final item in collections) item.subjectId: item,
    };
    final phone = AppLayout.isPhone(context);
    final pagePad = AppLayout.pagePadding(context);
    return CustomScrollView(
      controller: _scrollController,
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
                child: _buildDiscoverHeader(context, phone),
              ),
            ),
          ),
        ),
        ..._buildResultSlivers(context, collectionMap, pagePad),
        SliverToBoxAdapter(child: SizedBox(height: phone ? 36 : 60)),
      ],
    );
  }

  Widget _buildDiscoverHeader(BuildContext context, bool phone) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('发现', style: AppLayout.pageTitleStyle(context)),
      SizedBox(height: AppLayout.sectionGap(context)),
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
                        onPressed: _clearSearch,
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
            child: phone
                ? IconButton(
                    tooltip: '筛选',
                    onPressed: _searchTarget == DiscoverSearchTarget.subject
                        ? _showFilters
                        : null,
                    icon: const Icon(Icons.tune_rounded),
                  )
                : OutlinedButton.icon(
                    onPressed: _searchTarget == DiscoverSearchTarget.subject
                        ? _showFilters
                        : null,
                    icon: const Icon(Icons.tune_rounded),
                    label: const Text('筛选'),
                  ),
          ),
        ],
      ),
      const SizedBox(height: 12),
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
      if (_queryMode == DiscoverQueryMode.browse) ...[
        const SizedBox(height: 12),
        Material(
          color: Colors.transparent,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(
              Icons.ssid_chart_rounded,
              color: Color(0xFFF3A646),
            ),
            title: const Text(
              '评分趋势',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              phone ? '涨跌榜 · 口碑提升 · netaba.re' : '涨跌榜 · 口碑提升 · 历史曲线（netaba.re）',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ScoreTrendsPage()),
            ),
          ),
        ),
      ],
      const SizedBox(height: 18),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(switch (_queryMode) {
            DiscoverQueryMode.characterPrompt ||
            DiscoverQueryMode.characterSearch => '角色搜索',
            DiscoverQueryMode.personPrompt ||
            DiscoverQueryMode.personSearch => '人物搜索',
            DiscoverQueryMode.subjectSearch => '${_subjectType.label}搜索结果',
            DiscoverQueryMode.browse =>
              _supportsSeason
                  ? '${_subjectType.label}季度榜'
                  : '${_subjectType.label}年度榜',
          }, style: Theme.of(context).textTheme.titleLarge),
          if (!_searching && _supportsSeason)
            Chip(
              label: Text('$_browseYear · ${_quarterLabel(_browseQuarter)}'),
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
          if (_searchingSubjects && _metaTags.isNotEmpty)
            Chip(label: Text(_metaTags.join(' · '))),
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
    ],
  );

  List<Widget> _buildResultSlivers(
    BuildContext context,
    Map<int, UserCollection> collectionMap,
    double pagePad,
  ) {
    Widget box(Widget child) => SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: pagePad),
      sliver: SliverToBoxAdapter(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1220),
            child: child,
          ),
        ),
      ),
    );

    if (_loading) {
      return [
        box(
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 100),
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
      ];
    }
    if (_error != null &&
        _subjects.isEmpty &&
        _characters.isEmpty &&
        _persons.isEmpty) {
      return [
        box(
          EmptyState(
            icon: Icons.cloud_off_outlined,
            title: '没有连接上 Bangumi',
            message: _error!,
            action: FilledButton.tonalIcon(
              onPressed: _runCurrentQuery,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重试'),
            ),
          ),
        ),
      ];
    }
    // Subtle top indicator while refreshing over stale content.
    final refreshingBar = _refreshing
        ? [
            box(
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: LinearProgressIndicator(minHeight: 2),
              ),
            ),
          ]
        : const <Widget>[];
    if (_queryMode == DiscoverQueryMode.characterPrompt) {
      return [box(const _SearchPrompt(target: DiscoverSearchTarget.character))];
    }
    if (_queryMode == DiscoverQueryMode.personPrompt) {
      return [box(const _SearchPrompt(target: DiscoverSearchTarget.person))];
    }
    if (_searchingCharacters && _characters.isEmpty) {
      return [
        box(
          _EmptyDiscoverState(
            searching: true,
            resultLabel: '角色',
            activeFilterCount: 0,
            keyword: _searchController.text.trim(),
            onClearFilters: () {},
            onClearSearch: _clearSearch,
            onOpenFilters: () {},
          ),
        ),
      ];
    }
    if (_searchingPersons && _persons.isEmpty) {
      return [
        box(
          _EmptyDiscoverState(
            searching: true,
            resultLabel: '人物',
            activeFilterCount: 0,
            keyword: _searchController.text.trim(),
            onClearFilters: () {},
            onClearSearch: _clearSearch,
            onOpenFilters: () {},
          ),
        ),
      ];
    }
    if (!_searchingCharacters && !_searchingPersons && _subjects.isEmpty) {
      return [
        box(
          _EmptyDiscoverState(
            searching: _searching,
            resultLabel: _subjectType.label,
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
            onClearSearch: _clearSearch,
            onOpenFilters: _showFilters,
          ),
        ),
      ];
    }

    if (_searchingCharacters || _searchingPersons) {
      final itemCount = _searchingCharacters
          ? _characters.length
          : _persons.length;
      return [
        ...refreshingBar,
        _centeredLazySliver(
          pagePad: pagePad,
          itemCount: itemCount,
          childBuilder: (context, index) {
            if (_searchingCharacters) {
              final character = _characters[index];
              return ListTile(
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
              );
            }
            final person = _persons[index];
            final kind = switch (person.type) {
              2 => '公司',
              3 => '团体',
              _ => '',
            };
            final personMeta = [if (kind.isNotEmpty) kind, ...person.career];
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: _DiscoverMonoThumb(
                url: person.imageUrl,
                round: person.type != 2,
              ),
              title: Text(person.displayName),
              subtitle: personMeta.isEmpty
                  ? (person.name != person.displayName
                        ? Text(person.name)
                        : null)
                  : Text(personMeta.join(' / ')),
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
            );
          },
        ),
        if (_hasMore) box(_buildLoadMore()),
      ];
    }

    return [
      ...refreshingBar,
      SliverPadding(
        padding: EdgeInsets.symmetric(horizontal: pagePad),
        sliver: SliverLayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.crossAxisExtent;
            final contentWidth = width > 1220 ? 1220.0 : width;
            final side = (width - contentWidth) / 2;
            const spacing = 12.0;
            final columns = subjectPosterColumnCount(contentWidth);
            return SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: side),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisExtent: subjectPosterItemHeight(
                    contentWidth,
                    columns,
                    spacing: spacing,
                    textScaler: MediaQuery.textScalerOf(context),
                  ),
                  mainAxisSpacing: spacing,
                  crossAxisSpacing: spacing,
                ),
                delegate: SliverChildBuilderDelegate((context, index) {
                  final subject = _subjects[index];
                  final collection = collectionMap[subject.id];
                  final supportsEpisodes = subject.type.hasEpisodes;
                  return SubjectPosterCard(
                    subject: subject,
                    collection: collection,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => SubjectDetailScreen(subject: subject),
                      ),
                    ),
                    onEpisodeGrid: collection != null && supportsEpisodes
                        ? () => showEpisodeGridSheet(context, ref, collection)
                        : null,
                  );
                }, childCount: _subjects.length),
              ),
            );
          },
        ),
      ),
      if (_hasMore) box(_buildLoadMore()),
    ];
  }

  Widget _centeredLazySliver({
    required double pagePad,
    required IndexedWidgetBuilder childBuilder,
    required int itemCount,
  }) => SliverPadding(
    padding: EdgeInsets.symmetric(horizontal: pagePad),
    sliver: SliverLayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.crossAxisExtent;
        final contentWidth = width > 1220 ? 1220.0 : width;
        return SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: (width - contentWidth) / 2),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              childBuilder,
              childCount: itemCount,
              addAutomaticKeepAlives: false,
              addRepaintBoundaries: true,
            ),
          ),
        );
      },
    ),
  );

  Widget _buildLoadMore() => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Center(
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
  );

  Future<void> _showFilters() async {
    var browseYear = _browseYear;
    var browseQuarter = _browseQuarter;
    var browseSort = _browseSort;
    var searchSort = _searchSort;
    var minimumRating = _minimumRating;
    var startYear = _startYear;
    var metaTags = List<String>.from(_metaTags);
    final tagController = TextEditingController(text: _tag);
    final browseYearController = TextEditingController(text: '$browseYear');
    final startYearController = TextEditingController(
      text: startYear == 0 ? '' : '$startYear',
    );
    final currentYear = DateTime.now().year;
    final latestBrowseYear = currentYear + 1;
    final earliestYear = _earliestDiscoverYear;
    String? browseYearError;
    String? startYearError;
    final yearChoices = [
      for (var year = latestBrowseYear; year >= currentYear - 8; year--) year,
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
    Animation<double>? sheetAnimation;

    final applied = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 680),
      builder: (sheetContext) {
        sheetAnimation ??= ModalRoute.of(sheetContext)?.animation;
        return StatefulBuilder(
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
                      ? '当前为搜索模式：官方标签与下列条件作用于关键词搜索。'
                      : _supportsSeason
                      ? '当前为季度浏览：可按年份和季度查看排行。选中官方标签后会改为搜索。'
                      : '当前为年度浏览：可按年份与排序查看热门作品。选中官方标签后会改为搜索。',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 22),
                Text('官方标签', style: Theme.of(context).textTheme.titleMedium),
                for (final group in BangumiMetaTags.groupsFor(
                  _subjectType,
                )) ...[
                  const SizedBox(height: 10),
                  Text(
                    group.label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final tag in group.tags)
                        ChoiceChip(
                          label: Text(tag),
                          selected: metaTags.contains(tag),
                          onSelected: (selected) => setSheetState(() {
                            metaTags = [
                              for (final item in metaTags)
                                if (!group.tags.contains(item)) item,
                            ];
                            if (selected) metaTags = [...metaTags, tag];
                          }),
                        ),
                    ],
                  ),
                ],
                if (!_searching) ...[
                  const SizedBox(height: 22),
                  Text(
                    _supportsSeason ? '季度浏览' : '年度浏览',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    key: const ValueKey('discover-browse-year-input'),
                    controller: browseYearController,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(4),
                    ],
                    onChanged: (value) => setSheetState(() {
                      browseYearError = _discoverYearInputError(
                        value,
                        minimum: earliestYear,
                        maximum: latestBrowseYear,
                      );
                      if (browseYearError == null) {
                        browseYear = int.parse(value);
                      }
                    }),
                    decoration: InputDecoration(
                      labelText: '年份',
                      hintText: '$currentYear',
                      prefixIcon: const Icon(Icons.calendar_today_outlined),
                      suffixText: '年',
                      helperText: '可输入 $earliestYear—$latestBrowseYear',
                      errorText: browseYearError,
                    ),
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
                          onSelected: (_) => setSheetState(() {
                            browseYear = year;
                            browseYearController.text = '$year';
                            browseYearError = null;
                          }),
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
                  TextField(
                    key: const ValueKey('discover-start-year-input'),
                    controller: startYearController,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(4),
                    ],
                    onChanged: (value) => setSheetState(() {
                      startYearError = _discoverYearInputError(
                        value,
                        minimum: earliestYear,
                        maximum: currentYear,
                        optional: true,
                      );
                      if (startYearError == null) {
                        startYear = value.trim().isEmpty ? 0 : int.parse(value);
                      }
                    }),
                    decoration: InputDecoration(
                      labelText: _yearFilterLabel,
                      hintText: '留空表示不限',
                      prefixIcon: const Icon(Icons.calendar_today_outlined),
                      suffixText: '年',
                      helperText: '可输入 $earliestYear—$currentYear，留空不限',
                      errorText: startYearError,
                    ),
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
                          onSelected: (_) => setSheetState(() {
                            startYear = year;
                            startYearController.text = year == 0 ? '' : '$year';
                            startYearError = null;
                          }),
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
                        browseYearController.text = '${now.year}';
                        browseYearError = null;
                        browseQuarter = (now.month - 1) ~/ 3;
                        browseSort = 'rank';
                        searchSort = 'match';
                        minimumRating = 0;
                        startYear = 0;
                        startYearController.clear();
                        startYearError = null;
                        metaTags = [];
                        tagController.clear();
                      }),
                      child: const Text('重置'),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed:
                          browseYearError != null || startYearError != null
                          ? null
                          : () {
                              setState(() {
                                _browseYear = browseYear;
                                _browseQuarter = browseQuarter;
                                _browseSort = browseSort;
                                _searchSort = searchSort;
                                _minimumRating = minimumRating;
                                _startYear = startYear;
                                _metaTags = List<String>.from(metaTags);
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
        );
      },
    );
    await _waitForDismissed(sheetAnimation);
    tagController.dispose();
    browseYearController.dispose();
    startYearController.dispose();
    if (applied == true && mounted) {
      setState(() {
        _subjects = const [];
        _loading = false;
      });
      unawaited(_startCurrentQuery());
    }
  }

  String? _discoverYearInputError(
    String value, {
    required int minimum,
    required int maximum,
    bool optional = false,
  }) {
    final normalized = value.trim();
    if (normalized.isEmpty) return optional ? null : '请输入年份';
    final year = int.tryParse(normalized);
    if (year == null || year < minimum || year > maximum) {
      return '请输入 $minimum—$maximum 年';
    }
    return null;
  }

  Future<void> _waitForDismissed(Animation<double>? animation) async {
    if (animation == null || animation.status == AnimationStatus.dismissed) {
      return;
    }
    final completer = Completer<void>();
    void listener(AnimationStatus status) {
      if (status != AnimationStatus.dismissed || completer.isCompleted) return;
      animation.removeStatusListener(listener);
      completer.complete();
    }

    animation.addStatusListener(listener);
    if (animation.status == AnimationStatus.dismissed) {
      listener(animation.status);
    }
    await completer.future;
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
    required this.resultLabel,
    required this.activeFilterCount,
    required this.keyword,
    required this.onClearFilters,
    required this.onClearSearch,
    required this.onOpenFilters,
  });

  final bool searching;
  final String resultLabel;
  final int activeFilterCount;
  final String keyword;
  final VoidCallback onClearFilters;
  final VoidCallback onClearSearch;
  final VoidCallback onOpenFilters;

  @override
  Widget build(BuildContext context) {
    final title = searching ? '没有找到相关$resultLabel' : '这里暂时没有内容';
    final message = searching
        ? activeFilterCount > 0
              ? keyword.isEmpty
                    ? '当前标签与筛选条件没有结果。可清除筛选后重试。'
                    : '关键词「$keyword」在当前筛选下没有结果。可清除筛选，或换更短关键词。'
              : '关键词「$keyword」没有匹配的$resultLabel。试试换类型，或缩短关键词。'
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

class _SearchPrompt extends StatelessWidget {
  const _SearchPrompt({required this.target});

  final DiscoverSearchTarget target;

  @override
  Widget build(BuildContext context) {
    final label = target == DiscoverSearchTarget.character ? '角色' : '人物';
    final example = target == DiscoverSearchTarget.character ? '鲁路修' : '福山润';
    return SizedBox(
      width: double.infinity,
      child: EmptyState(
        icon: target == DiscoverSearchTarget.character
            ? Icons.face_retouching_natural_rounded
            : Icons.person_search_rounded,
        title: '输入$label名开始搜索',
        message: '例如：$example。这里不会混入条目季度榜。',
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
        : CachedNetworkImage(
            imageUrl: BangumiEndpoints.imageUrl(
              url,
              size: BangumiImageSize.grid,
            ),
            fit: BoxFit.cover,
            fadeInDuration: Duration.zero,
            fadeOutDuration: Duration.zero,
            memCacheWidth: 88,
            memCacheHeight: 120,
            errorWidget: (_, _, _) => ColoredBox(
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
