import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/bangumi_models.dart';
import '../models/schedule_models.dart';
import '../state/rss_controller.dart';
import '../state/schedule_controller.dart';
import '../state/session_controller.dart';
import '../widgets/schedule_export_poster.dart';
import '../widgets/schedule_reminder_sheet.dart';
import '../widgets/subject_widgets.dart';
import '../widgets/readable_subject_title.dart';
import 'rss_sheets.dart';
import 'subject_detail_screen.dart';

/// Seasonal schedule as a WakeUp-style week grid (Mon–Sun always visible).
/// Subject info from Bangumi search; placement is local-only.
class SchedulePage extends ConsumerWidget {
  const SchedulePage({super.key});

  /// Wider chrome (FAB label, larger header) only — grid itself always fits 7 days.
  static const double wideBreakpoint = 720;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(scheduleProvider);
    final collections = ref.watch(
      sessionProvider.select((value) => value.collections),
    );
    final progressMap = {for (final item in collections) item.subjectId: item};
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= wideBreakpoint;

    final rss = ref.watch(rssProvider);

    ref.listen(scheduleProvider, (previous, next) {
      final message = next.message;
      if (message != null &&
          message.isNotEmpty &&
          message != previous?.message) {
        showAppMessage(context, message);
        ref.read(scheduleProvider.notifier).clearMessage();
      }
    });
    ref.listen(rssProvider, (previous, next) {
      final message = next.message;
      if (message != null &&
          message.isNotEmpty &&
          message != previous?.message) {
        showAppMessage(context, message);
        ref.read(rssProvider.notifier).clearMessage();
      }
    });

