import 'dart:async';

import 'package:flutter/material.dart';

import '../core/layout/app_layout.dart';

import '../core/network/community_service.dart';
import '../models/community_models.dart';
import '../widgets/community_widgets.dart';
import '../widgets/community_loading.dart';
import 'community_group_screen.dart';
import 'community_timeline_page.dart';
import 'community_topic_screen.dart';
import 'website_login_screen.dart';

enum _CommunityArea {
  rakuen('超展开', Icons.forum_outlined, 'https://bgm.tv/rakuen'),
  groups('小组', Icons.groups_outlined, 'https://bgm.tv/group'),
  timeline('时光机', Icons.dynamic_feed_outlined, 'https://bgm.tv/timeline');

  const _CommunityArea(this.label, this.icon, this.webUrl);

  final String label;
  final IconData icon;
  final String webUrl;
}

class CommunityPage extends StatefulWidget {
  const CommunityPage({super.key, this.service});
  final CommunityService? service;

  @override
  State<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends State<CommunityPage> {
  _CommunityArea _area = _CommunityArea.rakuen;
  final Set<_CommunityArea> _opened = {_CommunityArea.rakuen};

  void _selectArea(_CommunityArea area) {
    setState(() {
      _area = area;
      _opened.add(area);
    });
  }

  Future<void> _openWeb() async {
    await openSeededCommunityWeb(
      context,
      initialUrl: _area.webUrl,
      title: '${_area.label} · Bangumi',
    );
  }

  @override
  Widget build(BuildContext context) {
    final phone = AppLayout.isPhone(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppLayout.pagePadding(context),
        AppLayout.pageTopPadding(context),
        AppLayout.pagePadding(context),
        12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('社区', style: AppLayout.pageTitleStyle(context)),
              ),
              IconButton(
                visualDensity: phone
                    ? VisualDensity.compact
                    : VisualDensity.standard,
                tooltip: '在 Bangumi 网页查看',
                onPressed: _openWeb,
                icon: const Icon(Icons.language_rounded),
              ),
            ],
          ),
          SizedBox(height: phone ? 10 : 13),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<_CommunityArea>(
              segments: [
                for (final area in _CommunityArea.values)
                  ButtonSegment(
                    value: area,
                    icon: Icon(area.icon, size: 19),
                    label: Text(area.label),
                  ),
              ],
              selected: {_area},
              onSelectionChanged: (value) => _selectArea(value.first),
              showSelectedIcon: false,
            ),
          ),
          const SizedBox(height: 13),
          Expanded(
            child: IndexedStack(
              index: _area.index,
              children: [
                _RakuenPage(service: widget.service),
                _opened.contains(_CommunityArea.groups)
                    ? _GroupBrowser(service: widget.service)
                    : const SizedBox.shrink(),
                _opened.contains(_CommunityArea.timeline)
                    ? CommunityTimelinePage(service: widget.service)
                    : const SizedBox.shrink(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RakuenPage extends StatefulWidget {
  const _RakuenPage({this.service});
  final CommunityService? service;

  @override
  State<_RakuenPage> createState() => _RakuenPageState();
}

class _RakuenPageState extends State<_RakuenPage> {
  late final _service = widget.service ?? CommunityService.shared;
  final _scrollController = ScrollController();
  RakuenMode _mode = RakuenMode.subjectTrending;
  List<CommunityTopic> _topics = const [];
  List<CommunityGroup> _hotGroups = const [];
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  int _requestId = 0;
  int _lastSuccessfulRequest = -1;
  int _nextOffset = 0;
  bool _hasMore = true;
  String? _loadMoreError;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    unawaited(_loadCacheThenRefresh());
    unawaited(_loadHotGroups());
  }

  void _onScroll() {
    if (_loadMoreError == null &&
        _scrollController.position.extentAfter < 500) {
      unawaited(_loadMore());
    }
  }

  Future<void> _loadCacheThenRefresh() async {
    final requestId = ++_requestId;
    final network = _load(requestId: requestId);
    Future<void> restore() async {
      try {
        final cached = await _service.readCachedTopics(_mode);
        if (!mounted ||
            requestId != _requestId ||
            _lastSuccessfulRequest == requestId ||
            cached == null ||
            cached.data.isEmpty) {
          return;
        }
        setState(() {
          _topics = cached.data;
          _total = cached.total;
          _nextOffset = cached.data.length;
          _hasMore = _total > 0
              ? _nextOffset < _total
              : cached.data.length >= 20;
        });
      } catch (_) {
        // Optional disk reads never block the network request.
      }
    }

    unawaited(restore());
    await network;
  }

  Future<void> _load({bool refresh = false, int? requestId}) async {
    final mode = _mode;
    final activeRequest = requestId ?? ++_requestId;
    if (!mounted || activeRequest != _requestId) return;
    setState(() {
      _loadingMore = false;
      _loadMoreError = null;
      _loading = true;
      _error = null;
    });
    try {
      final page = await _service.loadTopicPage(mode, refresh: refresh);
      if (!mounted || activeRequest != _requestId || mode != _mode) return;
      setState(() {
        _topics = page.data;
        _lastSuccessfulRequest = activeRequest;
        _nextOffset = page.data.length;
        _hasMore =
            page.data.isNotEmpty &&
            (page.total > 0
                ? _nextOffset < page.total
                : page.data.length >= 20);
        _total = page.total;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || activeRequest != _requestId || mode != _mode) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || _topics.isEmpty || !_hasMore) {
      return;
    }
    final mode = _mode;
    final requestId = _requestId;
    setState(() {
      _loadingMore = true;
      _loadMoreError = null;
    });
    try {
      final page = await _service.loadTopicPage(mode, offset: _nextOffset);
      if (!mounted || mode != _mode || requestId != _requestId) return;
      final known = _topics
          .map((topic) => '${topic.kind.name}:${topic.id}')
          .toSet();
      setState(() {
        _topics = [
          ..._topics,
          ...page.data.where(
            (topic) => known.add('${topic.kind.name}:${topic.id}'),
          ),
        ];
        _nextOffset += page.data.length;
        _hasMore =
            page.data.isNotEmpty &&
            (page.total > 0
                ? _nextOffset < page.total
                : page.data.length >= 20);
        _total = page.total;
      });
    } catch (error) {
      if (!mounted || mode != _mode || requestId != _requestId) return;
      setState(() {
        _loadMoreError = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted && requestId == _requestId) {
        setState(() => _loadingMore = false);
      }
    }
  }

  Future<void> _loadHotGroups() async {
    try {
      final cached = await _service.readCachedGroups(
        CommunityGroupMode.all,
        CommunityGroupSort.members,
      );
      if (cached != null && cached.data.isNotEmpty && mounted) {
        setState(() => _hotGroups = cached.data.take(10).toList());
      }
      final page = await _service.loadGroupPage(limit: 10, refresh: true);
      if (mounted) setState(() => _hotGroups = page.data);
    } catch (_) {
      // Hot groups are secondary content; topic loading remains usable.
    }
  }

  void _selectMode(RakuenMode mode) {
    if (_mode == mode) return;
    setState(() {
      _mode = mode;
      _topics = const [];
      _total = 0;
      _hasMore = true;
      _nextOffset = 0;
      _loadMoreError = null;
      _error = null;
      _loadingMore = false;
    });
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
    unawaited(_loadCacheThenRefresh());
  }

  void _openTopic(CommunityTopic topic) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CommunityTopicScreen(topic: topic, service: _service),
      ),
    );
  }

  void _openGroup(CommunityGroup group) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CommunityGroupScreen(group: group, service: _service),
      ),
    );
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: _RakuenModePicker(
              mode: _mode,
              authenticated: _service.isAuthenticated,
              onChanged: _selectMode,
            ),
          ),
          IconButton(
            tooltip: '刷新话题',
            onPressed: _loading ? null : () => _load(refresh: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      const SizedBox(height: 10),
      if (_topics.isNotEmpty)
        CommunityRefreshStatus(
          loading: _loading,
          error: _error,
          onRetry: () => _load(refresh: true),
        ),
      Expanded(child: _buildBody()),
    ],
  );

  Widget _buildBody() {
    if (_loading && _topics.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _topics.isEmpty) {
      return CommunityErrorView(
        message: _error!,
        onRetry: () => _load(refresh: true),
      );
    }
    return RefreshIndicator(
      onRefresh: () async {
        unawaited(_loadHotGroups());
        await _load(refresh: true);
      },
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 26),
        itemCount: _topics.length + 2,
        itemBuilder: (context, index) {
          if (index == 0) {
            if (_hotGroups.isEmpty || !_mode.isSubject) {
              return const SizedBox.shrink();
            }
            return _HotGroups(groups: _hotGroups, onTap: _openGroup);
          }
          if (index == _topics.length + 1) {
            if (_topics.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(36),
                child: Center(child: Text('暂时没有话题')),
              );
            }
            return CommunityLoadMoreFooter(
              loading: _loadingMore,
              hasMore: _hasMore,
              error: _loadMoreError,
              onLoad: _loading ? null : () => _loadMore(),
            );
          }
          final topic = _topics[index - 1];
          return CommunityTopicCard(
            topic: topic,
            onTap: () => _openTopic(topic),
          );
        },
      ),
    );
  }
}

