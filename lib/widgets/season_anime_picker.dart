import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/bangumi_models.dart';
import '../models/schedule_models.dart';
import '../state/schedule_controller.dart';
import '../state/session_controller.dart';
import 'subject_widgets.dart';

Future<void> showSeasonAnimePicker(
  BuildContext context, {
  required SeasonKey season,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  constraints: const BoxConstraints(maxWidth: 820),
  builder: (_) => FractionallySizedBox(
    heightFactor: .9,
    child: SeasonAnimePicker(season: season),
  ),
);

class SeasonAnimePicker extends ConsumerStatefulWidget {
  const SeasonAnimePicker({super.key, required this.season});
  final SeasonKey season;
  @override
  ConsumerState<SeasonAnimePicker> createState() => _SeasonAnimePickerState();
}

class _SeasonAnimePickerState extends ConsumerState<SeasonAnimePicker> {
  static const _pageSize = 24;
  final _subjects = <int, Subject>{};
  final _selected = <int>{};
  final _offsets = <int, int>{};
  final _finishedMonths = <int>{};
  final _days = <int, int>{};
  bool _loading = false,
      _saving = false,
      _calendarLoading = true,
      _calendarFailed = false;
  bool _automaticDays = true;
  String? _error, _message;
  late final int? _ownerId;
  late final ScheduleController _schedule;

  @override
  void initState() {
    super.initState();
    _ownerId = ref.read(sessionProvider).user?.id;
    _schedule = ref.read(scheduleProvider.notifier);
    unawaited(_load());
    unawaited(_loadCalendar());
  }

  bool get _current =>
      mounted &&
      ref.read(sessionProvider).user?.id == _ownerId &&
      identical(ref.read(scheduleProvider.notifier), _schedule) &&
      ref.read(scheduleProvider).season == widget.season;

  Future<void> _loadCalendar() async {
    setState(() {
      _calendarLoading = true;
      _calendarFailed = false;
    });
    try {
      final calendar = await ref
          .read(bangumiApiProvider)
          .getCalendar()
          .timeout(const Duration(seconds: 8));
      if (!_current) return;
      _days.clear();
      for (final day in calendar) {
        if (day.weekday < 1 || day.weekday > 7) continue;
        for (final subject in day.subjects) {
          _days[subject.id] = day.weekday;
        }
      }
    } catch (_) {
      if (mounted) _calendarFailed = true;
    } finally {
      if (mounted) setState(() => _calendarLoading = false);
    }
  }

  Future<void> _load() async {
    if (_loading || _finishedMonths.length == 3) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final months = [
      for (var i = 0; i < 3; i++) widget.season.startMonth + i,
    ].where((month) => !_finishedMonths.contains(month)).toList();
    try {
      final api = ref.read(bangumiApiProvider);
      // The public API filters a month, not a quarter. Page each of all three months.
      final pages = await Future.wait([
        for (final month in months)
          api.browseSubjects(
            type: SubjectType.anime,
            year: widget.season.year,
            month: month,
            limit: _pageSize,
            offset: _offsets[month] ?? 0,
          ),
      ]);
      if (!_current) return;
      for (var i = 0; i < months.length; i++) {
        final page = pages[i];
        _offsets[months[i]] = (_offsets[months[i]] ?? 0) + page.length;
        if (page.length < _pageSize) _finishedMonths.add(months[i]);
        for (final subject in page) {
          if (subject.id > 0 && subject.type == SubjectType.anime) {
            _subjects[subject.id] = subject;
          }
        }
      }
    } catch (_) {
      if (mounted) _error = '新番列表加载失败，请重试；已选作品会保留。';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _add() async {
    if (_saving || !_current || _selected.isEmpty) return;
    setState(() {
      _saving = true;
      _message = null;
    });
    final result = await _schedule.addBatchToSeason(
      [for (final id in _selected) _subjects[id]!],
      widget.season,
      allowed: () => _current,
      weekdays: _automaticDays ? Map.of(_days) : const {},
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      _selected.removeAll({...result.added, ...result.existing});
      _message =
          result.error ??
          (result.stopped
              ? '账号或季度已变化，请重新打开'
              : '已加入 ${result.added.length} 部${result.existing.isEmpty ? '' : ' · ${result.existing.length} 部已在表中'}${result.warning == null ? '' : '\n${result.warning}'}');
    });
  }

  @override
  Widget build(BuildContext context) {
    final schedule = ref.watch(scheduleProvider);
    ref.watch(sessionProvider.select((s) => s.user?.id));
    final current = _current;
    final existing = schedule.schedule.items.map((e) => e.subjectId).toSet();
    final selected = _selected.where((id) => !existing.contains(id)).length;
    final items = _subjects.values.toList()
      ..sort((a, b) {
        final score = b.score.compareTo(a.score);
        return score == 0 ? a.id.compareTo(b.id) : score;
      });
    final locked =
        _saving ||
        schedule.saving ||
        schedule.loading ||
        schedule.readFailed ||
        !current;
    return PopScope(
      canPop: !_saving,
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '挑选本季新番',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    tooltip: '关闭新番挑选',
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: !current
                  ? const Center(child: Text('账号或季度已变化，请关闭后重新打开'))
                  : ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        Text(
                          '加入 ${widget.season.label} · ${widget.season.startMonth}—${widget.season.startMonth + 2} 月',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const Text('只加入本机新番表；放送日可在表中调整。'),
                        Wrap(
                          spacing: 8,
                          children: [
                            ChoiceChip(
                              label: const Text('按放送日安排'),
                              selected: _automaticDays,
                              onSelected: locked
                                  ? null
                                  : (_) =>
                                        setState(() => _automaticDays = true),
                            ),
                            ChoiceChip(
                              label: const Text('全部放入待安排'),
                              selected: !_automaticDays,
                              onSelected: locked
                                  ? null
                                  : (_) =>
                                        setState(() => _automaticDays = false),
                            ),
                          ],
                        ),
                        if (_automaticDays)
                          Text(
                            _calendarLoading
                                ? '正在查询官方放送日…'
                                : _calendarFailed
                                ? '放送日暂不可用，加入的作品将放入待安排。'
                                : '按当前官方放送日安排，未收录的作品放入待安排。',
                          ),
                        if (_calendarFailed && !_calendarLoading)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              onPressed: locked ? null : _loadCalendar,
                              child: const Text('重试放送日'),
                            ),
                          ),
                        Wrap(
                          spacing: 8,
                          children: [
                            TextButton(
                              onPressed: locked || items.isEmpty
                                  ? null
                                  : () => setState(() {
                                      _selected.addAll(
                                        _subjects.keys.where(
                                          (id) => !existing.contains(id),
                                        ),
                                      );
                                    }),
                              child: const Text('全选已加载'),
                            ),
                            TextButton(
                              onPressed: locked || _selected.isEmpty
                                  ? null
                                  : () => setState(_selected.clear),
                              child: const Text('清空选择'),
                            ),
                          ],
                        ),
                        for (final subject in items)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Material(
                              color: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(12),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: locked || existing.contains(subject.id)
                                    ? null
                                    : () => setState(() {
                                        if (!_selected.add(subject.id)) {
                                          _selected.remove(subject.id);
                                        }
                                      }),
                                child: Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Row(
                                    children: [
                                      SubjectCover(
                                        subject: subject,
                                        width: 44,
                                        height: 62,
                                        borderRadius: 6,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(subject.displayName),
                                            Text(
                                              [
                                                if (subject.date.isNotEmpty)
                                                  subject.date,
                                                subject.score > 0
                                                    ? '${subject.score.toStringAsFixed(1)} 分'
                                                    : '暂无评分',
                                                if (existing.contains(
                                                  subject.id,
                                                ))
                                                  '已在表中',
                                              ].join(' · '),
                                              style: Theme.of(
                                                context,
                                              ).textTheme.bodySmall,
                                            ),
                                          ],
                                        ),
                                      ),
                                      Checkbox(
                                        value:
                                            existing.contains(subject.id) ||
                                            _selected.contains(subject.id),
                                        semanticLabel:
                                            existing.contains(subject.id)
                                            ? '${subject.displayName}，已在表中'
                                            : '选择 ${subject.displayName}',
                                        onChanged:
                                            locked ||
                                                existing.contains(subject.id)
                                            ? null
                                            : (value) => setState(() {
                                                if (value == true) {
                                                  _selected.add(subject.id);
                                                } else {
                                                  _selected.remove(subject.id);
                                                }
                                              }),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (_loading)
                          const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                        if (_error != null) Text(_error!),
                        if (!_loading && _error != null)
                          TextButton(
                            onPressed: _load,
                            child: const Text('重试列表'),
                          ),
                        if (!_loading &&
                            _error == null &&
                            _finishedMonths.length < 3)
                          TextButton(
                            onPressed: _load,
                            child: const Text('加载更多新番'),
                          ),
                        if (!_loading && _error == null && items.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text('这个季度暂未查到新番，可稍后重试或用搜索加入。'),
                          ),
                      ],
                    ),
            ),
            if (current && _message != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Text(_message!),
              ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(child: Text('已选 $selected 部')),
                  const SizedBox(width: 8),
                  Flexible(
                    child: FilledButton.icon(
                      onPressed:
                          locked ||
                              selected == 0 ||
                              (_automaticDays && _calendarLoading)
                          ? null
                          : _add,
                      icon: const Icon(Icons.playlist_add),
                      label: Text(_saving ? '加入中…' : '加入新番表'),
                    ),
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
