import '../features/discover/application/discover_controller.dart';
import '../features/discover/domain/discover_query.dart';
import '../features/discover/presentation/discover_result_widgets.dart';
export '../features/discover/domain/discover_query.dart';
import '../navigation/app_destination.dart';
export '../navigation/app_destination.dart' show openDiscoverTagSearch;
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/layout/app_layout.dart';
import '../core/network/bangumi_support.dart';
import '../core/storage/browsing_store.dart';
import '../models/bangumi_models.dart';
import '../models/subject_search_filter.dart';
import '../state/session_controller.dart';
import '../widgets/episode_grid_sheet.dart';
import '../widgets/subject_widgets.dart';
import '../widgets/recent_searches.dart';
import '../widgets/discover_filters_sheet.dart';

final discoverCollectionsProvider = Provider<List<UserCollection>>(
  (ref) => ref.watch(sessionProvider.select((state) => state.collections)),
);

class DiscoverPage extends ConsumerStatefulWidget {
  const DiscoverPage({
    super.key,
    this.initialTag = '',
    this.initialSubjectType,
    this.showTitle = true,
  });

  final bool showTitle;
  final String initialTag;
  final SubjectType? initialSubjectType;

  @override
  ConsumerState<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends ConsumerState<DiscoverPage> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _debounce;
  late final DiscoverController _results;
  List<Subject> get _subjects => _results.subjects;
  List<CharacterDetail> get _characters => _results.characters;
  List<PersonDetail> get _persons => _results.persons;
  bool get _loading => _results.loading;
  bool get _refreshing => _results.refreshing;
  bool get _loadingMore => _results.loadingMore;
  bool get _hasMore => _results.hasMore;
  String? get _error => _results.error;
  String? get _pageError => _results.pageError;

  late SubjectType _subjectType;
  late int _browseYear;
  late int _browseQuarter; // anime/real only
  String _browseSort = 'rank'; // date | rank for non-season browse
  String _searchSort = 'match';
  double _minimumRating = 0;
  bool _ratingExclusive = false;
  int _startYear = 0;
  int _endYear = 0;
  bool _hideCollected = false;
  bool _filterSearch = false;
  late String _tag;
  List<String> _metaTags = const [];
  DiscoverSearchTarget _searchTarget = DiscoverSearchTarget.subject;

  DiscoverQueryMode get _queryMode => resolveDiscoverQueryMode(
    target: _searchTarget,
    keyword: _searchController.text,
    tag: _tag,
    metaTags: _metaTags,
    filterSearch: _filterSearch,
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
      : discoverEarliestOtherYear;

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
      if (_minimumRating > 0 || _ratingExclusive) count++;
      if (_startYear > 0 || _endYear > 0) count++;
      if (_hideCollected) count++;
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
    _results = DiscoverController(
      api: ref.read(bangumiApiProvider),
      cache: ref.read(snapshotCacheProvider),
      query: _query,
      onChanged: () {
        if (mounted) setState(() {});
      },
    );
    _scrollController.addListener(_onScroll);
    Future.microtask(() {
      unawaited(_startCurrentQuery());
    });
  }

  DiscoverQuery get _query => DiscoverQuery(
    target: _searchTarget,
    keyword: _searchController.text.trim(),
    tag: _tag,
    metaTags: _metaTags,
    filterSearch: _filterSearch,
    subjectType: _subjectType,
    browseYear: _browseYear,
    browseQuarter: _browseQuarter,
    browseSort: _browseSort,
    searchSort: _searchSort,
    minimumRating: _minimumRating,
    ratingExclusive: _ratingExclusive,
    startYear: _startYear,
    endYear: _endYear,
  );

  @override
  void dispose() {
    _debounce?.cancel();
    _results.dispose();
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
    _results.prepareSearch(_query);
    _debounce = Timer(const Duration(milliseconds: 450), _startCurrentQuery);
  }

  Future<void> _startCurrentQuery() {
    _debounce?.cancel();
    return _results.start(_query);
  }