    return Scaffold(
      floatingActionButton: isWide
          ? FloatingActionButton.extended(
              onPressed: () => _openSearchAddSheet(context),
              icon: const Icon(Icons.search_rounded),
              label: const Text('搜索加入'),
            )
          : FloatingActionButton(
              onPressed: () => _openSearchAddSheet(context),
              tooltip: '搜索加入',
              child: const Icon(Icons.search_rounded),
            ),
      body: state.loading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                const _RssAutoRefresh(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        isWide ? 16 : 12,
                        isWide ? 18 : 10,
                        4,
                        8,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (Navigator.canPop(context)) ...[
                                IconButton(
                                  visualDensity: isWide
                                      ? VisualDensity.standard
                                      : VisualDensity.compact,
                                  tooltip: '返回',
                                  onPressed: () => Navigator.maybePop(context),
                                  icon: const Icon(Icons.arrow_back_rounded),
                                ),
                                SizedBox(width: isWide ? 6 : 2),
                              ],
                              Expanded(
                                child: Text(
                                  '新番表',
                                  style: isWide
                                      ? Theme.of(
                                          context,
                                        ).textTheme.headlineLarge
                                      : Theme.of(
                                          context,
                                        ).textTheme.headlineMedium,
                                ),
                              ),
                              Flexible(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerRight,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        visualDensity: isWide
                                            ? VisualDensity.standard
                                            : VisualDensity.compact,
                                        tooltip: '导出图片',
                                        onPressed: () => unawaited(
                                          showScheduleExportDialog(
                                            context,
                                            schedule: state.schedule,
                                          ),
                                        ),
                                        icon: const Icon(Icons.image_outlined),
                                      ),
                                      IconButton(
                                        visualDensity: isWide
                                            ? VisualDensity.standard
                                            : VisualDensity.compact,
                                        tooltip: '更新提醒',
                                        onPressed: () =>
                                            showRssUpdatesSheet(context),
                                        icon: Badge(
                                          isLabelVisible: rss.totalUnread > 0,
                                          label: Text(
                                            rss.totalUnread > 99
                                                ? '99+'
                                                : '${rss.totalUnread}',
                                          ),
                                          child: const Icon(
                                            Icons.notifications_outlined,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        visualDensity: isWide
                                            ? VisualDensity.standard
                                            : VisualDensity.compact,
                                        tooltip: rss.refreshing
                                            ? '检查中…'
                                            : '检查更新',
                                        onPressed: rss.refreshing
                                            ? null
                                            : () => ref
                                                  .read(rssProvider.notifier)
                                                  .refreshAll(force: true),
                                        icon: rss.refreshing
                                            ? const SizedBox(
                                                width: 22,
                                                height: 22,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              )
                                            : const Icon(Icons.sync_rounded),
                                      ),
                                      IconButton(
                                        visualDensity: isWide
                                            ? VisualDensity.standard
                                            : VisualDensity.compact,
                                        tooltip: '更新源 RSS',
                                        onPressed: () =>
                                            showRssSourcesSheet(context),
                                        icon: const Icon(
                                          Icons.rss_feed_rounded,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isWide
                                ? '搜索加番 · 拖拽改期 · 导出海报 · 种子站 RSS 提醒'
                                : '拖拽改期 · 导出图片 · RSS 角标',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                              fontSize: isWide ? null : 13,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _SeasonPicker(
                            season: state.season,
                            knownSeasons: state.knownSeasons,
                            onChanged: (season) => ref
                                .read(scheduleProvider.notifier)
                                .setSeason(season),
                            onCreate: () => _createSeasonDialog(context, ref),
                            onDeleteCurrent: state.schedule.items.isEmpty
                                ? () => ref
                                      .read(scheduleProvider.notifier)
                                      .deleteCurrentSeason()
                                : null,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '共 ${state.schedule.items.length} 部 · '
                            '已排 ${state.schedule.items.where((e) => e.isScheduled).length} 部'
                            ' · RSS 未读 ${rss.totalUnread}',
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
                    Expanded(
                      child: state.schedule.items.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(24),
                              child: EmptyState(
                                icon: Icons.calendar_view_week_rounded,
                                title: '本季课表还是空的',
                                message: '点右下角搜索加番；加源后可在格子 ⋮ 里绑定 RSS 提醒。',
                              ),
                            )
                          : _ScheduleBoard(
                              schedule: state.schedule,
                              progressMap: progressMap,
                              compactChrome: !isWide,
                              season: state.season,
                              unreadBySubject: rss.unreadBySubject,
                            ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  Future<void> _openSearchAddSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 720),
      builder: (sheetContext) => const _SearchAddSheet(),
    );
  }
}

/// Quietly refresh RSS when schedule opens and data looks stale.
class _RssAutoRefresh extends ConsumerStatefulWidget {
  const _RssAutoRefresh();

  @override
  ConsumerState<_RssAutoRefresh> createState() => _RssAutoRefreshState();
}

class _RssAutoRefreshState extends ConsumerState<_RssAutoRefresh> {
  var _didRun = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeRefresh());
  }

  void _maybeRefresh() {
    if (_didRun || !mounted) return;
    final rss = ref.read(rssProvider);
    if (!rss.loaded || rss.refreshing) return;
    if (rss.bindings.isEmpty || rss.sources.isEmpty) return;
    final stale = rss.sources.any((source) {
      final last = source.lastFetchAt;
      if (last == null) return true;
      return DateTime.now().difference(last) > const Duration(minutes: 30);
    });
    if (!stale) return;
    _didRun = true;
    unawaited(ref.read(rssProvider.notifier).refreshAll());
  }

  @override
  Widget build(BuildContext context) {
    // Re-try once sources/bindings finish loading.
    ref.listen(rssProvider, (previous, next) {
      if (!_didRun && next.loaded) _maybeRefresh();
    });
    return const SizedBox.shrink();
  }
}

Future<void> _createSeasonDialog(BuildContext context, WidgetRef ref) async {
  final current = ref.read(scheduleProvider).season;
  var year = current.year;
  var quarter = current.quarter;
  final created = await showDialog<SeasonKey>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setLocal) {
          return AlertDialog(
            title: const Text('新建 / 打开季度表'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: year,
                        decoration: const InputDecoration(labelText: '年份'),
                        items: [
                          for (var y = DateTime.now().year + 2; y >= 2000; y--)
                            DropdownMenuItem(value: y, child: Text('$y')),
                        ],
                        onChanged: (value) {
                          if (value != null) setLocal(() => year = value);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: quarter,
                        decoration: const InputDecoration(labelText: '季度'),
                        items: const [
                          DropdownMenuItem(value: 0, child: Text('冬季（1月）')),
                          DropdownMenuItem(value: 1, child: Text('春季（4月）')),
                          DropdownMenuItem(value: 2, child: Text('夏季（7月）')),
                          DropdownMenuItem(value: 3, child: Text('秋季（10月）')),
                        ],
                        onChanged: (value) {
                          if (value != null) setLocal(() => quarter = value);
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(
                  context,
                  SeasonKey(year: year, quarter: quarter),
                ),
                child: const Text('打开'),
              ),
            ],
          );
        },
      );
    },
  );
  if (created == null) return;
  await ref.read(scheduleProvider.notifier).createSeason(created);
}

class _SearchAddSheet extends ConsumerStatefulWidget {
  const _SearchAddSheet();

  @override
  ConsumerState<_SearchAddSheet> createState() => _SearchAddSheetState();
}

