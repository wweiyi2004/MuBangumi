import '../widgets/score_date_range_selector.dart';
import '../widgets/score_chart_controls.dart';
import '../widgets/image_share_sheet.dart';
import '../core/theme/anime_icon.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/network/netaba_api.dart';
import '../features/score_comparison/application/score_comparison_controller.dart';
import '../models/bangumi_models.dart';
import '../state/session_controller.dart';
import '../widgets/score_comparison_chart.dart';

class ScoreComparisonPage extends ConsumerStatefulWidget {
  const ScoreComparisonPage({
    super.key,
    this.initial = const [],
    this.embedded = false,
  });
  final List<Subject> initial;
  final bool embedded;
  @override
  ConsumerState<ScoreComparisonPage> createState() =>
      _ScoreComparisonPageState();
}

class _ScoreComparisonPageState extends ConsumerState<ScoreComparisonPage> {
  late final ScoreComparisonController _controller;
  int _days = 0;
  ScoreChartAxes _axes = const ScoreChartAxes();
  static const _colors = [
    Color(0xFFA64B58),
    Color(0xFF377CC8),
    Color(0xFF219B80),
    Color(0xFFBD771D),
    Color(0xFF8254CA),
    Color(0xFFCD5C3D),
  ];
  @override
  void initState() {
    super.initState();
    _controller = ScoreComparisonController(
      (id) => ref.read(netabaApiProvider).getSubjectHistory(id),
    )..addListener(_changed);
    ref.listenManual(
      sessionProvider.select((state) => state.user?.id),
      (_, _) => _controller.reset(),
    );
    Future<void>.microtask(() {
      if (!mounted) return;
      for (final subject in widget.initial.take(6)) {
        unawaited(_controller.add(subject));
      }
    });
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _choose() async {
    final owner = ref.read(sessionProvider).user?.id;
    final selected = _controller.entries
        .map((entry) => entry.subject.id)
        .toSet();
    final own = ref
        .read(sessionProvider)
        .collections
        .map((item) => item.subject)
        .where((subject) => subject.type == SubjectType.anime)
        .toList();
    final subject = await showModalBottomSheet<Subject>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) =>
          _SubjectPicker(owned: own, selected: selected, owner: owner),
    );
    if (!mounted ||
        subject == null ||
        owner != ref.read(sessionProvider).user?.id) {
      return;
    }
    if (_controller.entries.length >= 6) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('最多对比 6 部作品，请先移除一部')));
      return;
    }
    unawaited(_controller.add(subject));
  }

  @override
  Widget build(BuildContext context) {
    final entries = _controller.entries;
    final series = [
      for (final entry in entries)
        entry.history?.scoreSeries(maxPoints: 0) ?? const [],
    ];
    final dates =
        series.expand((points) => points.map((point) => point.at)).toList()
          ..sort();
    final since = _days == 0 || dates.isEmpty
        ? null
        : dates.last.subtract(Duration(days: _days));
    final lines = [
      for (var i = 0; i < entries.length; i++)
        ScoreComparisonLine(
          entries[i].subject.displayName,
          series[i],
          _colors[i],
        ),
    ];
    final visibleAxes = ScoreChartAxes(
      minimum: _axes.minimum,
      maximum: _axes.maximum,
      start: _axes.start ?? since,
      end:
          _axes.end ??
          ((_axes.start != null || since != null) && dates.isNotEmpty
              ? dates.last
              : null),
    );
    return Scaffold(
      appBar: widget.embedded
          ? null
          : AppBar(
              title: const Text('评分历史对比'),
              actions: [
                IconButton(
                  tooltip: '添加对比作品',
                  onPressed: _choose,
                  icon: const AnimeIcon(Icons.add_rounded),
                ),
              ],
            ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1040),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('数据来源：netaba.re'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final days in [0, 30, 90, 365])
                      ChoiceChip(
                        label: Text(days == 0 ? '全部时间' : '近 $days 天'),
                        selected:
                            _days == days &&
                            (days != 0 ||
                                (_axes.start == null && _axes.end == null)),
                        onSelected: (_) => setState(() {
                          _days = days;
                          _axes = ScoreChartAxes(
                            minimum: _axes.minimum,
                            maximum: _axes.maximum,
                          );
                        }),
                      ),
                    ActionChip(
                      avatar: const AnimeIcon(
                        Icons.ios_share_rounded,
                        size: 18,
                      ),
                      label: const Text('分享对比图'),
                      onPressed:
                          lines.any(
                            (line) => line.points.any(visibleAxes.includes),
                          )
                          ? () => showImageShareSheet(
                              context,
                              title: '评分历史对比',
                              filename: 'MuBangumi-score-comparison.png',
                              subtitle: '数据来源：netaba.re · 圆点标记起点、最新、最高和最低的实际记录',
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ScoreComparisonChart(
                                    lines: lines,
                                    axes: visibleAxes,
                                    markKeyPoints: true,
                                  ),
                                  ScoreChartKeyPoints(
                                    lines: lines,
                                    axes: visibleAxes,
                                  ),
                                ],
                              ),
                            )
                          : null,
                    ),
                    ActionChip(
                      avatar: const AnimeIcon(Icons.add_rounded, size: 18),
                      label: const Text('选择作品'),
                      onPressed: _choose,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ScoreChartControls(
                  axes: visibleAxes,
                  points: lines.expand((line) => line.points).toList(),
                  onChanged: (axes) => setState(() {
                    _axes = axes;
                    if (axes.start != null) _days = 0;
                  }),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: ScoreComparisonChart(
                      lines: lines,
                      axes: visibleAxes,
                    ),
                  ),
                ),
                if (dates.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: ScoreDateRangeSelector(
                      dates: dates,
                      start: visibleAxes.start,
                      end: visibleAxes.end,
                      onChanged: (range) => setState(() {
                        _days = 0;
                        _axes = ScoreChartAxes(
                          start: range.start,
                          end: range.end,
                        );
                      }),
                    ),
                  ),
                const SizedBox(height: 12),
                for (var i = 0; i < entries.length; i++)
                  ListTile(
                    leading: AnimeIcon(
                      Icons.circle,
                      color: _colors[i],
                      size: 12,
                    ),
                    title: Text(entries[i].subject.displayName),
                    subtitle: Text(
                      entries[i].loading
                          ? '正在读取历史…'
                          : entries[i].error ??
                                (series[i].isEmpty
                                    ? '数据源暂无历史评分记录'
                                    : series[i].length == 1
                                    ? '仅有一个样本，暂不能判断趋势'
                                    : '${series[i].length} 个历史样本'),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (entries[i].error != null)
                          IconButton(
                            tooltip: '重试此作品',
                            onPressed: () =>
                                _controller.reload(entries[i].subject.id),
                            icon: const AnimeIcon(Icons.refresh_rounded),
                          ),
                        IconButton(
                          tooltip: '移除对比作品',
                          onPressed: () =>
                              _controller.remove(entries[i].subject.id),
                          icon: const AnimeIcon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                if (entries.isEmpty)
                  FilledButton.tonalIcon(
                    onPressed: _choose,
                    icon: const AnimeIcon(Icons.add_chart_rounded),
                    label: const Text('从收藏或搜索中添加作品'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SubjectPicker extends ConsumerStatefulWidget {
  const _SubjectPicker({
    required this.owned,
    required this.selected,
    required this.owner,
  });
  final int? owner;
  final List<Subject> owned;
  final Set<int> selected;
  @override
  ConsumerState<_SubjectPicker> createState() => _SubjectPickerState();
}

class _SubjectPickerState extends ConsumerState<_SubjectPicker> {
  List<Subject>? _results;
  String _query = '';
  bool _loading = false;
  String? _error;
  int _request = 0;
  Future<void> _search(String value) async {
    final request = ++_request;
    final text = value.trim();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(bangumiApiProvider);
      final id = int.tryParse(text);
      final results = text.isEmpty
          ? widget.owned
          : id != null
          ? [await api.getSubject(id)]
          : await api.searchSubjects(
              text,
              subjectType: SubjectType.anime,
              limit: 20,
            );
      if (mounted && request == _request) setState(() => _results = results);
    } catch (_) {
      if (mounted && request == _request) setState(() => _error = '搜索失败，请重试');
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(sessionProvider.select((state) => state.user?.id)) !=
        widget.owner) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('账号已变化，返回重新选择'),
          ),
        ),
      );
    }
    final subjects =
        _results ??
        widget.owned
            .where(
              (subject) => subject.displayName.toLowerCase().contains(
                _query.toLowerCase(),
              ),
            )
            .toList();
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .8,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                onChanged: (value) => setState(() {
                  _request++;
                  _loading = false;
                  _query = value;
                  _results = null;
                  _error = null;
                }),
                onSubmitted: _search,
                decoration: InputDecoration(
                  hintText: '筛选收藏，或搜索作品名 / 条目 ID',
                  prefixIcon: const AnimeIcon(Icons.search_rounded),
                  suffixIcon: IconButton(
                    tooltip: '搜索全部动画',
                    onPressed: () => _search(_query),
                    icon: const AnimeIcon(Icons.travel_explore_rounded),
                  ),
                ),
              ),
            ),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null) Text(_error!),
            Expanded(
              child: ListView.builder(
                itemCount: subjects.length,
                itemBuilder: (context, index) => ListTile(
                  title: Text(subjects[index].displayName),
                  subtitle: Text(subjects[index].name),
                  trailing: widget.selected.contains(subjects[index].id)
                      ? const AnimeIcon(Icons.check_rounded)
                      : null,
                  enabled: !widget.selected.contains(subjects[index].id),
                  onTap: () => Navigator.pop(context, subjects[index]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
