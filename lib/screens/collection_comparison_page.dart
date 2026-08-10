import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/insights/collection_insights.dart';
import '../models/bangumi_models.dart';
import '../state/session_controller.dart';

class CollectionComparisonPage extends ConsumerStatefulWidget {
  const CollectionComparisonPage({
    super.key,
    required this.targetUsername,
    required this.targetDisplayName,
  });

  final String targetUsername;
  final String targetDisplayName;

  @override
  ConsumerState<CollectionComparisonPage> createState() =>
      _CollectionComparisonPageState();
}

class _CollectionComparisonPageState
    extends ConsumerState<CollectionComparisonPage> {
  CollectionComparison? _comparison;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    setState(() {
      _comparison = null;
      _error = null;
    });
    final me = ref.read(sessionProvider).user;
    if (me == null) {
      setState(() => _error = '请先登录后再进行收藏对比');
      return;
    }
    try {
      final api = ref.read(bangumiApiProvider);
      final pages = await Future.wait([
        api.getUserCollections(me.username, subjectType: SubjectType.anime),
        api.getUserCollections(
          widget.targetUsername,
          subjectType: SubjectType.anime,
        ),
      ]);
      if (!mounted) return;
      setState(
        () => _comparison = CollectionInsights.compare(pages[0], pages[1]),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('与 ${widget.targetDisplayName} 的口味对比')),
    body: _buildBody(),
  );

  Widget _buildBody() {
    final comparison = _comparison;
    if (_error != null) {
      return Center(
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
      );
    }
    if (comparison == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Text(
                  '${comparison.similarityPercent}%',
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const Text('综合口味相似度'),
                const SizedBox(height: 14),
                LinearProgressIndicator(value: comparison.similarity),
                const SizedBox(height: 12),
                Text(
                  '置信度：${comparison.confidenceLabel} · '
                  '共同收藏 ${comparison.sharedTotal} 部 · '
                  '共同评分 ${comparison.sharedRatedTotal} 部',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                label: '收藏重合',
                value: '${comparison.catalogOverlapPercent}%',
                detail: '${comparison.myTotal} / ${comparison.theirTotal} 部',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _MetricCard(
                label: '评分接近',
                value: '${comparison.ratingClosenessPercent}%',
                detail: comparison.ratingCorrelation == null
                    ? '样本少，未算相关性'
                    : '相关系数 ${comparison.ratingCorrelation!.toStringAsFixed(2)}',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          '算法说明：综合分由 Jaccard 收藏重合度、共同评分的 Pearson 相关性和平均评分差构成；共同评分越少，评分信号权重越低。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 24),
        _ComparedSection(
          title: '共同喜欢',
          emptyText: '暂时没有双方都打出 7 分以上的条目',
          items: comparison.commonFavorites,
        ),
        const SizedBox(height: 22),
        _ComparedSection(
          title: '分歧最大',
          emptyText: '共同评分的条目中没有明显分歧',
          items: comparison.biggestDifferences,
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.detail,
  });

  final String label;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label),
          const SizedBox(height: 4),
          Text(value, style: Theme.of(context).textTheme.headlineSmall),
          Text(detail, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    ),
  );
}

class _ComparedSection extends StatelessWidget {
  const _ComparedSection({
    required this.title,
    required this.emptyText,
    required this.items,
  });

  final String title;
  final String emptyText;
  final List<ComparedCollection> items;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 8),
      if (items.isEmpty)
        Card(child: ListTile(title: Text(emptyText)))
      else
        for (final item in items)
          Card(
            child: ListTile(
              title: Text(item.mine.subject.displayName),
              subtitle: Text(
                '我 ${item.mine.rate} 分 · 对方 ${item.theirs.rate} 分',
              ),
              trailing: item.ratingDifference == 0
                  ? const Icon(Icons.handshake_outlined)
                  : Text('相差 ${item.ratingDifference}'),
            ),
          ),
    ],
  );
}