  void _selectSubjectType(SubjectType type) {
    if (_subjectType == type) return;
    setState(() {
      _subjectType = type;
      // Reset filters that often break cross-type search.
      _resetSearchFilters();
      _browseSort = 'rank';
      final now = DateTime.now();
      _browseYear = now.year;
      _browseQuarter = (now.month - 1) ~/ 3;
      _results.clearError();
      _results.clearSubjects();
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
    _ratingExclusive = false;
    _startYear = 0;
    _endYear = 0;
    _hideCollected = false;
    _filterSearch = false;
    _tag = '';
    _metaTags = const [];
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchController.clear();
    setState(_resetSearchFilters);
    unawaited(_startCurrentQuery());
  }

  Future<void> _rememberCurrentSearch() async {
    final account = ref.read(sessionProvider).user?.username;
    final keyword = _searchController.text.trim();
    if (account == null || account.isEmpty || keyword.isEmpty) return;
    final search = RecentSearch(
      keyword: keyword,
      target: _searchTarget.name,
      subjectType: _subjectType,
    );
    try {
      await ref
          .read(browsingRepositoryProvider)
          .rememberSearch(account, search);
      if (mounted) ref.invalidate(recentSearchesProvider(account));
    } catch (_) {
      // History is optional; an unavailable local store cannot block search.
    }
  }

  void _selectRecentSearch(RecentSearch search) {
    _debounce?.cancel();
    setState(() {
      _searchTarget = DiscoverSearchTarget.values.firstWhere(
        (target) => target.name == search.target,
      );
      _subjectType = search.subjectType;
      _searchController.text = search.keyword;
      _searchController.selection = TextSelection.collapsed(
        offset: search.keyword.length,
      );
      _resetSearchFilters();
    });
    unawaited(_rememberCurrentSearch());
    _runCurrentQuery();
  }

  void _openSearchResult(Widget page) {
    unawaited(_rememberCurrentSearch());
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  void _clearBrowseFilters() {
    final now = DateTime.now();
    setState(() {
      _browseYear = now.year;
      _browseQuarter = (now.month - 1) ~/ 3;
      _browseSort = 'rank';
    });
  }

  void _runCurrentQuery() => unawaited(_startCurrentQuery());
  Future<void> _loadMore() => _results.loadMore();

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
      if (widget.showTitle)
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
                unawaited(_rememberCurrentSearch());
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
      if (_searchController.text.trim().isEmpty && _tag.isEmpty)
        Consumer(
          builder: (context, ref, _) {
            final account = ref.watch(
              sessionProvider.select((state) => state.user?.username),
            );
            return account == null || account.isEmpty
                ? const SizedBox.shrink()
                : RecentSearches(
                    key: ValueKey(account),
                    account: account,
                    onSelected: (search) {
                      if (ref.read(sessionProvider).user?.username == account) {
                        _selectRecentSearch(search);
                      }
                    },
                  );
          },
        ),
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
                    _results.clearError();
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
              MaterialPageRoute<void>(builder: (_) => const ScoreTrendsRoute()),
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
          if (_searchingSubjects && (_minimumRating > 0 || _ratingExclusive))
            Chip(
              label: Text(
                '评分 ${_ratingExclusive ? '>' : '≥'} ${_minimumRating.toStringAsFixed(1)}',
              ),
            ),
          if (_searchingSubjects && (_startYear > 0 || _endYear > 0))
            Chip(
              label: Text(
                _startYear > 0 && _endYear > 0
                    ? '$_startYear–$_endYear 年（含）'
                    : _startYear > 0
                    ? '$_startYear 年及以后'
                    : '$_endYear 年及以前',
              ),
            ),
          if (_searchingSubjects && _hideCollected)
            const Chip(label: Text('隐藏已收藏')),
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
    final numericFilter = SubjectSearchFilter(
      minimumRating: _minimumRating,
      ratingExclusive: _ratingExclusive,
      startYear: _startYear,
      endYear: _endYear,
    );
    final visibleSubjects = _searchingSubjects
        ? _subjects
              .where(
                (subject) =>
                    numericFilter.permits(subject) &&
                    (!_hideCollected || !collectionMap.containsKey(subject.id)),
              )
              .toList()
        : _subjects;
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
      return [
        box(const DiscoverSearchPrompt(target: DiscoverSearchTarget.character)),
      ];
    }
    if (_queryMode == DiscoverQueryMode.personPrompt) {
      return [
        box(const DiscoverSearchPrompt(target: DiscoverSearchTarget.person)),
      ];
    }
    if (_searchingCharacters && _characters.isEmpty) {
      return [
        box(
          EmptyDiscoverState(
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
          EmptyDiscoverState(
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
    if (!_searchingCharacters &&
        !_searchingPersons &&
        visibleSubjects.isEmpty) {
      return [
        ...refreshingBar,
        if (_hasMore && _subjects.isNotEmpty)
          box(
            EmptyState(
              icon: Icons.filter_alt_outlined,
              title: '当前已加载条目均被筛除',
              message: '后续页面可能还有符合条件的作品，可以继续加载或调整筛选。',
              action: OutlinedButton.icon(
                onPressed: _showFilters,
                icon: const Icon(Icons.tune_rounded),
                label: const Text('调整筛选'),
              ),
            ),
          )
        else
          box(
            EmptyDiscoverState(
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
        if (_hasMore) box(_buildLoadMore()),
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
                leading: DiscoverMonoThumb(url: character.imageUrl),
                title: Text(character.displayName),
                subtitle: character.name != character.displayName
                    ? Text(character.name)
                    : null,
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _openSearchResult(
                  CharacterRoute(
                    characterId: character.id,
                    seedName: character.displayName,
                    seedImageUrl: character.imageUrl,
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
              leading: DiscoverMonoThumb(
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
              onTap: () => _openSearchResult(
                PersonRoute(
                  personId: person.id,
                  seedName: person.displayName,
                  seedImageUrl: person.imageUrl,
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
                  final subject = visibleSubjects[index];
                  final collection = collectionMap[subject.id];
                  final supportsEpisodes = subject.type.hasEpisodes;
                  return SubjectPosterCard(
                    subject: subject,
                    collection: collection,
                    onTap: () =>
                        _openSearchResult(SubjectRoute(subject: subject)),
                    onEpisodeGrid: collection != null && supportsEpisodes
                        ? () => showEpisodeGridSheet(context, ref, collection)
                        : null,
                  );
                }, childCount: visibleSubjects.length),
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
    child: Column(
      children: [
        if (_pageError != null)
          Text(
            _pageError!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        Center(
          child: _loadingMore
              ? const SizedBox.square(
                  dimension: 28,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : TextButton.icon(
                  onPressed: _refreshing || _loading ? null : _loadMore,
                  icon: const Icon(Icons.expand_more_rounded),
                  label: Text(_pageError == null ? '加载更多' : '重试加载'),
                ),
        ),
      ],
    ),
  );

  Future<void> _showFilters() async {
    final type = _subjectType;
    final result = await showModalBottomSheet<DiscoverFilters>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 680),
      builder: (_) => DiscoverFiltersSheet(
        subjectType: type,
        earliestYear: _earliestDiscoverYear,
        hasKeyword: _searchController.text.trim().isNotEmpty,
        initial: DiscoverFilters(
          browseYear: _browseYear,
          browseQuarter: _browseQuarter,
          browseSort: _browseSort,
          searchMode: _searchingSubjects,
          searchSort: _searchSort,
          minimumRating: _minimumRating,
          ratingExclusive: _ratingExclusive,
          startYear: _startYear,
          endYear: _endYear,
          hideCollected: _hideCollected,
          metaTags: _metaTags,
          tag: _tag,
        ),
      ),
    );
    if (!mounted || result == null || type != _subjectType) return;
    setState(() {
      _browseYear = result.browseYear;
      _browseQuarter = result.browseQuarter;
      _browseSort = result.browseSort;
      _filterSearch = result.searchMode;
      _searchSort = result.searchSort;
      _minimumRating = result.minimumRating;
      _ratingExclusive = result.ratingExclusive;
      _startYear = result.startYear;
      _endYear = result.endYear;
      _hideCollected = result.hideCollected;
      _metaTags = result.metaTags;
      _tag = result.tag;
      _results.clearSubjects();
    });
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
    unawaited(_startCurrentQuery());
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
