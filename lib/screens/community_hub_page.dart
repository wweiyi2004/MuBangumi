import 'dart:async';

import 'package:flutter/material.dart';

import '../core/network/community_service.dart';
import '../models/community_models.dart';
import '../widgets/community_widgets.dart';
import 'community_group_screen.dart';
import 'community_page.dart';
import 'community_timeline_page.dart';
import 'community_topic_screen.dart';

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
  const CommunityPage({super.key});

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

  void _openWeb() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CommunityWebScreen(
          initialUrl: _area.webUrl,
          title: '${_area.label} · Bangumi',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 620;
    final phone = MediaQuery.sizeOf(context).width < 420;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        phone ? 12 : (compact ? 14 : 20),
        phone ? 12 : 18,
        phone ? 8 : (compact ? 14 : 20),
        12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '社区',
                  style: phone
                      ? Theme.of(context).textTheme.headlineMedium
                      : Theme.of(context).textTheme.headlineLarge,
                ),
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
                const _RakuenPage(),
                _opened.contains(_CommunityArea.groups)
                    ? const _GroupBrowser()
                    : const SizedBox.shrink(),
                _opened.contains(_CommunityArea.timeline)
                    ? const CommunityTimelinePage()
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
  const _RakuenPage();

  @override
  State<_RakuenPage> createState() => _RakuenPageState();
}

class _RakuenPageState extends State<_RakuenPage> {
  final _service = CommunityService.shared;
  final _scrollController = ScrollController();
  RakuenMode _mode = RakuenMode.subjectTrending;
  List<CommunityTopic> _topics = const [];
  List<CommunityGroup> _hotGroups = const [];
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    unawaited(_loadCacheThenRefresh());
    unawaited(_loadHotGroups());
  }

  void _onScroll() {
    if (_scrollController.position.extentAfter < 500) {
      unawaited(_loadMore());
    }
  }

  Future<void> _loadCacheThenRefresh() async {
    final mode = _mode;
    final requestId = ++_requestId;
    final cached = await _service.readCachedTopics(mode);
    if (cached != null &&
        cached.data.isNotEmpty &&
        mounted &&
        requestId == _requestId) {
      setState(() {
        _topics = cached.data;
        _total = cached.total;
        _loading = false;
      });
    }
    await _load(refresh: true, requestId: requestId);
  }

  Future<void> _load({bool refresh = false, int? requestId}) async {
    final mode = _mode;
    final activeRequest = requestId ?? ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _service.loadTopicPage(mode, refresh: refresh);
      if (!mounted || activeRequest != _requestId || mode != _mode) return;
      setState(() {
        _topics = page.data;
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
    if (_loading ||
        _loadingMore ||
        _topics.isEmpty ||
        (_total > 0 && _topics.length >= _total)) {
      return;
    }
    final mode = _mode;
    final requestId = _requestId;
    setState(() => _loadingMore = true);
    try {
      final page = await _service.loadTopicPage(mode, offset: _topics.length);
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
        _total = page.total;
      });
    } catch (error) {
      if (!mounted || mode != _mode || requestId != _requestId) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _loadingMore = false);
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
      _error = null;
      _loadingMore = false;
    });
    unawaited(_loadCacheThenRefresh());
  }

  void _openTopic(CommunityTopic topic) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CommunityTopicScreen(topic: topic),
      ),
    );
  }

  void _openGroup(CommunityGroup group) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CommunityGroupScreen(group: group),
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
      _RakuenModePicker(
        mode: _mode,
        authenticated: _service.isAuthenticated,
        onChanged: _selectMode,
      ),
      const SizedBox(height: 10),
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
        await Future.wait([_load(refresh: true), _loadHotGroups()]);
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
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: _loadingMore
                    ? const CircularProgressIndicator()
                    : Text(
                        _total > 0 && _topics.length >= _total
                            ? '已经到底了'
                            : '继续向下浏览',
                      ),
              ),
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
          height: 82,
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
  const _GroupBrowser();

  @override
  State<_GroupBrowser> createState() => _GroupBrowserState();
}

class _GroupBrowserState extends State<_GroupBrowser> {
  final _service = CommunityService.shared;
  final _scrollController = ScrollController();
  CommunityGroupMode _mode = CommunityGroupMode.all;
  CommunityGroupSort _sort = CommunityGroupSort.members;
  List<CommunityGroup> _groups = const [];
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    unawaited(_loadCacheThenRefresh());
  }

  void _onScroll() {
    if (_scrollController.position.extentAfter < 500) {
      unawaited(_loadMore());
    }
  }

  Future<void> _loadCacheThenRefresh() async {
    final mode = _mode;
    final sort = _sort;
    final requestId = ++_requestId;
    final cached = await _service.readCachedGroups(mode, sort);
    if (cached != null &&
        cached.data.isNotEmpty &&
        mounted &&
        requestId == _requestId) {
      setState(() {
        _groups = cached.data;
        _total = cached.total;
        _loading = false;
      });
    }
    await _load(refresh: true, requestId: requestId);
  }

  Future<void> _load({bool refresh = false, int? requestId}) async {
    final mode = _mode;
    final sort = _sort;
    final activeRequest = requestId ?? ++_requestId;
    setState(() {
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
    if (_loading ||
        _loadingMore ||
        _groups.isEmpty ||
        (_total > 0 && _groups.length >= _total)) {
      return;
    }
    final mode = _mode;
    final sort = _sort;
    final requestId = _requestId;
    setState(() => _loadingMore = true);
    try {
      final page = await _service.loadGroupPage(
        mode: mode,
        sort: sort,
        offset: _groups.length,
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
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _changeFilter({CommunityGroupMode? mode, CommunityGroupSort? sort}) {
    setState(() {
      _mode = mode ?? _mode;
      _sort = sort ?? _sort;
      _groups = const [];
      _total = 0;
      _error = null;
      _loadingMore = false;
    });
    unawaited(_loadCacheThenRefresh());
  }

  void _openGroup(CommunityGroup group) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CommunityGroupScreen(group: group),
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
        ],
      ),
      const SizedBox(height: 11),
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
            mainAxisExtent: 82,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemCount: _groups.length + 1,
          itemBuilder: (context, index) {
            if (index == _groups.length) {
              if (_groups.isEmpty) return const Center(child: Text('暂时没有小组'));
              return Center(
                child: _loadingMore
                    ? const CircularProgressIndicator()
                    : Text(
                        _total > 0 && _groups.length >= _total
                            ? '已经到底了'
                            : '继续向下浏览',
                      ),
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
