import '../navigation/app_destination.dart';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../widgets/readable_subject_title.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../core/insights/collection_insights.dart';
import '../core/insights/collection_year_review.dart';
import '../widgets/insight_widgets.dart';
import '../models/bangumi_models.dart';
import '../models/collection_coverage.dart';
import '../widgets/subject_widgets.dart';

enum _ExportAction { save, share }

String _collectionStatusLabel(CollectionType type) => switch (type) {
  CollectionType.wish => '待体验',
  CollectionType.done => '已完成',
  CollectionType.doing => '进行中',
  CollectionType.onHold => '搁置',
  CollectionType.dropped => '已放弃',
};

class CollectionStatsPage extends StatefulWidget {
  const CollectionStatsPage({
    super.key,
    required this.username,
    this.displayName,
    required this.collections,
    this.isLoading = false,
    this.isCached = false,
    this.coverage,
  });

  final String username;
  final String? displayName;
  final List<UserCollection> collections;
  final bool isLoading;
  final bool isCached;
  final CollectionCoverage? coverage;

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
  CollectionMemoryOrder _order = CollectionMemoryOrder.highest;
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

  void _browse(String title, Iterable<UserCollection> items) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 850),
      builder: (_) => FractionallySizedBox(
        heightFactor: .9,
        child: _MemoriesSheet(
          title: title,
          items: items.toList(),
          order: _order,
        ),
      ),
    );
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
              ListTile(
                title: Text(
                  widget.coverage?.isComplete == false ? '导出已加载收藏' : '导出全部收藏',
                ),
                subtitle: Text(
                  widget.coverage?.isComplete == false
                      ? widget.coverage!.notice
                      : '包含评分、短评、标签及隐私标记',
                ),
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
        if (widget.coverage != null) 'coverage': widget.coverage!.toJson(),
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
        title: const Text('统计与回顾'),
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
                if (widget.coverage?.isComplete == false &&
                    !widget.isLoading) ...[
                  Text(
                    widget.coverage!.notice,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                ],
                if (widget.isLoading || widget.isCached) ...[
                  if (widget.isLoading) const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  Text(
                    widget.isLoading
                        ? '收藏同步中 · 先展示已加载的记录，统计会自动更新'
                        : '当前使用本机收藏快照，联网同步后会自动更新',
                  ),
                  const SizedBox(height: 14),
                ],
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
                          '$_name 的这一年',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
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
      _LedgerHeading(
        title: '$_name 的收藏手账',
        description: personalLine,
        action: TextButton.icon(
          onPressed: _filtered.isEmpty
              ? null
              : () => _browse('全部收藏', _filtered),
          icon: const Icon(Icons.view_list_rounded),
          label: const Text('浏览收藏记录'),
        ),
      ),
      const SizedBox(height: 16),
      InsightMetrics(
        children: [
          _LedgerMetric(
            label: widget.coverage?.isComplete == false ? '已加载收藏' : '总收藏',
            value: '${_statistics.total}',
          ),
          _LedgerMetric(
            label: '留下评分',
            value: '${_statistics.ratedTotal}',
            detail: _statistics.total == 0
                ? '等待你的第一笔评价'
                : '占收藏的 ${(_statistics.ratedTotal / _statistics.total * 100).round()}%',
          ),
          _LedgerMetric(
            label: '你的平均分',
            value: _statistics.ratedTotal == 0
                ? '—'
                : _statistics.averageRating.toStringAsFixed(1),
            detail: '未评分作品不计入',
          ),
        ],
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ActionChip(
            avatar: const Icon(Icons.task_alt_rounded, size: 18),
            label: Text('当前已完成 ${_statistics.completedTotal}'),
            onPressed: () => _browse(
              '当前已完成',
              _filtered.where((item) => item.type == CollectionType.done),
            ),
          ),
          ActionChip(
            avatar: const Icon(Icons.favorite_border_rounded, size: 18),
            label: Text('高分收藏 ${_statistics.highRatedTotal}'),
            onPressed: () => _browse(
              '高分收藏 · 8–10 分',
              _filtered.where(
                (item) => CollectionStatistics.isRated(item) && item.rate >= 8,
              ),
            ),
          ),
          ActionChip(
            avatar: const Icon(Icons.edit_note_rounded, size: 18),
            label: Text('留下短评 ${_statistics.commentedTotal}'),
            onPressed: () => _browse(
              '留下短评的收藏',
              _filtered.where((item) => item.comment.trim().isNotEmpty),
            ),
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
              subtitle: '点击类型或状态，查看对应作品',
              child: _Composition(
                statistics: _statistics,
                onType: (type) => _browse(
                  type.label,
                  _filtered.where((item) => item.subject.type == type),
                ),
                onStatus: (type) => _browse(
                  _subjectType == null
                      ? _collectionStatusLabel(type)
                      : type.labelFor(_subjectType!),
                  _filtered.where((item) => item.type == type),
                ),
              ),
            );
            final ratings = InsightSection(
              title: '你的评分习惯',
              subtitle: '点击分数，重温当时的评价',
              child: _Ratings(
                statistics: _statistics,
                onRating: (rating) => _browse(
                  rating == 0 ? '未评分的收藏' : '你评 $rating 分',
                  _filtered.where(
                    (item) => rating == 0
                        ? !CollectionStatistics.isRated(item)
                        : item.rate == rating,
                  ),
                ),
              ),
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
                          ActionChip(
                            label: Text('${entry.key} · ${entry.value}'),
                            onPressed: () => _browse(
                              '标签 · ${entry.key}',
                              _filtered.where(
                                (item) => item.tags.any(
                                  (tag) => tag.trim() == entry.key,
                                ),
                              ),
                            ),
                          ),
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
    final selected = collectionMemories(review.forMonth(_month), order: _order);
    final tag = stats.tagCounts.entries.firstOrNull;
    final peaks = review.peakMonths;
    return [
      Text(
        review.items.isEmpty
            ? '这一年，暂时还没有可回顾的记录。'
            : '${review.items.length} 条收藏更新，分布在 ${review.activeMonths} 个月里。${tag == null ? '' : '常用标签「${tag.key}」。'}',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (stats.ratedTotal > 0)
            Text(
              '最高 ${review.items.first.rate} 分',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          if (peaks.isNotEmpty)
            Text(
              peaks.length == 1
                  ? '${peaks.first} 月更新最活跃'
                  : '${peaks.length} 个月并列最活跃',
            ),
        ],
      ),
      const SizedBox(height: 16),
      Tooltip(
        message:
            '按收藏最后更新时间归档，不代表实际观看、游玩或完成日期；修改旧收藏可能改变归属年份。'
            '${_statistics.undatedTotal == 0 ? '' : '另有 ${_statistics.undatedTotal} 条无日期记录，仅计入收藏概览。'}',
        child: Row(
          children: [
            Icon(
              Icons.info_outline_rounded,
              size: 14,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '按收藏最后更新时间归档${_statistics.undatedTotal == 0 ? '' : ' · ${_statistics.undatedTotal} 条无日期记录未归档'}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      InsightMetrics(
        children: [
          _LedgerMetric(label: '收藏更新', value: '${stats.total}'),
          _LedgerMetric(label: '其中已评分', value: '${stats.ratedTotal}'),
          _LedgerMetric(
            label: '你的平均分',
            value: stats.ratedTotal == 0
                ? '—'
                : stats.averageRating.toStringAsFixed(1),
          ),
        ],
      ),
      if (review.items.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                label: Text('当前已完成 ${stats.completedTotal}'),
                onPressed: () => _browse(
                  '$_year 年 · 当前已完成',
                  review.items.where(
                    (item) => item.type == CollectionType.done,
                  ),
                ),
              ),
              ActionChip(
                label: Text('高分收藏 ${stats.highRatedTotal}'),
                onPressed: () => _browse(
                  '$_year 年 · 8–10 分',
                  review.items.where(
                    (item) =>
                        CollectionStatistics.isRated(item) && item.rate >= 8,
                  ),
                ),
              ),
              ActionChip(
                label: Text('留下短评 ${stats.commentedTotal}'),
                onPressed: () => _browse(
                  '$_year 年 · 短评',
                  review.items.where((item) => item.comment.trim().isNotEmpty),
                ),
              ),
            ],
          ),
        ),
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
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  DropdownButton<CollectionMemoryOrder>(
                    value: _order,
                    items: [
                      for (final order in CollectionMemoryOrder.values)
                        DropdownMenuItem(
                          value: order,
                          child: Text(order.label),
                        ),
                    ],
                    onChanged: (order) {
                      if (order != null) setState(() => _order = order);
                    },
                  ),
                  TextButton.icon(
                    onPressed: selected.isEmpty
                        ? null
                        : () => _browse(
                            '$_year 年${_month == null ? '' : ' $_month 月'}的收藏',
                            selected,
                          ),
                    icon: const Icon(Icons.search_rounded),
                    label: Text('查看全部 ${selected.length} 条'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
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
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns =
                      constraints.maxWidth >= 760 &&
                          MediaQuery.textScalerOf(context).scale(14) < 22
                      ? 2
                      : 1;
                  return Wrap(
                    spacing: 14,
                    runSpacing: 14,
                    children: [
                      for (final item in selected.take(10))
                        SizedBox(
                          width:
                              (constraints.maxWidth - (columns - 1) * 14) /
                              columns,
                          child: _MemoryCard(
                            item: item,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    SubjectRoute(subject: item.subject),
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 10),
              if (selected.length > 10)
                Text(
                  '预览 10 条 · 点击「查看全部」继续浏览和搜索',
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

class _LedgerHeading extends StatelessWidget {
  const _LedgerHeading({
    required this.title,
    required this.description,
    required this.action,
  });
  final String title;
  final String description;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          description,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth < 600
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [text, const SizedBox(height: 4), action],
            )
          : Row(
              children: [
                Expanded(child: text),
                const SizedBox(width: 20),
                action,
              ],
            ),
    );
  }
}

class _LedgerMetric extends StatelessWidget {
  const _LedgerMetric({required this.label, required this.value, this.detail});
  final String label;
  final String value;
  final String? detail;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(0, 10, 12, 12),
    decoration: BoxDecoration(
      border: Border(
        bottom: BorderSide(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: .6),
        ),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        if (detail != null) ...[
          const SizedBox(height: 4),
          Text(
            detail!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    ),
  );
}

class _MemoriesSheet extends StatefulWidget {
  const _MemoriesSheet({
    required this.title,
    required this.items,
    required this.order,
  });
  final String title;
  final List<UserCollection> items;
  final CollectionMemoryOrder order;

  @override
  State<_MemoriesSheet> createState() => _MemoriesSheetState();
}

class _MemoriesSheetState extends State<_MemoriesSheet> {
  final _search = TextEditingController();
  late CollectionMemoryOrder _order = widget.order;
  late List<UserCollection> _items = collectionMemories(
    widget.items,
    order: _order,
  );

  void _filter() => setState(() {
    _items = collectionMemories(
      widget.items,
      order: _order,
      query: _search.text,
    );
  });

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        18,
        0,
        18,
        MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  maxLines: keyboard ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: keyboard
                      ? Theme.of(context).textTheme.titleMedium
                      : Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: '关闭记录',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _search,
            onChanged: (_) => _filter(),
            decoration: InputDecoration(
              hintText: '搜索作品、标签或短评',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: '清空搜索',
                      onPressed: () {
                        _search.clear();
                        _filter();
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
          ),
          if (!keyboard)
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('${_items.length} / ${widget.items.length} 条记录'),
                DropdownButton<CollectionMemoryOrder>(
                  value: _order,
                  items: [
                    for (final order in CollectionMemoryOrder.values)
                      DropdownMenuItem(value: order, child: Text(order.label)),
                  ],
                  onChanged: (order) {
                    if (order != null) {
                      _order = order;
                      _filter();
                    }
                  },
                ),
              ],
            ),
          Expanded(
            child: _items.isEmpty
                ? const Center(child: Text('没有匹配的收藏记录'))
                : ListView.separated(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    itemCount: _items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    padding: const EdgeInsets.only(bottom: 18),
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      return _MemoryCard(
                        item: item,
                        showFullComment: true,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => SubjectRoute(subject: item.subject),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _Composition extends StatelessWidget {
  const _Composition({
    required this.statistics,
    required this.onType,
    required this.onStatus,
  });
  final CollectionStatistics statistics;
  final ValueChanged<SubjectType> onType;
  final ValueChanged<CollectionType> onStatus;
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
                onTap: () => onType(entry.key),
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
                  ActionChip(
                    label: Text(
                      '${_collectionStatusLabel(entry.key)} · ${entry.value}',
                    ),
                    onPressed: () => onStatus(entry.key),
                  ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _Ratings extends StatelessWidget {
  const _Ratings({required this.statistics, required this.onRating});
  final CollectionStatistics statistics;
  final ValueChanged<int> onRating;
  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          if (statistics.ratedTotal == 0)
            const Text('还没有评分。遇到喜欢的作品时，留下你的感受吧。')
          else ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '评分中位数 ${statistics.medianRating!.toStringAsFixed(1)} · 共 ${statistics.ratedTotal} 条评分',
              ),
            ),
            const SizedBox(height: 12),
            _RatingChart(
              counts: statistics.ratingDistribution,
              onRating: onRating,
            ),
          ],
          if (statistics.total > statistics.ratedTotal)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => onRating(0),
                child: Text(
                  '未评分 ${statistics.total - statistics.ratedTotal} 条 · 查看',
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class _RatingChart extends StatelessWidget {
  const _RatingChart({required this.counts, required this.onRating});
  final Map<int, int> counts;
  final ValueChanged<int> onRating;

  @override
  Widget build(BuildContext context) {
    final peak = counts.values.fold(1, (a, b) => a > b ? a : b);
    final scheme = Theme.of(context).colorScheme;
    final labelHeight = MediaQuery.textScalerOf(context).scale(12) * 1.6;
    return LayoutBuilder(
      builder: (context, constraints) {
        final minWidth =
            (MediaQuery.textScalerOf(context).scale(12) * 1.5 + 6) * 10;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: constraints.maxWidth < minWidth
                ? minWidth
                : constraints.maxWidth,
            height: 108 + labelHeight * 2,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var rating = 1; rating <= 10; rating++)
                  Expanded(
                    child: Tooltip(
                      message: '$rating 分 · ${counts[rating]} 条收藏',
                      child: Semantics(
                        label: '$rating 分，${counts[rating]} 条收藏',
                        button: counts[rating]! > 0,
                        child: InkWell(
                          onTap: counts[rating] == 0
                              ? null
                              : () => onRating(rating),
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                SizedBox(
                                  height: labelHeight,
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      counts[rating] == 0
                                          ? ''
                                          : '${counts[rating]}',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.labelSmall,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  height: counts[rating] == 0
                                      ? 2
                                      : 8 + 80 * counts[rating]! / peak,
                                  decoration: BoxDecoration(
                                    color: counts[rating] == 0
                                        ? scheme.outlineVariant
                                        : rating >= 8
                                        ? scheme.primary
                                        : scheme.primary.withValues(alpha: .45),
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  height: labelHeight,
                                  child: Text(
                                    '$rating',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelSmall,
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
    );
  }
}

class _DistributionRow extends StatelessWidget {
  const _DistributionRow({
    required this.label,
    required this.count,
    required this.total,
    this.icon,
    this.onTap,
  });
  final String label;
  final int count;
  final int total;
  final IconData? icon;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: Padding(
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
              Text(
                '$count · ${total == 0 ? 0 : (count / total * 100).round()}%',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              if (onTap != null)
                const Icon(Icons.chevron_right_rounded, size: 18),
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
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          counts[i] == 0 ? '' : '${counts[i]}',
                                          style: Theme.of(
                                            context,
                                          ).textTheme.labelSmall,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      height: 4 + 88 * counts[i] / maxCount,
                                      decoration: BoxDecoration(
                                        color: counts[i] == 0
                                            ? scheme.outlineVariant.withValues(
                                                alpha: .4,
                                              )
                                            : selected == i + 1
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
                                        '${i + 1}月',
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
  const _MemoryCard({
    required this.item,
    required this.onTap,
    this.showFullComment = false,
  });
  final UserCollection item;
  final VoidCallback onTap;
  final bool showFullComment;
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
                        CollectionStatistics.isRated(item)
                            ? '你评 ${item.rate} 分'
                            : '还未评分',
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
                  const SizedBox(height: 6),
                  Text(
                    item.updatedAt == null
                        ? '更新时间未知'
                        : '${item.updatedAt!.toLocal().year}.${item.updatedAt!.toLocal().month.toString().padLeft(2, '0')}.${item.updatedAt!.toLocal().day.toString().padLeft(2, '0')} 更新',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (item.comment.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      '“${item.comment.trim()}”',
                      maxLines: showFullComment ? null : 2,
                      overflow: showFullComment
                          ? TextOverflow.visible
                          : TextOverflow.ellipsis,
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
