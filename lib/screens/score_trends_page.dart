import 'dart:async';
import 'package:flutter/material.dart';
import '../widgets/readable_subject_title.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/network/netaba_api.dart';
import '../models/bangumi_models.dart';
import '../models/netaba_models.dart';
import '../state/session_controller.dart';
import '../widgets/insight_widgets.dart';
import '../widgets/score_history_chart.dart';
import '../widgets/subject_widgets.dart';
import 'subject_detail_screen.dart';

enum _TrendKind {
  up('涨分', '近期涨分', '近期', Icons.trending_up_rounded),
  down('跌分', '近期跌分', '近期', Icons.trending_down_rounded),
  done('完结波动', '完结之后，口碑如何变化', '近期', Icons.done_all_rounded),
  reputation('长期提升', '慢慢积累的好口碑', '开播以来', Icons.auto_awesome_rounded);

  const _TrendKind(this.label, this.title, this.period, this.icon);
  final String label;
  final String title;
  final String period;
  final IconData icon;
}

class ScoreTrendsPage extends ConsumerStatefulWidget {
  const ScoreTrendsPage({super.key});
  @override
  ConsumerState<ScoreTrendsPage> createState() => _ScoreTrendsPageState();
}

class _ScoreTrendsPageState extends ConsumerState<ScoreTrendsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  bool _loadingTrends = true;
  bool _loadingReputation = true;
  bool _onlyMine = false;
  String? _trendsError;
  String? _reputationError;
  NetabaTrending? _trending;
  List<NetabaTrendingItem> _reputation = const [];
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    unawaited(Future<void>.microtask(_load));
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load({bool refresh = false}) async {
    if (!mounted) return;
    final requestId = ++_requestId;
    final api = ref.read(netabaApiProvider);
    if (refresh) api.clearCache();
    setState(() {
      _loadingTrends = true;
      _loadingReputation = true;
      _trendsError = null;
      _reputationError = null;
    });
    Future<void> trends() async {
      try {
        final data = await api.getTrending();
        if (!mounted || requestId != _requestId) return;
        setState(() {
          _trending = data;
          _loadingTrends = false;
        });
      } catch (_) {
        if (!mounted || requestId != _requestId) return;
        setState(() {
          _trendsError = '榜单暂时加载失败';
          _loadingTrends = false;
        });
      }
    }

    Future<void> reputation() async {
      try {
        final data = await api.getScoreIncreases();
        if (!mounted || requestId != _requestId) return;
        setState(() {
          _reputation = data;
          _loadingReputation = false;
        });
      } catch (_) {
        if (!mounted || requestId != _requestId) return;
        setState(() {
          _reputationError = '长期提升榜暂时加载失败';
          _loadingReputation = false;
        });
      }
    }

    await Future.wait([trends(), reputation()]);
  }

  void _openSubject(NetabaTrendingItem item, UserCollection? mine) {
    final subject =
        mine?.subject ??
        Subject(
          id: item.bgmId,
          name: item.name,
          nameCn: item.nameCn,
          imageUrl: '',
          summary: '',
          episodeCount: 0,
          score: item.latestScore,
          rank: item.latestRank,
          date: '',
        );
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SubjectDetailScreen(subject: subject),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final mine = {for (final item in session.collections) item.subjectId: item};
    final loading = _loadingTrends || _loadingReputation;
    return Scaffold(
      appBar: AppBar(
        title: const Text('评分趋势'),
        actions: [
          IconButton(
            tooltip: '刷新榜单',
            onPressed: loading ? null : () => _load(refresh: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: '数据来源 · netaba.re',
            onPressed: () => launchUrl(
              Uri.parse('https://netaba.re/trending'),
              mode: LaunchMode.externalApplication,
            ),
            icon: const Icon(Icons.open_in_new_rounded),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [for (final kind in _TrendKind.values) Tab(text: kind.label)],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ChoiceChip(
                      label: const Text('全部作品'),
                      selected: !_onlyMine,
                      onSelected: (_) => setState(() => _onlyMine = false),
                    ),
                    ChoiceChip(
                      avatar: const Icon(
                        Icons.bookmark_border_rounded,
                        size: 17,
                      ),
                      label: const Text('我的收藏'),
                      selected: _onlyMine,
                      onSelected: (_) => setState(() => _onlyMine = true),
                    ),
                    if (session.isLoadingCollections) const Text('收藏同步中…'),
                  ],
                ),
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  for (final kind in _TrendKind.values)
                    _TrendList(
                      kind: kind,
                      source: switch (kind) {
                        _TrendKind.up => _trending?.up ?? const [],
                        _TrendKind.down => _trending?.down ?? const [],
                        _TrendKind.done => _trending?.done ?? const [],
                        _TrendKind.reputation => _reputation,
                      },
                      loading: kind == _TrendKind.reputation
                          ? _loadingReputation
                          : _loadingTrends,
                      error: kind == _TrendKind.reputation
                          ? _reputationError
                          : _trendsError,
                      onlyMine: _onlyMine,
                      mine: mine,
                      onRefresh: () => _load(refresh: true),
                      onTap: (item) => _openSubject(item, mine[item.bgmId]),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrendList extends StatelessWidget {
  const _TrendList({
    required this.kind,
    required this.source,
    required this.loading,
    required this.error,
    required this.onlyMine,
    required this.mine,
    required this.onRefresh,
    required this.onTap,
  });
  final _TrendKind kind;
  final List<NetabaTrendingItem> source;
  final bool loading;
  final String? error;
  final bool onlyMine;
  final Map<int, UserCollection> mine;
  final Future<void> Function() onRefresh;
  final ValueChanged<NetabaTrendingItem> onTap;

  @override
  Widget build(BuildContext context) {
    final visible = [
      for (var i = 0; i < source.length; i++)
        if (!onlyMine || mine.containsKey(source[i].bgmId))
          (rank: i + 1, item: source[i]),
    ];
    final owned = source.where((item) => mine.containsKey(item.bgmId)).length;
    NetabaTrendingItem? largest;
    for (final row in visible) {
      if (largest == null ||
          row.item.scoreDelta.abs() > largest.scoreDelta.abs()) {
        largest = row.item;
      }
    }
    final lead = largest;
    final description = lead == null
        ? '看看作品的评分，如何随时间发生变化。'
        : '${lead.displayName}在这份榜单中的变动最大：${lead.scoreDelta >= 0 ? '+' : ''}${lead.scoreDelta.toStringAsFixed(2)} 分。';
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1040),
        child: RefreshIndicator(
          onRefresh: onRefresh,
          child: ListView.builder(
            key: PageStorageKey('trends:${kind.name}:$onlyMine'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 36),
            itemCount: visible.length + 2,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    InsightHero(
                      label: '${kind.period}评分变化',
                      title: kind.title,
                      description: description,
                      icon: kind.icon,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (source.isNotEmpty || (!loading && error == null))
                            Chip(label: Text('${source.length} 部作品')),
                          if (owned > 0)
                            Chip(
                              avatar: const Icon(
                                Icons.bookmark_rounded,
                                size: 16,
                              ),
                              label: Text('已收藏 $owned 部'),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '数据来自 netaba.re',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (loading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: LinearProgressIndicator(minHeight: 2),
                      ),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                source.isNotEmpty ? '刷新失败，已保留当前榜单' : error!,
                              ),
                            ),
                            TextButton(
                              onPressed: loading ? null : onRefresh,
                              child: const Text('重试'),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 16),
                  ],
                );
              }
              if (index == visible.length + 1) {
                if (visible.isNotEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: Text(
                        '已显示 ${visible.length} 部作品',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  );
                }
                if (loading || error != null) return const SizedBox.shrink();
                return EmptyState(
                  icon: onlyMine
                      ? Icons.bookmark_border_rounded
                      : Icons.ssid_chart_rounded,
                  title: onlyMine ? '这份榜单里还没有你的收藏' : '暂时没有趋势记录',
                  message: onlyMine ? '切换到全部作品，看看新的兴趣。' : '稍后再来看看。',
                );
              }
              final row = visible[index - 1];
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _TrendTile(
                  rank: row.rank,
                  item: row.item,
                  mine: mine[row.item.bgmId],
                  period: kind.period,
                  onTap: () => onTap(row.item),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _TrendTile extends StatelessWidget {
  const _TrendTile({
    required this.rank,
    required this.item,
    required this.mine,
    required this.period,
    required this.onTap,
  });
  final int rank;
  final NetabaTrendingItem item;
  final UserCollection? mine;
  final String period;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final delta = item.scoreDelta;
    final positive = delta > 0;
    final color = delta == 0
        ? scheme.onSurfaceVariant
        : positive
        ? (scheme.brightness == Brightness.dark
              ? const Color(0xFF80DDB5)
              : const Color(0xFF187650))
        : (scheme.brightness == Brightness.dark
              ? const Color(0xFFFFB4A8)
              : const Color(0xFFB44439));
    final samples = item.sparkline();
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: rank <= 3
                          ? scheme.primaryContainer
                          : scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$rank',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ReadableSubjectTitle(
                      item.displayName,
                      maxLines: 2,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
              if (mine != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      Chip(
                        avatar: const Icon(Icons.bookmark_rounded, size: 15),
                        label: Text(mine!.type.labelFor(mine!.subject.type)),
                        visualDensity: VisualDensity.compact,
                      ),
                      if (mine!.rate > 0)
                        Chip(
                          label: Text('你评 ${mine!.rate} 分'),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final metrics = Wrap(
                    spacing: 22,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '当前评分',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                          Text(
                            item.latestScore > 0
                                ? item.latestScore.toStringAsFixed(2)
                                : '—',
                            style: Theme.of(context).textTheme.headlineMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$period变化',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                delta == 0
                                    ? Icons.trending_flat_rounded
                                    : positive
                                    ? Icons.trending_up_rounded
                                    : Icons.trending_down_rounded,
                                color: color,
                                size: 21,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                '${delta > 0 ? '+' : ''}${delta.toStringAsFixed(2)}',
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(
                                      color: color,
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      if (item.latestRank > 0)
                        Text(
                          'Bangumi #${item.latestRank}',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                    ],
                  );
                  Widget graph(double width) => Semantics(
                    label: '${item.displayName}的历史评分走势',
                    child: samples.length < 2
                        ? SizedBox(
                            width: width,
                            height: 54,
                            child: const Center(child: Text('暂无曲线')),
                          )
                        : ScoreSparkline(
                            points: samples,
                            color: color,
                            width: width,
                            height: 54,
                          ),
                  );
                  if (constraints.maxWidth < 620 ||
                      MediaQuery.textScalerOf(context).scale(14) > 21) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        metrics,
                        const SizedBox(height: 12),
                        graph(constraints.maxWidth),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: metrics),
                      const SizedBox(width: 24),
                      graph(160),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