class _SearchAddSheetState extends ConsumerState<_SearchAddSheet> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<Subject> _results = const [];
  bool _loading = false;
  String? _error;
  int _requestId = 0;
  SubjectType _type = SubjectType.anime;
  int? _weekday = DateTime.now().weekday;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      unawaited(_search(value.trim()));
    });
    setState(() {});
  }

  Future<void> _search(String keyword) async {
    if (keyword.isEmpty) {
      setState(() {
        _results = const [];
        _loading = false;
        _error = null;
      });
      return;
    }
    final requestId = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await ref
          .read(bangumiApiProvider)
          .searchSubjects(keyword, subjectType: _type, limit: 20);
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _add(Subject subject) async {
    await ref
        .read(scheduleProvider.notifier)
        .addSubject(subject, weekday: _weekday);
    // Keep sheet open so multiple titles can be added in one search session.
  }

  @override
  Widget build(BuildContext context) {
    final schedule = ref.watch(scheduleProvider).schedule;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Text(
              '搜索 Bangumi 加入新番表',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: _onQueryChanged,
              onSubmitted: (value) {
                // Enter submits immediately; cancel the pending debounce so
                // the same keyword is not searched twice.
                _debounce?.cancel();
                unawaited(_search(value.trim()));
              },
              decoration: InputDecoration(
                hintText: _type == SubjectType.anime
                    ? '搜索动画名，例如：迷宫饭'
                    : '搜索${_type.label}',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _controller.clear();
                          _onQueryChanged('');
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text('类型', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(width: 8),
                for (final type in const [
                  SubjectType.anime,
                  SubjectType.real,
                ]) ...[
                  ChoiceChip(
                    label: Text(type.label),
                    selected: _type == type,
                    onSelected: (_) {
                      setState(() => _type = type);
                      unawaited(_search(_controller.text.trim()));
                    },
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text('放到', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('待安排'),
                  selected: _weekday == null,
                  onSelected: (_) => setState(() => _weekday = null),
                ),
                const SizedBox(width: 8),
                for (
                  var day = DateTime.monday;
                  day <= DateTime.sunday;
                  day++
                ) ...[
                  ChoiceChip(
                    label: Text(weekdayLabel(day)),
                    selected: _weekday == day,
                    onSelected: (_) => setState(() => _weekday = day),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? EmptyState(
                    icon: Icons.cloud_off_outlined,
                    title: '搜索失败',
                    message: _error!,
                    action: FilledButton.tonal(
                      onPressed: () => _search(_controller.text.trim()),
                      child: const Text('重试'),
                    ),
                  )
                : _controller.text.trim().isEmpty
                ? const EmptyState(
                    icon: Icons.search_rounded,
                    title: '搜索作品加入课表',
                    message: '输入关键词后点选结果；可先选周几，或先放进待安排。',
                  )
                : _results.isEmpty
                ? const EmptyState(
                    icon: Icons.search_off_rounded,
                    title: '没有搜索结果',
                    message: '试试更短的关键词，或切换动画/三次元。',
                  )
                : ListView.separated(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: _results.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final subject = _results[index];
                      final exists = schedule.containsSubject(subject.id);
                      return ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        tileColor: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        leading: SubjectCover(
                          subject: subject,
                          width: 44,
                          height: 62,
                          borderRadius: 8,
                        ),
                        title: ReadableSubjectTitle(
                          subject.displayName,
                          maxLines: 1,
                        ),
                        subtitle: Text(
                          [
                            if (subject.score > 0)
                              subject.score.toStringAsFixed(1),
                            if (subject.date.isNotEmpty) subject.date,
                            if (subject.episodeCount > 0)
                              '${subject.episodeCount} 话',
                          ].join(' · '),
                        ),
                        trailing: exists
                            ? Chip(
                                label: const Text('已在表中'),
                                visualDensity: VisualDensity.compact,
                                side: BorderSide.none,
                                backgroundColor: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHigh,
                              )
                            : FilledButton.tonalIcon(
                                onPressed: () => unawaited(_add(subject)),
                                icon: const Icon(Icons.add_rounded, size: 18),
                                label: Text(
                                  _weekday == null
                                      ? '待安排'
                                      : weekdayLabel(_weekday!),
                                ),
                              ),
                        onTap: exists ? null : () => unawaited(_add(subject)),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _SeasonPicker extends StatelessWidget {
  const _SeasonPicker({
    required this.season,
    required this.knownSeasons,
    required this.onChanged,
    required this.onCreate,
    this.onDeleteCurrent,
  });

  final SeasonKey season;
  final List<SeasonKey> knownSeasons;
  final ValueChanged<SeasonKey> onChanged;
  final VoidCallback onCreate;
  final VoidCallback? onDeleteCurrent;

  @override
  Widget build(BuildContext context) {
    // Nearby seasons as quick picks + anything the user has created/opened.
    final now = SeasonKey.current();
    final quick = <SeasonKey>[];
    var cursor = now.quarter == 0
        ? SeasonKey(year: now.year - 1, quarter: 3)
        : SeasonKey(year: now.year, quarter: now.quarter - 1);
    for (var i = 0; i < 6; i++) {
      quick.add(cursor);
      cursor = cursor.quarter == 3
          ? SeasonKey(year: cursor.year + 1, quarter: 0)
          : SeasonKey(year: cursor.year, quarter: cursor.quarter + 1);
    }
    final map = <String, SeasonKey>{
      for (final key in [...quick, ...knownSeasons, season]) key.id: key,
    };
    final list = map.values.toList()
      ..sort((a, b) {
        final byYear = b.year.compareTo(a.year);
        if (byYear != 0) return byYear;
        return b.quarter.compareTo(a.quarter);
      });

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          ActionChip(
            avatar: const Icon(Icons.add_rounded, size: 18),
            label: const Text('新建表'),
            onPressed: onCreate,
          ),
          const SizedBox(width: 8),
          for (final option in list) ...[
            ChoiceChip(
              label: Text(option.label),
              selected: option == season,
              onSelected: (_) => onChanged(option),
            ),
            const SizedBox(width: 8),
          ],
          if (onDeleteCurrent != null) ...[
            ActionChip(
              avatar: Icon(
                Icons.delete_outline_rounded,
                size: 18,
                color: Theme.of(context).colorScheme.error,
              ),
              label: Text(
                '删空表',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onPressed: onDeleteCurrent,
            ),
          ],
        ],
      ),
    );
  }
}

class _DragPayload {
  const _DragPayload(this.item);
  final ScheduleItem item;
}

/// Unscheduled strip + week grid, with drag-and-drop within the season.
class _ScheduleBoard extends ConsumerStatefulWidget {
  const _ScheduleBoard({
    required this.schedule,
    required this.progressMap,
    required this.compactChrome,
    required this.season,
    required this.unreadBySubject,
  });

  final SeasonSchedule schedule;
  final Map<int, UserCollection> progressMap;
  final bool compactChrome;
  final SeasonKey season;
  final Map<int, int> unreadBySubject;

  @override
  ConsumerState<_ScheduleBoard> createState() => _ScheduleBoardState();
}

class _ScheduleBoardState extends ConsumerState<_ScheduleBoard> {
  bool _dragging = false;

  void _setDragging(bool value) {
    if (_dragging == value) return;
    setState(() => _dragging = value);
  }

  Future<void> _place(int subjectId, {int? weekday, int? insertIndex}) async {
    await ref
        .read(scheduleProvider.notifier)
        .moveItem(subjectId, weekday: weekday, insertIndex: insertIndex);
  }

  Future<void> _remove(int subjectId) async {
    await ref.read(scheduleProvider.notifier).removeSubject(subjectId);
  }

  @override
  Widget build(BuildContext context) {
    final schedule = widget.schedule;
    final progressMap = widget.progressMap;
    final compact = widget.compactChrome;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Always show pool target while dragging, even if currently empty.
        if (schedule.unscheduled.isNotEmpty || _dragging)
          _UnscheduledBar(
            items: schedule.unscheduled,
            progressMap: progressMap,
            compact: compact,
            dragging: _dragging,
            unreadBySubject: widget.unreadBySubject,
            season: widget.season,
            onDragStarted: () => _setDragging(true),
            onDragEnded: () => _setDragging(false),
            onAccept: (payload, index) => _place(
              payload.item.subjectId,
              weekday: null,
              insertIndex: index,
            ),
            onOpen: (item) => _openSubject(context, item),
            onMove: (item, day) => _place(item.subjectId, weekday: day),
            onRemove: (item) => _remove(item.subjectId),
          ),
        Expanded(
          child: _CourseTable(
            schedule: schedule,
            progressMap: progressMap,
            dragging: _dragging,
            unreadBySubject: widget.unreadBySubject,
            season: widget.season,
            onDragStarted: () => _setDragging(true),
            onDragEnded: () => _setDragging(false),
            onAccept: (payload, weekday, slot) => _place(
              payload.item.subjectId,
              weekday: weekday,
              insertIndex: slot,
            ),
            onOpen: (item) => _openSubject(context, item),
            onMove: (item, day) => _place(item.subjectId, weekday: day),
            onRemove: (item) => _remove(item.subjectId),
          ),
        ),
        // Drag-to-delete zone (fixes “找不到删除” on dense phones).
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: _dragging
              ? _DeleteDropZone(
                  key: const ValueKey('delete-zone'),
                  onAccept: (payload) => _remove(payload.item.subjectId),
                )
              : const SizedBox(key: ValueKey('delete-zone-off'), height: 0),
        ),
      ],
    );
  }
}

class _DeleteDropZone extends StatelessWidget {
  const _DeleteDropZone({super.key, required this.onAccept});

  final ValueChanged<_DragPayload> onAccept;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DragTarget<_DragPayload>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) => onAccept(details.data),
      builder: (context, candidate, _) {
        final active = candidate.isNotEmpty;
        return Material(
          color: active ? scheme.errorContainer : scheme.surfaceContainerHigh,
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 56,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.delete_outline_rounded,
                    color: active ? scheme.error : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    active ? '松手删除安排' : '拖到这里删除安排',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: active ? scheme.error : scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _UnscheduledBar extends StatelessWidget {
  const _UnscheduledBar({
    required this.items,
    required this.progressMap,
    required this.compact,
    required this.dragging,
    required this.unreadBySubject,
    required this.season,
    required this.onDragStarted,
    required this.onDragEnded,
    required this.onAccept,
    required this.onOpen,
    required this.onMove,
    required this.onRemove,
  });

  final List<ScheduleItem> items;
  final Map<int, UserCollection> progressMap;
  final bool compact;
  final bool dragging;
  final Map<int, int> unreadBySubject;
  final SeasonKey season;
  final VoidCallback onDragStarted;
  final VoidCallback onDragEnded;
  final void Function(_DragPayload payload, int index) onAccept;
  final ValueChanged<ScheduleItem> onOpen;
  final void Function(ScheduleItem item, int? day) onMove;
  final ValueChanged<ScheduleItem> onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DragTarget<_DragPayload>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) => onAccept(details.data, items.length),
      builder: (context, candidate, _) {
        final highlight = candidate.isNotEmpty;
        return Material(
          color: highlight
              ? scheme.tertiaryContainer.withValues(alpha: .65)
              : scheme.surfaceContainerLow,
          child: SizedBox(
            height: compact ? 108 : 124,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(16, compact ? 6 : 8, 16, 4),
                  child: Text(
                    highlight
                        ? '松手放到待安排'
                        : items.isEmpty
                        ? '待安排 · 拖到这里取消排期'
                        : compact
                        ? '待安排 ${items.length} · 长按拖到周几'
                        : '待安排（${items.length}）· 长按拖拽 / 点 ⋮ 删除',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                Expanded(
                  child: items.isEmpty
                      ? Center(
                          child: Text(
                            dragging ? '拖到此处' : '空',
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                        )
                      : ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                          itemCount: items.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            final item = items[index];
                            return _CourseCell(
                              item: item,
                              collection: progressMap[item.subjectId],
                              style: _CellStyle.chip,
                              enableDrag: true,
                              unreadCount: unreadBySubject[item.subjectId] ?? 0,
                              season: season,
                              onDragStarted: onDragStarted,
                              onDragEnded: onDragEnded,
                              onOpen: () => onOpen(item),
                              onMove: (day) => onMove(item, day),
                              onRemove: () => onRemove(item),
                            );
                          },
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

/// WakeUp-style week grid: Mon–Sun always fit; cells are drop targets.
class _CourseTable extends StatelessWidget {
  const _CourseTable({
    required this.schedule,
    required this.progressMap,
    required this.dragging,
    required this.unreadBySubject,
    required this.season,
    required this.onDragStarted,
    required this.onDragEnded,
    required this.onAccept,
    required this.onOpen,
    required this.onMove,
    required this.onRemove,
  });

  final SeasonSchedule schedule;
  final Map<int, UserCollection> progressMap;
  final bool dragging;
  final Map<int, int> unreadBySubject;
  final SeasonKey season;
  final VoidCallback onDragStarted;
  final VoidCallback onDragEnded;
  final void Function(_DragPayload payload, int weekday, int slot) onAccept;
  final ValueChanged<ScheduleItem> onOpen;
  final void Function(ScheduleItem item, int? day) onMove;
  final ValueChanged<ScheduleItem> onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final today = DateTime.now().weekday;
    // Precompute each weekday's sorted items once: itemsOn() filters and
    // sorts on every call, and the table below used to call it repeatedly
    // per day/slot (hundreds of O(n) passes per rebuild).
    final itemsByDay = <int, List<ScheduleItem>>{};
    for (final item in schedule.items) {
      final weekday = item.weekday;
      if (weekday == null) continue;
      itemsByDay.putIfAbsent(weekday, () => []).add(item);
    }
    for (final list in itemsByDay.values) {
      list.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    }
    List<ScheduleItem> dayItems(int day) => itemsByDay[day] ?? const [];
    final maxRows = [
      for (var day = DateTime.monday; day <= DateTime.sunday; day++)
        dayItems(day).length,
    ].fold<int>(0, math.max);
    // Not capped at 3: always keep one empty row so users can drop/add more.
    // Minimum 3 rows is only visual (timetable-like empty slots).
    final slots = math.max(3, maxRows + 1);

    return LayoutBuilder(
      builder: (context, constraints) {
        final pad = constraints.maxWidth < 400 ? 6.0 : 8.0;
        final tableWidth = math.max(0.0, constraints.maxWidth - pad * 2);
        final indexWidth = tableWidth < 420
            ? (tableWidth < 340 ? 18.0 : 22.0)
            : 32.0;
        final dayWidth = (tableWidth - indexWidth) / 7;
        // Cover-on-top layout must kick in before the horizontal row overflows.
        final dense = dayWidth < 108;
        final medium = dayWidth < 128;
        final cellStyle = dayWidth < 78 ? _CellStyle.dense : _CellStyle.grid;
        final rowHeight = dense
            ? (dayWidth < 56 ? 82.0 : 90.0)
            : medium
            ? 96.0
            : 100.0;
        final headerHeight = dense ? 34.0 : 44.0;
        final shortHeader = dayWidth < 64;

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(pad, 0, pad, dragging ? 12 : 96),
          child: SizedBox(
            width: tableWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(12),
                    ),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: indexWidth,
                        height: headerHeight,
                        child: Icon(
                          Icons.grid_on_rounded,
                          size: dense ? 12 : 16,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      for (
                        var day = DateTime.monday;
                        day <= DateTime.sunday;
                        day++
                      )
                        Expanded(
                          child: DragTarget<_DragPayload>(
                            onWillAcceptWithDetails: (_) => true,
                            onAcceptWithDetails: (details) => onAccept(
                              details.data,
                              day,
                              dayItems(day).length,
                            ),
                            builder: (context, candidate, _) {
                              final hot = candidate.isNotEmpty;
                              return Container(
                                height: headerHeight,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: hot
                                      ? scheme.primary.withValues(alpha: .25)
                                      : day == today
                                      ? scheme.primaryContainer.withValues(
                                          alpha: .55,
                                        )
                                      : null,
                                  border: Border(
                                    left: BorderSide(
                                      color: scheme.outlineVariant,
                                    ),
                                  ),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      shortHeader
                                          ? weekdayShortLabel(day)
                                          : weekdayLabel(day),
                                      style: TextStyle(
                                        fontSize: dense ? 12 : 13,
                                        fontWeight: FontWeight.w800,
                                        color: day == today || hot
                                            ? scheme.primary
                                            : null,
                                      ),
                                    ),
                                    if (!dense)
                                      Text(
                                        '${dayItems(day).length}',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(color: scheme.outlineVariant),
                      right: BorderSide(color: scheme.outlineVariant),
                      bottom: BorderSide(color: scheme.outlineVariant),
                    ),
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(12),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var slot = 0; slot < slots; slot++)
                        SizedBox(
                          height: rowHeight,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                width: indexWidth,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  border: Border(
                                    top: BorderSide(
                                      color: scheme.outlineVariant,
                                    ),
                                  ),
                                  color: scheme.surfaceContainerLow,
                                ),
                                child: Text(
                                  '${slot + 1}',
                                  style: TextStyle(
                                    fontSize: dense ? 11 : 13,
                                    fontWeight: FontWeight.w700,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              for (
                                var day = DateTime.monday;
                                day <= DateTime.sunday;
                                day++
                              )
                                Expanded(
                                  child: _DaySlot(
                                    day: day,
                                    slot: slot,
                                    isToday: day == today,
                                    dense: dense,
                                    item: slot < dayItems(day).length
                                        ? dayItems(day)[slot]
                                        : null,
                                    collection: slot < dayItems(day).length
                                        ? progressMap[dayItems(
                                            day,
                                          )[slot].subjectId]
                                        : null,
                                    unreadCount: slot < dayItems(day).length
                                        ? (unreadBySubject[dayItems(
                                                day,
                                              )[slot].subjectId] ??
                                              0)
                                        : 0,
                                    season: season,
                                    cellStyle: cellStyle,
                                    onAccept: onAccept,
                                    onDragStarted: onDragStarted,
                                    onDragEnded: onDragEnded,
                                    onOpen: onOpen,
                                    onMove: onMove,
                                    onRemove: onRemove,
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
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

class _DaySlot extends StatelessWidget {
  const _DaySlot({
    required this.day,
    required this.slot,
    required this.isToday,
    required this.dense,
    required this.item,
    required this.collection,
    required this.unreadCount,
    required this.season,
    required this.cellStyle,
    required this.onAccept,
    required this.onDragStarted,
    required this.onDragEnded,
    required this.onOpen,
    required this.onMove,
    required this.onRemove,
  });

  final int day;
  final int slot;
  final bool isToday;
  final bool dense;
  final ScheduleItem? item;
  final UserCollection? collection;
  final int unreadCount;
  final SeasonKey season;
  final _CellStyle cellStyle;
  final void Function(_DragPayload payload, int weekday, int slot) onAccept;
  final VoidCallback onDragStarted;
  final VoidCallback onDragEnded;
  final ValueChanged<ScheduleItem> onOpen;
  final void Function(ScheduleItem item, int? day) onMove;
  final ValueChanged<ScheduleItem> onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DragTarget<_DragPayload>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) => onAccept(details.data, day, slot),
      builder: (context, candidate, _) {
        final hot = candidate.isNotEmpty;
        return Container(
          padding: EdgeInsets.all(dense ? 2 : 3),
          decoration: BoxDecoration(
            color: hot
                ? scheme.primary.withValues(alpha: .18)
                : isToday
                ? scheme.primaryContainer.withValues(alpha: .10)
                : null,
            border: Border(
              left: BorderSide(color: scheme.outlineVariant),
              top: BorderSide(color: scheme.outlineVariant),
            ),
          ),
          child: item == null
              ? const SizedBox.expand()
              : _CourseCell(
                  item: item!,
                  collection: collection,
                  style: cellStyle,
                  dense: dense,
                  enableDrag: true,
                  unreadCount: unreadCount,
                  season: season,
                  onDragStarted: onDragStarted,
                  onDragEnded: onDragEnded,
                  onOpen: () => onOpen(item!),
                  onMove: (target) => onMove(item!, target),
                  onRemove: () => onRemove(item!),
                ),
        );
      },
    );
  }
}

enum _CellStyle { chip, grid, dense }

class _CourseCell extends ConsumerWidget {
  const _CourseCell({
    required this.item,
    required this.onOpen,
    required this.onMove,
    required this.onRemove,
    required this.season,
    this.collection,
    this.style = _CellStyle.grid,
    this.dense = false,
    this.enableDrag = false,
    this.unreadCount = 0,
    this.onDragStarted,
    this.onDragEnded,
  });

  final ScheduleItem item;
  final UserCollection? collection;
  final VoidCallback onOpen;
  final ValueChanged<int?> onMove;
  final VoidCallback onRemove;
  final SeasonKey season;
  final _CellStyle style;
  final bool dense;
  final bool enableDrag;
  final int unreadCount;
  final VoidCallback? onDragStarted;
  final VoidCallback? onDragEnded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final subject = Subject(
      id: item.subjectId,
      name: item.name,
      nameCn: item.nameCn,
      imageUrl: item.imageUrl,
      summary: '',
      episodeCount: item.episodeCount,
      score: 0,
      rank: 0,
      date: '',
      type: item.type,
    );
    final progress = collection == null
        ? null
        : collection!.subject.episodeCount > 0
        ? '${collection!.episodeStatus}/${collection!.subject.episodeCount}'
        : null;

    final showMenuButton = style == _CellStyle.grid && !dense;
    final content = switch (style) {
      _CellStyle.chip => SizedBox(
        width: 84,
        child: Stack(
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) => SubjectCover(
                      subject: subject,
                      width: 48,
                      height: constraints.maxHeight,
                      borderRadius: 8,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                ReadableSubjectTitle(
                  item.displayName,
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            Positioned(
              top: -4,
              right: -8,
              child: IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                tooltip: '更多',
                icon: const Icon(Icons.more_vert_rounded, size: 16),
                onPressed: () => _showActions(context, ref),
              ),
            ),
          ],
        ),
      ),
      _CellStyle.dense => Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => SubjectCover(
                    subject: subject,
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                    borderRadius: 6,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              SizedBox(
                height: 22,
                child: ReadableSubjectTitle(
                  item.displayName,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 9,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSecondaryContainer,
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            top: -6,
            right: -8,
            child: IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
              tooltip: '删除/改期',
              icon: Icon(
                Icons.more_horiz_rounded,
                size: 16,
                color: scheme.onSurface.withValues(alpha: .75),
              ),
              onPressed: () => _showActions(context, ref),
            ),
          ),
        ],
      ),
      _CellStyle.grid =>
        dense
            ? Stack(
                children: [
                  Column(
                    children: [
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) => SubjectCover(
                            subject: subject,
                            width: constraints.maxWidth,
                            height: constraints.maxHeight,
                            borderRadius: 6,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      ReadableSubjectTitle(
                        item.displayName,
                        maxLines: 1,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  Positioned(
                    top: -6,
                    right: -8,
                    child: IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 26,
                        minHeight: 26,
                      ),
                      tooltip: '删除/改期',
                      icon: const Icon(Icons.more_horiz_rounded, size: 16),
                      onPressed: () => _showActions(context, ref),
                    ),
                  ),
                ],
              )
            : LayoutBuilder(
                builder: (context, cellConstraints) {
                  final tight = cellConstraints.maxWidth < 120;
                  final coverW = tight ? 32.0 : 40.0;
                  final coverH = tight ? 46.0 : 56.0;
                  return Row(
                    children: [
                      SubjectCover(
                        subject: subject,
                        width: coverW,
                        height: coverH,
                        borderRadius: 7,
                      ),
                      SizedBox(width: tight ? 4 : 6),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ReadableSubjectTitle(
                              item.displayName,
                              maxLines: tight ? 1 : 2,
                              style: TextStyle(
                                fontSize: tight ? 11 : 12,
                                fontWeight: FontWeight.w800,
                                height: 1.15,
                              ),
                            ),
                            if (progress != null && !tight) ...[
                              const SizedBox(height: 2),
                              Text(
                                progress,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: scheme.onSecondaryContainer,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (showMenuButton && !tight)
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                          tooltip: '更多',
                          icon: const Icon(Icons.more_vert_rounded, size: 18),
                          onPressed: () => _showActions(context, ref),
                        ),
                    ],
                  );
                },
              ),
    };

    final radius = dense || style == _CellStyle.dense ? 8.0 : 10.0;
    final card = Material(
      color: scheme.secondaryContainer.withValues(alpha: .55),
      borderRadius: BorderRadius.circular(radius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: onOpen,
        child: Stack(
          children: [
            Padding(
              padding: EdgeInsets.all(
                dense || style == _CellStyle.dense ? 3 : 5,
              ),
              child: content,
            ),
            if (unreadCount > 0)
              Positioned(
                left: 2,
                top: 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.error,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    unreadCount > 9 ? '9+' : '$unreadCount',
                    style: TextStyle(
                      color: scheme.onError,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            if (item.reminderEnabled && item.isScheduled)
              Positioned(
                right: 3,
                bottom: 3,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer.withValues(alpha: .92),
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: Icon(
                      Icons.notifications_active_rounded,
                      size: 12,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    if (!enableDrag) return card;

    return LongPressDraggable<_DragPayload>(
      data: _DragPayload(item),
      hapticFeedbackOnStart: true,
      onDragStarted: onDragStarted,
      onDragEnd: (_) => onDragEnded?.call(),
      onDraggableCanceled: (_, _) => onDragEnded?.call(),
      feedback: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 72,
          height: 96,
          child: Column(
            children: [
              Expanded(
                child: SubjectCover(
                  subject: subject,
                  width: 72,
                  height: 72,
                  borderRadius: 0,
                ),
              ),
              ColoredBox(
                color: scheme.secondaryContainer,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: ReadableSubjectTitle(
                    item.displayName,
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.28, child: card),
      child: card,
    );
  }

  Future<void> _showActions(BuildContext context, WidgetRef ref) async {
    final value = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: ReadableSubjectTitle(
                  item.displayName,
                  maxLines: 1,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  unreadCount > 0
                      ? '有 $unreadCount 条未读更新 · 长按拖拽改期'
                      : '点封面进条目 · 长按可拖拽改期',
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.open_in_new_rounded),
                title: const Text('打开条目'),
                onTap: () => Navigator.pop(context, 'open'),
              ),
              ListTile(
                leading: Icon(
                  item.reminderEnabled
                      ? Icons.notifications_active_rounded
                      : Icons.notifications_none_rounded,
                ),
                title: const Text('系统更新提醒'),
                subtitle: Text(
                  item.reminderEnabled && item.isScheduled
                      ? '${weekdayLabel(item.weekday!)} '
                            '${item.reminderHour.toString().padLeft(2, '0')}:'
                            '${item.reminderMinute.toString().padLeft(2, '0')}'
                      : item.isScheduled
                      ? '已关闭 · 可独立设置'
                      : '先安排到具体星期',
                ),
                onTap: () => Navigator.pop(context, 'reminder'),
              ),
              ListTile(
                leading: const Icon(Icons.rss_feed_rounded),
                title: const Text('绑定更新源'),
                subtitle: const Text('种子站 RSS → 提醒该看了'),
                onTap: () => Navigator.pop(context, 'rss_bind'),
              ),
              ListTile(
                leading: Badge(
                  isLabelVisible: unreadCount > 0,
                  child: const Icon(Icons.notifications_outlined),
                ),
                title: const Text('查看更新'),
                onTap: () => Navigator.pop(context, 'rss_updates'),
              ),
              ListTile(
                leading: Icon(
                  Icons.delete_outline_rounded,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  '删除安排',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                subtitle: const Text('从本季新番表移除'),
                onTap: () => Navigator.pop(context, 'remove'),
              ),
              ListTile(
                leading: const Icon(Icons.inbox_outlined),
                title: const Text('移到待安排'),
                onTap: () => Navigator.pop(context, 'pool'),
              ),
              for (var day = DateTime.monday; day <= DateTime.sunday; day++)
                ListTile(
                  leading: const Icon(Icons.event_rounded),
                  title: Text('安排到${weekdayLabel(day)}'),
                  onTap: () => Navigator.pop(context, '$day'),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (value == null) return;
    if (value == 'open') {
      onOpen();
      return;
    }
    if (value == 'rss_bind') {
      if (!context.mounted) return;
      await showRssBindSheet(context, item: item, season: season);
      return;
    }
    if (value == 'reminder') {
      if (!context.mounted) return;
      await showScheduleReminderSheet(context, item: item);
      return;
    }
    if (value == 'rss_updates') {
      if (!context.mounted) return;
      await showRssUpdatesSheet(
        context,
        subjectId: item.subjectId,
        subjectName: item.displayName,
      );
      return;
    }
    if (value == 'remove') {
      onRemove();
      return;
    }
    if (value == 'pool') {
      onMove(null);
      return;
    }
    final day = int.tryParse(value);
    if (day != null) onMove(day);
  }
}

void _openSubject(BuildContext context, ScheduleItem item) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => SubjectDetailScreen(
        subject: Subject(
          id: item.subjectId,
          name: item.name,
          nameCn: item.nameCn,
          imageUrl: item.imageUrl,
          summary: '',
          episodeCount: item.episodeCount,
          score: 0,
          rank: 0,
          date: '',
          type: item.type,
        ),
      ),
    ),
  );
}
