import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/network/netaba_api.dart';
import '../models/bangumi_models.dart';
import '../models/netaba_models.dart';
import '../widgets/score_history_chart.dart';
import '../widgets/subject_widgets.dart';
import 'subject_detail_screen.dart';

/// Bangumi score movers powered by netaba.re analytics.
class ScoreTrendsPage extends ConsumerStatefulWidget {
  const ScoreTrendsPage({super.key});

  @override
  ConsumerState<ScoreTrendsPage> createState() => _ScoreTrendsPageState();
}

class _ScoreTrendsPageState extends ConsumerState<ScoreTrendsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _loading = true;
  String? _error;
  NetabaTrending? _trending;
  List<NetabaTrendingItem> _reputation = const [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(netabaApiProvider);
      final results = await Future.wait([
        api.getTrending(),
        api.getScoreIncreases(),
      ]);
      if (!mounted) return;
      setState(() {
        _trending = results[0] as NetabaTrending;
        _reputation = results[1] as List<NetabaTrendingItem>;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst(RegExp(r'^.*Exception:\s*'), '');
      });
    }
  }

  void _openSubject(NetabaTrendingItem item) {
    final subject = Subject(
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('评分趋势'),
        actions: [
          IconButton(
            tooltip: '在浏览器打开 netaba.re',
            onPressed: () => launchUrl(
              Uri.parse('https://netaba.re/trending'),
              mode: LaunchMode.externalApplication,
            ),
            icon: const Icon(Icons.open_in_new_rounded),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: '涨分'),
            Tab(text: '跌分'),
            Tab(text: '完结波动'),
            Tab(text: '口碑提升'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('重试'),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      child: Text(
                        '近月 Bangumi 评分变化 · 数据来自 netaba.re',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _TrendList(
                            items: _trending?.up ?? const [],
                            rising: true,
                            emptyLabel: '暂无涨分条目',
                            onTap: _openSubject,
                          ),
                          _TrendList(
                            items: _trending?.down ?? const [],
                            rising: false,
                            emptyLabel: '暂无跌分条目',
                            onTap: _openSubject,
                          ),
                          _TrendList(
                            items: _trending?.done ?? const [],
                            rising: null,
                            emptyLabel: '暂无完结波动数据',
                            onTap: _openSubject,
                          ),
                          _TrendList(
                            items: _reputation,
                            rising: true,
                            emptyLabel: '暂无口碑提升数据',
                            deltaLabel: '开播以来',
                            onTap: _openSubject,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _TrendList extends StatelessWidget {
  const _TrendList({
    required this.items,
    required this.rising,
    required this.emptyLabel,
    required this.onTap,
    this.deltaLabel = '近月',
  });

  final List<NetabaTrendingItem> items;
  final bool? rising;
  final String emptyLabel;
  final String deltaLabel;
  final ValueChanged<NetabaTrendingItem> onTap;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return EmptyState(
        icon: Icons.ssid_chart_rounded,
        title: emptyLabel,
        message: '稍后再来看看，或直接打开 netaba.re 查看完整图表。',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final item = items[index];
        return _TrendTile(
          rank: index + 1,
          item: item,
          rising: rising ?? item.scoreDelta >= 0,
          deltaLabel: deltaLabel,
          onTap: () => onTap(item),
        );
      },
    );
  }
}

class _TrendTile extends StatelessWidget {
  const _TrendTile({
    required this.rank,
    required this.item,
    required this.rising,
    required this.deltaLabel,
    required this.onTap,
  });

  final int rank;
  final NetabaTrendingItem item;
  final bool rising;
  final String deltaLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final deltaColor = rising
        ? const Color(0xFF2E9E6B)
        : const Color(0xFFE05A5A);
    final delta = item.scoreDelta;
    final sparkColor = rising
        ? const Color(0xFFF3A646)
        : const Color(0xFFE05A5A);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            children: [
              SizedBox(
                width: 28,
                child: Text(
                  '$rank',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      children: [
                        if (item.latestScore > 0)
                          Text(
                            '当前 ${item.latestScore.toStringAsFixed(2)}',
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        if (item.latestRank > 0)
                          Text(
                            '#${item.latestRank}',
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        Text(
                          '$deltaLabel ${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(2)}',
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: deltaColor,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              ScoreSparkline(
                points: item.sparkline(),
                color: sparkColor,
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
