import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../widgets/readable_subject_title.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../core/insights/collection_insights.dart';
import '../core/insights/collection_year_review.dart';
import '../widgets/insight_widgets.dart';
import 'subject_detail_screen.dart';
import '../models/bangumi_models.dart';
import '../widgets/subject_widgets.dart';

enum _ExportAction { save, share }

class CollectionStatsPage extends StatefulWidget {
  const CollectionStatsPage({
    super.key,
    required this.username,
    this.displayName,
    required this.collections,
  });

  final String username;
  final String? displayName;
  final List<UserCollection> collections;

  @override
  State<CollectionStatsPage> createState() => _CollectionStatsPageState();
}

class _CollectionStatsPageState extends State<CollectionStatsPage> {
  late CollectionStatistics _statistics;
  late List<UserCollection> _filtered;
  CollectionYearReview? _review;
  SubjectType? _subjectType;
  bool _annual = false;
  int? _month;
  int? _year;
  bool _exporting = false;
  bool _choosingExport = false;
  final _exportButtonKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _recompute();
  }

  @override
  void didUpdateWidget(covariant CollectionStatsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.collections != widget.collections) _recompute();
  }

  void _recompute() {
    _filtered = [
      for (final item in widget.collections)
        if (_subjectType == null || item.subject.type == _subjectType) item,
    ];
    _statistics = CollectionStatistics(_filtered);
    _year ??= _statistics.years.contains(DateTime.now().year)
        ? DateTime.now().year
        : _statistics.years.firstOrNull ?? DateTime.now().year;
    _review = CollectionYearReview(_filtered, _year!);
  }

  void _selectType(SubjectType? type) {
    if (_subjectType == type) return;
    setState(() {
      _subjectType = type;
      _month = null;
      _recompute();
    });
  }

  Future<void> _exportJson() async {
    if (_exporting || _choosingExport) return;
    setState(() => _choosingExport = true);
    try {
      final box =
          _exportButtonKey.currentContext?.findRenderObject() as RenderBox?;
      final origin = box == null
          ? null
          : box.localToGlobal(Offset.zero) & box.size;
      final action = await showModalBottomSheet<_ExportAction>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                title: Text('导出全部收藏'),
                subtitle: Text('包含评分、短评、标签及隐私标记'),
              ),
              ListTile(
                leading: const Icon(Icons.save_alt_rounded),
                title: const Text('另存为 JSON'),
                subtitle: const Text('选择保存位置'),
                onTap: () => Navigator.pop(context, _ExportAction.save),
              ),
              ListTile(
                leading: const Icon(Icons.share_rounded),
                title: const Text('分享收藏文件'),
                onTap: () => Navigator.pop(context, _ExportAction.share),
              ),
            ],
          ),
        ),
      );
      if (action == null || !mounted) return;
      setState(() {
        _choosingExport = false;
        _exporting = true;
      });
      final now = DateTime.now();
      final stamp =
          '${now.year}${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}_'
          '${now.hour.toString().padLeft(2, '0')}'
          '${now.minute.toString().padLeft(2, '0')}'
          '${now.second.toString().padLeft(2, '0')}';
      final safeUsername = widget.username.replaceAll(
        RegExp(r'[^a-zA-Z0-9_-]'),
        '_',
      );
      final filename = 'MuBangumi_${safeUsername}_$stamp.json';
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
      if (!mounted) return;
      final bytes = Uint8List.fromList(utf8.encode(encoded));
      if (action == _ExportAction.share) {
        await Share.shareXFiles(
          [XFile.fromData(bytes, mimeType: 'application/json')],
          fileNameOverrides: [filename],
          subject: 'MuBangumi 收藏数据',
          sharePositionOrigin: origin,
        );
      } else {
        final destination = await FilePicker.platform.saveFile(
          dialogTitle: '保存收藏数据',
          fileName: filename,
          type: FileType.custom,
          allowedExtensions: ['json'],
          bytes: bytes,
          lockParentWindow: true,
        );
        if (destination == null || !mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('收藏数据已保存到所选位置')));
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导出失败：$error')));
    } finally {
      if (mounted) {
        setState(() {
          _exporting = false;
          _choosingExport = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final years = {DateTime.now().year, _year!, ..._statistics.years}.toList()
      ..sort((a, b) => b.compareTo(a));
    return Scaffold(
      appBar: AppBar(
        title: const Text('收藏手账'),
        actions: [
          IconButton(
            key: _exportButtonKey,
            tooltip: '导出收藏数据',
            onPressed: _exporting || _choosingExport ? null : _exportJson,
            icon: _exporting
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.file_download_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: ListView(
              key: PageStorageKey('stats:$_annual'),
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 40),
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: false,
                        icon: Icon(Icons.donut_small_rounded),
                        label: Text('收藏概览'),
                      ),
                      ButtonSegment(
                        value: true,
                        icon: Icon(Icons.auto_awesome_rounded),
                        label: Text('年度回顾'),
                      ),
                    ],
                    selected: {_annual},
                    showSelectedIcon: false,
                    onSelectionChanged: (value) => setState(() {
                      _annual = value.first;
                      _month = null;
                    }),
                  ),
                ),
                const SizedBox(height: 14),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ChoiceChip(
                        label: const Text('全部类型'),
                        selected: _subjectType == null,
                        onSelected: (_) => _selectType(null),
                      ),
                      for (final type in SubjectType.values) ...[
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: Text(type.label),
                          selected: _subjectType == type,
                          onSelected: (_) => _selectType(type),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                if (_annual) ...[
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '选择回顾年份',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      ),
                      DropdownButton<int>(
                        value: _year,
                        underline: const SizedBox.shrink(),
                        items: [
                          for (final year in years)
                            DropdownMenuItem(
                              value: year,
                              child: Text('$year 年'),
                            ),
                        ],
                        onChanged: (year) {
                          if (year == null) return;
                          setState(() {
                            _year = year;
                            _month = null;
                            _review = CollectionYearReview(_filtered, year);
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ..._annualContent(context),
                ] else
                  ..._overviewContent(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String get _name => widget.displayName?.trim().isNotEmpty == true
      ? widget.displayName!.trim()
      : widget.username;

  List<Widget> _overviewContent(BuildContext context) {
    final types =
        _statistics.bySubjectType.entries
            .where((entry) => entry.value > 0)
            .toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    final tags = _statistics.tagCounts.entries;
    final personalLine = _statistics.total == 0
        ? '从收藏第一部喜欢的作品开始。'
        : types.length == 1
        ? '这里收下了你记录的 ${_statistics.total} 部${types.first.key.label}。'
        : '你记录了 ${types.length} 种类型，${types.first.key.label}在其中占了 ${(types.first.value / _statistics.total * 100).round()}%。';
    return [
      InsightHero(
        label: _subjectType == null ? '你的收藏全貌' : '${_subjectType!.label}收藏',
        title: '$_name 的收藏手账',
        description: personalLine,
      ),
      const SizedBox(height: 16),
      InsightMetrics(
        children: [
          InsightMetric(
            label: '总收藏',
            value: '${_statistics.total}',
            icon: Icons.bookmarks_outlined,
          ),
          InsightMetric(
            label: '留下评分',
            value: '${_statistics.ratedTotal}',
            icon: Icons.star_outline_rounded,
            detail: _statistics.total == 0
                ? '等待你的第一笔评价'
                : '占收藏的 ${(_statistics.ratedTotal / _statistics.total * 100).round()}%',
          ),
          InsightMetric(
            label: '你的平均分',
            value: _statistics.ratedTotal == 0
                ? '—'
                : _statistics.averageRating.toStringAsFixed(1),
            icon: Icons.favorite_border_rounded,
            detail: '未评分作品不计入',
          ),
        ],
      ),
      if (_filtered.isEmpty)
        const InsightSection(
          title: '慢慢积累你的喜好',
          child: Text('收藏、评分和标签，会让这里逐渐成为你的作品地图。'),
        )
      else ...[
        LayoutBuilder(
          builder: (context, constraints) {
            final composition = InsightSection(
              title: '收藏的不同侧面',
              child: _Composition(statistics: _statistics),
            );
            final ratings = InsightSection(
              title: '你的评分习惯',
              child: _Ratings(statistics: _statistics),
            );
            final tagSection = tags.isEmpty
                ? const SizedBox.shrink()
                : InsightSection(
                    title: '你常用的标签',
                    subtitle: '「${tags.first.key}」出现在 ${tags.first.value} 条收藏中',
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final entry in tags.take(12))
                          Chip(label: Text('${entry.key} · ${entry.value}')),
                      ],
                    ),
                  );
            if (constraints.maxWidth < 800) {
              return Column(children: [composition, ratings, tagSection]);
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Column(children: [composition, tagSection])),
                const SizedBox(width: 24),
                Expanded(child: ratings),
              ],
            );
          },
        ),
      ],
    ];
  }

  List<Widget> _annualContent(BuildContext context) {
    final review = _review!;
    final stats = review.statistics;
    final selected = review.forMonth(_month);
    final tag = stats.tagCounts.entries.firstOrNull;
    final peaks = review.peakMonths;
    return [
      InsightHero(
        label: '${_year!} 年度回顾',
        title: '$_name 的这一年',
        description: review.items.isEmpty
            ? '这一年，暂时还没有可回顾的记录。'
            : '${review.items.length} 条收藏更新，分布在 ${review.activeMonths} 个月里。${tag == null ? '' : '「${tag.key}」是你最常用的标签之一。'}',
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (stats.ratedTotal > 0)
              Chip(
                avatar: const Icon(Icons.star_rounded, size: 17),
                label: Text('最高 ${review.items.first.rate} 分'),
              ),
            if (peaks.isNotEmpty)
              Chip(
                avatar: const Icon(Icons.calendar_month_rounded, size: 17),
                label: Text(
                  peaks.length == 1
                      ? '${peaks.first} 月更新最活跃'
                      : '${peaks.length} 个月并列最活跃',
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      Text(
        '年份与月份按收藏的最后更新时间统计。',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 18),
      InsightMetrics(
        children: [
          InsightMetric(
            label: '收藏更新',
            value: '${stats.total}',
            icon: Icons.bookmark_added_outlined,
          ),
          InsightMetric(
            label: '其中已评分',
            value: '${stats.ratedTotal}',
            icon: Icons.rate_review_outlined,
          ),
          InsightMetric(
            label: '你的平均分',
            value: stats.ratedTotal == 0
                ? '—'
                : stats.averageRating.toStringAsFixed(1),
            icon: Icons.star_border_rounded,
          ),
        ],
      ),
      if (review.items.isNotEmpty) ...[
        InsightSection(
          title: '这一年的记录节奏',
          subtitle: '点击月份，翻看当时更新的收藏',
          child: _MonthActivity(
            counts: review.months,
            selected: _month,
            onSelected: (month) =>
                setState(() => _month = _month == month ? null : month),
          ),
        ),
        InsightSection(
          title: _month == null ? '你的评分与收藏片段' : '$_month 月的收藏片段',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_month != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: ActionChip(
                    label: const Text('查看全年'),
                    avatar: const Icon(Icons.close_rounded, size: 16),
                    onPressed: () => setState(() => _month = null),
                  ),
                ),
              if (selected.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text('这个月没有收藏更新记录。'),
                ),
              for (final item in selected.take(10))
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _MemoryCard(
                    item: item,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            SubjectDetailScreen(subject: item.subject),
                      ),
                    ),
                  ),
                ),
              if (selected.length > 10)
                Text(
                  '展示评分优先的 10 部作品 · 共 ${selected.length} 条记录',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ),
      ],
    ];
  }
}

String _encodeCollectionExport(Map<String, Object?> payload) =>
    const JsonEncoder.withIndent('  ').convert(payload);

class _Composition extends StatelessWidget {
  const _Composition({required this.statistics});
  final CollectionStatistics statistics;
  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final entry in statistics.bySubjectType.entries)
            if (entry.value > 0)
              _DistributionRow(
                label: entry.key.label,
                count: entry.value,
                total: statistics.total,
                icon: subjectTypeIcon(entry.key),
              ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in statistics.byCollectionType.entries)
                if (entry.value > 0)
                  Chip(
                    label: Text('${_statusLabel(entry.key)} · ${entry.value}'),
                  ),
            ],
          ),
        ],
      ),
    ),
  );

  String _statusLabel(CollectionType type) => switch (type) {
    CollectionType.wish => '待体验',
    CollectionType.done => '已完成',
    CollectionType.doing => '进行中',
    CollectionType.onHold => '搁置',
    CollectionType.dropped => '已放弃',
  };
}

