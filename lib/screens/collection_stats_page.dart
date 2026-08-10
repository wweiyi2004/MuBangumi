import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../core/insights/collection_insights.dart';
import '../models/bangumi_models.dart';
import '../widgets/subject_widgets.dart';

class CollectionStatsPage extends StatefulWidget {
  const CollectionStatsPage({
    super.key,
    required this.username,
    required this.collections,
  });

  final String username;
  final List<UserCollection> collections;

  @override
  State<CollectionStatsPage> createState() => _CollectionStatsPageState();
}

class _CollectionStatsPageState extends State<CollectionStatsPage> {
  late final CollectionStatistics _statistics;
  int? _year;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _statistics = CollectionStatistics(widget.collections);
    _year = _statistics.years.contains(DateTime.now().year)
        ? DateTime.now().year
        : _statistics.years.firstOrNull;
  }

  Future<void> _exportJson() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final root = await _exportDirectory();
      await root.create(recursive: true);
      final now = DateTime.now();
      final stamp =
          '${now.year}${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}_'
          '${now.hour.toString().padLeft(2, '0')}'
          '${now.minute.toString().padLeft(2, '0')}'
          '${now.second.toString().padLeft(2, '0')}';
      final file = File(
        path.join(root.path, 'MuBangumi_${widget.username}_$stamp.json'),
      );
      final payload = <String, Object?>{
        'schema_version': 1,
        'exported_at': now.toIso8601String(),
        'username': widget.username,
        'count': widget.collections.length,
        'collections': [
          for (final item in widget.collections)
            {
              'subject_id': item.subjectId,
              'subject_type': item.subject.type.value,
              'subject_name': item.subject.name,
              'subject_name_cn': item.subject.nameCn,
              'collection_type': item.type.value,
              'rate': item.rate,
              'episode_status': item.episodeStatus,
              'volume_status': item.volumeStatus,
              'updated_at': item.updatedAt?.toIso8601String(),
              'comment': item.comment,
              'tags': item.tags,
              'private': item.private,
            },
        ],
      };
      final encoded = await compute(_encodeCollectionExport, payload);
      await file.writeAsString(encoded, flush: true);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已导出到 ${file.path}')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导出失败：$error')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<Directory> _exportDirectory() async {
    if (Platform.isAndroid || Platform.isIOS) {
      final documents = await getApplicationDocumentsDirectory();
      return Directory(path.join(documents.path, 'exports'));
    }
    final downloads = await getDownloadsDirectory();
    if (downloads != null) {
      return Directory(path.join(downloads.path, 'MuBangumi'));
    }
    final documents = await getApplicationDocumentsDirectory();
    return Directory(path.join(documents.path, 'MuBangumi', 'exports'));
  }

  @override
  Widget build(BuildContext context) {
    final year = _year;
    final yearly = year == null
        ? const <UserCollection>[]
        : _statistics.forYear(widget.collections, year);
    final ratedYearly = yearly.where((item) => item.rate > 0).toList();
    final yearlyAverage = ratedYearly.isEmpty
        ? 0.0
        : ratedYearly.fold<int>(0, (sum, item) => sum + item.rate) /
              ratedYearly.length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('收藏统计'),
        actions: [
          IconButton(
            tooltip: '导出 JSON',
            onPressed: _exporting ? null : _exportJson,
            icon: _exporting
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.file_download_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final width = (constraints.maxWidth - 20) / 3;
              return Row(
                children: [
                  _OverviewCard(
                    width: width,
                    label: '总收藏',
                    value: '${_statistics.total}',
                  ),
                  const SizedBox(width: 10),
                  _OverviewCard(
                    width: width,
                    label: '已评分',
                    value: '${_statistics.ratedTotal}',
                  ),
                  const SizedBox(width: 10),
                  _OverviewCard(
                    width: width,
                    label: '平均分',
                    value: _statistics.ratedTotal == 0
                        ? '—'
                        : _statistics.averageRating.toStringAsFixed(1),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 22),
          _SectionTitle(title: '收藏构成'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in _statistics.bySubjectType.entries)
                if (entry.value > 0)
                  Chip(
                    avatar: Icon(subjectTypeIcon(entry.key), size: 16),
                    label: Text('${entry.key.label} ${entry.value}'),
                  ),
              for (final entry in _statistics.byCollectionType.entries)
                if (entry.value > 0)
                  Chip(label: Text('${entry.key.label} ${entry.value}')),
            ],
          ),
          const SizedBox(height: 22),
          _SectionTitle(title: '评分分布'),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  for (var rating = 10; rating >= 1; rating--)
                    _RatingBar(
                      rating: rating,
                      count: _statistics.ratingDistribution[rating] ?? 0,
                      total: _statistics.ratedTotal,
                    ),
                ],
              ),
            ),
          ),
          if (_statistics.tagCounts.isNotEmpty) ...[
            const SizedBox(height: 22),
            _SectionTitle(title: '常用标签'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in _statistics.tagCounts.entries.take(16))
                  Chip(label: Text('${entry.key} ${entry.value}')),
              ],
            ),
          ],
          const SizedBox(height: 26),
          Row(
            children: [
              const Expanded(child: _SectionTitle(title: '年度回顾')),
              if (_statistics.years.isNotEmpty)
                DropdownButton<int>(
                  value: year,
                  items: [
                    for (final value in _statistics.years)
                      DropdownMenuItem(value: value, child: Text('$value')),
                  ],
                  onChanged: (value) => setState(() => _year = value),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '按 Bangumi 收藏的最后更新时间统计，不等同于实际观看日期。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          if (yearly.isEmpty)
            const Card(child: ListTile(title: Text('这一年没有可统计的收藏变更')))
          else ...[
            Card(
              child: ListTile(
                leading: const Icon(Icons.auto_awesome_outlined),
                title: Text('$year 年更新了 ${yearly.length} 个收藏'),
                subtitle: Text(
                  ratedYearly.isEmpty
                      ? '这一年没有新增评分'
                      : '其中 ${ratedYearly.length} 个有评分，平均 ${yearlyAverage.toStringAsFixed(1)} 分',
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text('年度高分', style: Theme.of(context).textTheme.titleMedium),
            for (final item in ratedYearly.take(10))
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(item.subject.displayName),
                subtitle: Text(item.type.labelFor(item.subject.type)),
                trailing: Text('${item.rate} 分'),
              ),
          ],
        ],
      ),
    );
  }
}

String _encodeCollectionExport(Map<String, Object?> payload) =>
    const JsonEncoder.withIndent('  ').convert(payload);

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({
    required this.width,
    required this.label,
    required this.value,
  });

  final double width;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
        child: Column(
          children: [
            Text(value, style: Theme.of(context).textTheme.headlineSmall),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    ),
  );
}

class _RatingBar extends StatelessWidget {
  const _RatingBar({
    required this.rating,
    required this.count,
    required this.total,
  });

  final int rating;
  final int count;
  final int total;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        SizedBox(width: 28, child: Text('$rating')),
        Expanded(
          child: LinearProgressIndicator(
            value: total == 0 ? 0 : count / total,
            minHeight: 8,
            borderRadius: BorderRadius.circular(5),
          ),
        ),
        SizedBox(width: 42, child: Text('$count', textAlign: TextAlign.end)),
      ],
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Text(
    title,
    style: Theme.of(
      context,
    ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
  );
}
