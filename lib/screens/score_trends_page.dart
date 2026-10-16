import '../widgets/score_comparison_chart.dart';
import '../widgets/image_share_sheet.dart';
import '../core/theme/anime_icon.dart';
import '../navigation/app_destination.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../widgets/readable_subject_title.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/network/netaba_api.dart';
import '../models/bangumi_models.dart';
import '../models/netaba_models.dart';
import '../state/session_controller.dart';
import '../widgets/score_history_chart.dart';
import 'score_comparison_page.dart';
import '../widgets/subject_widgets.dart';
import '../core/theme/app_tokens.dart';

enum _TrendKind {
  up('涨分', '近期涨分', '近期', Icons.trending_up_rounded),
  down('跌分', '近期跌分', '近期', Icons.trending_down_rounded),
  done('完结波动', '完结评分', '近期', Icons.done_all_rounded),
  reputation('长期提升', '长期评分', '开播以来', Icons.auto_awesome_rounded);

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
    _tabs = TabController(length: 5, vsync: this)
      ..addListener(() {
        if (mounted) setState(() {});
      });
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
      MaterialPageRoute<void>(builder: (_) => SubjectRoute(subject: subject)),
    );
  }

  List<NetabaTrendingItem> _source(_TrendKind kind) => switch (kind) {
    _TrendKind.up => _trending?.up ?? const [],
    _TrendKind.down => _trending?.down ?? const [],
    _TrendKind.done => _trending?.done ?? const [],
    _TrendKind.reputation => _reputation,
  };

  Future<void> _share(_TrendKind kind, List<NetabaTrendingItem> items) {
    const colors = [
      Color(0xFFA64B58),
      Color(0xFF377CC8),
      Color(0xFF219B80),
      Color(0xFFBD771D),
      Color(0xFF8254CA),
      Color(0xFFCD5C3D),
    ];
    final lines = [
      for (var i = 0; i < items.length; i++)
        ScoreComparisonLine(items[i].displayName, [
          for (final p in items[i].history)
            if (p.hasScore) NetabaChartPoint(p.recordedAt, p.score),
        ], colors[i % colors.length]),
    ];
    return showImageShareSheet(
      context,
      title:
          '${kind.label} · ${items.length == 1 ? items.single.displayName : '当前榜单前 ${items.length} 部'}',
      filename: 'MuBangumi-trend-${kind.name}.png',
      subtitle: '数据来源：netaba.re · 圆点标记起点、最新、最高和最低的实际记录',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '${item.displayName}  ${item.latestScore.toStringAsFixed(2)} 分  ·  ${kind.period} ${item.scoreDelta > 0 ? '+' : ''}${item.scoreDelta.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ScoreComparisonChart(lines: lines, markKeyPoints: true),
          ScoreChartKeyPoints(lines: lines),
        ],
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
          if (_tabs.index < 4)
            IconButton(
              tooltip: '分享趋势图',
              onPressed: () {
                final kind = _TrendKind.values[_tabs.index];
                final source = _source(kind)
                    .where((item) => !_onlyMine || mine.containsKey(item.bgmId))
                    .take(6)
                    .toList();
                if (source.isNotEmpty) _share(kind, source);
              },
              icon: const AnimeIcon(Icons.ios_share_rounded),
            ),
          IconButton(
            tooltip: '刷新榜单',
            onPressed: loading ? null : () => _load(refresh: true),
            icon: const AnimeIcon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: '数据来源 · netaba.re',
            onPressed: () => launchUrl(
              Uri.parse('https://netaba.re/trending'),
              mode: LaunchMode.externalApplication,
            ),
            icon: const AnimeIcon(Icons.open_in_new_rounded),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            for (final kind in _TrendKind.values) Tab(text: kind.label),
            const Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimeIcon(Icons.multiline_chart_rounded, size: 18),
                  SizedBox(width: 6),
                  Text('历史对比'),
                ],
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_tabs.index < 4)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
                child: Align(
                  alignment: Alignment.center,
                  child: SizedBox(
                    width: 1004,
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
                          avatar: const AnimeIcon(
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
                      onShare: (item) => _share(kind, [item]),
                    ),
                  ScoreComparisonPage(
                    embedded: true,
                    initial: session.collections
                        .where((item) => item.subject.type == SubjectType.anime)
                        .take(2)
                        .map((item) => item.subject)
                        .toList(),
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
    required this.onShare,
  });
  final _TrendKind kind;
  final List<NetabaTrendingItem> source;
  final bool loading;
  final String? error;
  final bool onlyMine;
  final Map<int, UserCollection> mine;
  final Future<void> Function() onRefresh;
  final ValueChanged<NetabaTrendingItem> onTap;
  final ValueChanged<NetabaTrendingItem> onShare;

  @override
  Widget build(BuildContext context) {
    final visible = [
      for (var i = 0; i < source.length; i++)
        if (!onlyMine || mine.containsKey(source[i].bgmId))
          (rank: i + 1, item: source[i]),
    ];
    final owned = source.where((item) => mine.containsKey(item.bgmId)).length;
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
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Wrap(
                        spacing: 16,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            '${kind.title} · ${visible.length} 部',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          if (owned > 0)
                            Text(
                              '已收藏 $owned 部',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          Text(
                            '红涨绿跌 · 数据来自 netaba.re',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
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
                    _QuoteColumns(period: kind.period),
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
              return _TrendTile(
                rank: row.rank,
                item: row.item,
                mine: mine[row.item.bgmId],
                period: kind.period,
                onTap: () => onTap(row.item),
                onShare: () => onShare(row.item),
              );
            },
          ),
        ),
      ),
    );
  }
}