class _Ratings extends StatelessWidget {
  const _Ratings({required this.statistics});
  final CollectionStatistics statistics;
  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: statistics.ratedTotal == 0
          ? const Text('还没有评分。遇到喜欢的作品时，留下你的感受吧。')
          : Column(
              children: [
                for (var rating = 10; rating >= 1; rating--)
                  _DistributionRow(
                    label: '$rating 分',
                    count: statistics.ratingDistribution[rating] ?? 0,
                    total: statistics.ratedTotal,
                  ),
              ],
            ),
    ),
  );
}

class _DistributionRow extends StatelessWidget {
  const _DistributionRow({
    required this.label,
    required this.count,
    required this.total,
    this.icon,
  });
  final String label;
  final int count;
  final int total;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Column(
      children: [
        Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16),
              const SizedBox(width: 6),
            ],
            Expanded(child: Text(label)),
            Text('$count', style: Theme.of(context).textTheme.labelLarge),
          ],
        ),
        const SizedBox(height: 6),
        LinearProgressIndicator(
          value: total == 0 ? 0 : count / total,
          minHeight: 6,
          borderRadius: BorderRadius.circular(8),
          backgroundColor: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest,
        ),
      ],
    ),
  );
}

class _MonthActivity extends StatelessWidget {
  const _MonthActivity({
    required this.counts,
    required this.selected,
    required this.onSelected,
  });
  final List<int> counts;
  final int? selected;
  final ValueChanged<int> onSelected;
  @override
  Widget build(BuildContext context) {
    final maxCount = counts.fold<int>(1, (a, b) => a > b ? a : b);
    final scheme = Theme.of(context).colorScheme;
    final labelHeight = MediaQuery.textScalerOf(context).scale(12) * 1.6;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final minWidth =
                (MediaQuery.textScalerOf(context).scale(11) * 2 + 6) * 12;
            final width = constraints.maxWidth > minWidth
                ? constraints.maxWidth
                : minWidth;
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: width,
                height: 116 + labelHeight * 2,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < 12; i++)
                      Expanded(
                        child: Semantics(
                          button: true,
                          selected: selected == i + 1,
                          label: '${i + 1}月，${counts[i]}条更新',
                          child: InkWell(
                            onTap: () => onSelected(i + 1),
                            borderRadius: BorderRadius.circular(8),
                            child: Tooltip(
                              message: '${i + 1}月 · ${counts[i]} 条更新',
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 3,
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    SizedBox(
                                      height: labelHeight,
                                      child: Text(
                                        counts[i] == 0 ? '' : '${counts[i]}',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.labelSmall,
                                      ),
                                    ),
                                    Container(
                                      height: 4 + 88 * counts[i] / maxCount,
                                      decoration: BoxDecoration(
                                        color: selected == i + 1
                                            ? scheme.primary
                                            : scheme.primary.withValues(
                                                alpha: selected == null
                                                    ? .55
                                                    : .2,
                                              ),
                                        borderRadius: BorderRadius.circular(5),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    SizedBox(
                                      height: labelHeight,
                                      child: Text(
                                        '${i + 1}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(
                                              fontWeight: selected == i + 1
                                                  ? FontWeight.w800
                                                  : null,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _MemoryCard extends StatelessWidget {
  const _MemoryCard({required this.item, required this.onTap});
  final UserCollection item;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SubjectCover(
              subject: item.subject,
              width: 62,
              height: 88,
              borderRadius: 10,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ReadableSubjectTitle(
                    item.subject.displayName,
                    maxLines: 2,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      Text(
                        item.rate > 0 ? '你评 ${item.rate} 分' : '还未评分',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        item.type.labelFor(item.subject.type),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  if (item.comment.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      '“${item.comment.trim()}”',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