class _RakuenModePicker extends StatelessWidget {
  const _RakuenModePicker({
    required this.mode,
    required this.authenticated,
    required this.onChanged,
  });

  final RakuenMode mode;
  final bool authenticated;
  final ValueChanged<RakuenMode> onChanged;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        for (var index = 0; index < RakuenMode.values.length; index++) ...[
          if (index == 0 ||
              RakuenMode.values[index - 1].isSubject !=
                  RakuenMode.values[index].isSubject) ...[
            if (index > 0) const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Text(
                RakuenMode.values[index].categoryLabel,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
          ],
          ChoiceChip(
            label: Text(RakuenMode.values[index].label),
            selected: mode == RakuenMode.values[index],
            onSelected: !RakuenMode.values[index].requiresLogin || authenticated
                ? (_) => onChanged(RakuenMode.values[index])
                : null,
          ),
          const SizedBox(width: 7),
        ],
      ],
    ),
  );
}

class _HotGroups extends StatelessWidget {
  const _HotGroups({required this.groups, required this.onTap});

  final List<CommunityGroup> groups;
  final ValueChanged<CommunityGroup> onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 15),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 4, 9),
          child: Text(
            '热门小组',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        SizedBox(
          height: communityGroupCardHeight(context),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: groups.length,
            separatorBuilder: (_, _) => const SizedBox(width: 9),
            itemBuilder: (context, index) {
              final group = groups[index];
              return SizedBox(
                width: 300,
                child: CommunityGroupCard(
                  group: group,
                  onTap: () => onTap(group),
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
}

class _GroupBrowser extends StatefulWidget {
  const _GroupBrowser({this.service});
  final CommunityService? service;

  @override
  State<_GroupBrowser> createState() => _GroupBrowserState();
}

class _GroupBrowserState extends State<_GroupBrowser> {
  late final _service = widget.service ?? CommunityService.shared;
  final _scrollController = ScrollController();
  CommunityGroupMode _mode = CommunityGroupMode.all;
  CommunityGroupSort _sort = CommunityGroupSort.members;
  List<CommunityGroup> _groups = const [];
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  int _requestId = 0;
  int _lastSuccessfulRequest = -1;
  int _nextOffset = 0;
  bool _hasMore = true;
  String? _loadMoreError;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    unawaited(_loadCacheThenRefresh());
  }

  void _onScroll() {
    if (_loadMoreError == null &&
        _scrollController.position.extentAfter < 500) {
      unawaited(_loadMore());
    }
  }

  Future<void> _loadCacheThenRefresh() async {
    final requestId = ++_requestId;
    final network = _load(requestId: requestId);
    Future<void> restore() async {
      try {
        final cached = await _service.readCachedGroups(_mode, _sort);
        if (!mounted ||
            requestId != _requestId ||
            _lastSuccessfulRequest == requestId ||
            cached == null ||
            cached.data.isEmpty) {
          return;
        }
        setState(() {
          _groups = cached.data;
          _total = cached.total;
          _nextOffset = cached.data.length;
          _hasMore = _total > 0
              ? _nextOffset < _total
              : cached.data.length >= 20;
        });
      } catch (_) {
        // Optional disk reads never block the network request.
      }
    }

    unawaited(restore());
    await network;
  }

  Future<void> _load({bool refresh = false, int? requestId}) async {
    final mode = _mode;
    final sort = _sort;
    final activeRequest = requestId ?? ++_requestId;
    if (!mounted || activeRequest != _requestId) return;
    setState(() {
      _loadingMore = false;
      _loadMoreError = null;
      _loading = true;
      _error = null;
    });
    try {
      final page = await _service.loadGroupPage(
        mode: mode,
        sort: sort,
        refresh: refresh,
      );
      if (!mounted ||
          activeRequest != _requestId ||
          mode != _mode ||
          sort != _sort) {
        return;
      }
      setState(() {
        _groups = page.data;
        _lastSuccessfulRequest = activeRequest;
        _nextOffset = page.data.length;
        _hasMore =
            page.data.isNotEmpty &&
            (page.total > 0
                ? _nextOffset < page.total
                : page.data.length >= 20);
        _total = page.total;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || activeRequest != _requestId) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || _groups.isEmpty || !_hasMore) {
      return;
    }
    final mode = _mode;
    final sort = _sort;
    final requestId = _requestId;
    setState(() {
      _loadingMore = true;
      _loadMoreError = null;
    });
    try {
      final page = await _service.loadGroupPage(
        mode: mode,
        sort: sort,
        offset: _nextOffset,
      );
      if (!mounted ||
          mode != _mode ||
          sort != _sort ||
          requestId != _requestId) {
        return;
      }
      final known = _groups.map((group) => group.slug).toSet();
      setState(() {
        _groups = [
          ..._groups,
          ...page.data.where((group) => known.add(group.slug)),
        ];
        _nextOffset += page.data.length;
        _hasMore =
            page.data.isNotEmpty &&
            (page.total > 0
                ? _nextOffset < page.total
                : page.data.length >= 20);
        _total = page.total;
      });
    } catch (error) {
      if (!mounted ||
          mode != _mode ||
          sort != _sort ||
          requestId != _requestId) {
        return;
      }
      setState(() {
        _loadMoreError = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted && requestId == _requestId) {
        setState(() => _loadingMore = false);
      }
    }
  }

  void _changeFilter({CommunityGroupMode? mode, CommunityGroupSort? sort}) {
    setState(() {
      _mode = mode ?? _mode;
      _sort = sort ?? _sort;
      _groups = const [];
      _total = 0;
      _hasMore = true;
      _nextOffset = 0;
      _loadMoreError = null;
      _error = null;
      _loadingMore = false;
    });
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
    unawaited(_loadCacheThenRefresh());
  }

  void _openGroup(CommunityGroup group) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CommunityGroupScreen(group: group, service: _service),
      ),
    );
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final mode in CommunityGroupMode.values) ...[
                    ChoiceChip(
                      label: Text(mode.label),
                      selected: _mode == mode,
                      onSelected:
                          !mode.requiresLogin || _service.isAuthenticated
                          ? (_) => _changeFilter(mode: mode)
                          : null,
                    ),
                    const SizedBox(width: 7),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<CommunityGroupSort>(
            tooltip: '排序',
            initialValue: _sort,
            onSelected: (sort) => _changeFilter(sort: sort),
            itemBuilder: (context) => [
              for (final sort in CommunityGroupSort.values)
                PopupMenuItem(value: sort, child: Text(sort.label)),
            ],
            child: Chip(
              avatar: const Icon(Icons.sort_rounded, size: 18),
              label: Text(_sort.label),
            ),
          ),
          IconButton(
            tooltip: '刷新小组',
            onPressed: _loading ? null : () => _load(refresh: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      const SizedBox(height: 11),
      if (_groups.isNotEmpty)
        CommunityRefreshStatus(
          loading: _loading,
          error: _error,
          onRetry: () => _load(refresh: true),
        ),
      Expanded(child: _buildBody()),
    ],
  );

  Widget _buildBody() {
    if (_loading && _groups.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _groups.isEmpty) {
      return CommunityErrorView(
        message: _error!,
        onRetry: () => _load(refresh: true),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _load(refresh: true),
      child: LayoutBuilder(
        builder: (context, constraints) => GridView.builder(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 28),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: constraints.maxWidth >= 1050
                ? 3
                : constraints.maxWidth >= 660
                ? 2
                : 1,
            mainAxisExtent: communityGroupCardHeight(context),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemCount: _groups.length + 1,
          itemBuilder: (context, index) {
            if (index == _groups.length) {
              if (_groups.isEmpty) return const Center(child: Text('暂时没有小组'));
              return CommunityLoadMoreFooter(
                loading: _loadingMore,
                hasMore: _hasMore,
                error: _loadMoreError,
                onLoad: _loading ? null : () => _loadMore(),
              );
            }
            final group = _groups[index];
            return CommunityGroupCard(
              group: group,
              onTap: () => _openGroup(group),
            );
          },
        ),
      ),
    );
  }
}