bool _wideQuotes(BuildContext context, double width) =>
    width >= 760 && MediaQuery.textScalerOf(context).scale(14) <= 19;

class _QuoteColumns extends StatelessWidget {
  const _QuoteColumns({required this.period});
  final String period;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (!_wideQuotes(context, constraints.maxWidth)) {
        return const SizedBox.shrink();
      }
      final theme = Theme.of(context);
      return Container(
        color: theme.colorScheme.surfaceContainerLow,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: DefaultTextStyle(
          style: theme.textTheme.labelMedium!.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          child: Row(
            children: [
              const SizedBox(width: 36, child: Text('#')),
              const Expanded(child: Text('作品')),
              const SizedBox(
                width: 110,
                child: Text('当前评分', textAlign: TextAlign.right),
              ),
              SizedBox(
                width: 130,
                child: Text('$period涨跌 / 分', textAlign: TextAlign.right),
              ),
              const SizedBox(width: 24),
              const SizedBox(
                width: 150,
                child: Text('评分走势', textAlign: TextAlign.center),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _TrendTile extends StatelessWidget {
  const _TrendTile({
    required this.rank,
    required this.item,
    required this.mine,
    required this.period,
    required this.onTap,
    required this.onShare,
  });
  final int rank;
  final NetabaTrendingItem item;
  final UserCollection? mine;
  final String period;
  final VoidCallback onTap;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final delta = item.scoreDelta;
    final positive = delta > 0;
    final color = delta == 0
        ? scheme.onSurfaceVariant
        : positive
        ? AppPalette.rise(scheme.brightness)
        : AppPalette.fall(scheme.brightness);
    final samples = item.sparkline();
    final numberStyle = theme.textTheme.titleLarge?.copyWith(
      fontWeight: FontWeight.w600,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final score = Text(
      item.latestScore > 0 ? item.latestScore.toStringAsFixed(2) : '—',
      style: numberStyle,
      textAlign: TextAlign.right,
    );
    final change = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimeIcon(
          delta == 0
              ? Icons.trending_flat_rounded
              : positive
              ? Icons.trending_up_rounded
              : Icons.trending_down_rounded,
          color: color,
          size: 16,
        ),
        const SizedBox(width: 4),
        Text(
          '${delta > 0 ? '+' : ''}${delta.toStringAsFixed(2)}',
          style: numberStyle?.copyWith(color: color, fontSize: 18),
        ),
      ],
    );
    final identity = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: ReadableSubjectTitle(
                item.displayName,
                maxLines: 2,
                style: theme.textTheme.titleSmall,
              ),
            ),
            IconButton(
              tooltip: '分享此作品趋势',
              onPressed: onShare,
              icon: const AnimeIcon(Icons.ios_share_rounded, size: 18),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Wrap(
          spacing: 10,
          runSpacing: 4,
          children: [
            if (item.latestRank > 0)
              Text(
                'Bangumi #${item.latestRank}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            if (mine != null)
              Text(
                mine!.type.labelFor(mine!.subject.type),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.primary,
                ),
              ),
            if (mine != null && mine!.rate > 0)
              Text(
                '你评 ${mine!.rate} 分',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ],
    );
    Widget graph(double width) => Semantics(
      label: '${item.displayName}的历史评分走势',
      child: samples.length < 2
          ? SizedBox(
              width: width,
              height: 40,
              child: Center(
                child: Text('暂无曲线', style: theme.textTheme.labelSmall),
              ),
            )
          : ScoreSparkline(
              points: samples,
              color: color,
              width: width,
              height: 40,
            ),
    );
    return Material(
      key: ValueKey('trend-quote-${item.bgmId}'),
      color: scheme.surface,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: .6),
              ),
            ),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final rankLabel = Text(
                '$rank',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              );
              if (_wideQuotes(context, constraints.maxWidth + 28)) {
                return Row(
                  children: [
                    SizedBox(width: 36, child: rankLabel),
                    Expanded(child: identity),
                    SizedBox(width: 110, child: score),
                    SizedBox(
                      width: 130,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: change,
                      ),
                    ),
                    const SizedBox(width: 24),
                    graph(150),
                  ],
                );
              }
              final metrics = Wrap(
                spacing: 18,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('当前评分', style: theme.textTheme.labelSmall),
                      score,
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$period涨跌 / 分', style: theme.textTheme.labelSmall),
                      change,
                    ],
                  ),
                ],
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 28, child: rankLabel),
                      Expanded(child: identity),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (constraints.maxWidth >= 340 &&
                      MediaQuery.textScalerOf(context).scale(14) <= 19)
                    Row(
                      children: [
                        Expanded(child: metrics),
                        const SizedBox(width: 12),
                        graph(110),
                      ],
                    )
                  else ...[
                    metrics,
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: graph(constraints.maxWidth),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
