import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../models/bangumi_models.dart';
import '../../../models/schedule_models.dart';
import 'schedule_course_cell.dart';

/// Unscheduled strip + week grid, with drag-and-drop within the season.
class ScheduleBoard extends StatefulWidget {
  const ScheduleBoard({
    super.key,
    required this.schedule,
    required this.progressMap,
    required this.compactChrome,
    required this.season,
    required this.unreadBySubject,
    required this.today,
    required this.onOpen,
    required this.onActions,
    required this.onPlace,
    required this.onRemove,
  });

  final SeasonSchedule schedule;
  final Map<int, UserCollection> progressMap;
  final bool compactChrome;
  final SeasonKey season;
  final Map<int, int> unreadBySubject;
  final int today;
  final ValueChanged<ScheduleItem> onOpen, onActions;
  final void Function(int subjectId, {int? weekday, int? insertIndex}) onPlace;
  final ValueChanged<int> onRemove;

  @override
  State<ScheduleBoard> createState() => _ScheduleBoardState();
}

class _ScheduleBoardState extends State<ScheduleBoard> {
  bool _dragging = false;

  void _setDragging(bool value) {
    if (!mounted || _dragging == value) return;
    setState(() => _dragging = value);
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
            onAccept: (payload, index) => widget.onPlace(
              payload.item.subjectId,
              weekday: null,
              insertIndex: index,
            ),
            onOpen: widget.onOpen,
            onActions: widget.onActions,
          ),
        Expanded(
          child: _CourseTable(
            today: widget.today,
            schedule: schedule,
            progressMap: progressMap,
            dragging: _dragging,
            unreadBySubject: widget.unreadBySubject,
            season: widget.season,
            onDragStarted: () => _setDragging(true),
            onDragEnded: () => _setDragging(false),
            onAccept: (payload, weekday, slot) => widget.onPlace(
              payload.item.subjectId,
              weekday: weekday,
              insertIndex: slot,
            ),
            onOpen: widget.onOpen,
            onActions: widget.onActions,
          ),
        ),
        // Drag-to-delete zone (fixes “找不到删除” on dense phones).
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: _dragging
              ? _DeleteDropZone(
                  key: const ValueKey('delete-zone'),
                  onAccept: (payload) {
                    if (payload.season == widget.season) {
                      widget.onRemove(payload.item.subjectId);
                    }
                  },
                )
              : const SizedBox(key: ValueKey('delete-zone-off'), height: 0),
        ),
      ],
    );
  }
}

class _DeleteDropZone extends StatelessWidget {
  const _DeleteDropZone({super.key, required this.onAccept});

  final ValueChanged<ScheduleDragPayload> onAccept;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DragTarget<ScheduleDragPayload>(
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
    required this.onActions,
  });

  final List<ScheduleItem> items;
  final Map<int, UserCollection> progressMap;
  final bool compact;
  final bool dragging;
  final Map<int, int> unreadBySubject;
  final SeasonKey season;
  final VoidCallback onDragStarted;
  final VoidCallback onDragEnded;
  final void Function(ScheduleDragPayload payload, int index) onAccept;
  final ValueChanged<ScheduleItem> onOpen;
  final ValueChanged<ScheduleItem> onActions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DragTarget<ScheduleDragPayload>(
      onWillAcceptWithDetails: (details) => details.data.season == season,
      onAcceptWithDetails: (details) => onAccept(details.data, items.length),
      builder: (context, candidate, _) {
        final highlight = candidate.isNotEmpty;
        return Material(
          color: highlight
              ? scheme.tertiaryContainer.withValues(alpha: .65)
              : scheme.surfaceContainerLow,
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
              SizedBox(
                height:
                    (compact ? 60 : 76) +
                    MediaQuery.textScalerOf(context).scale(12) * 1.5,
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
                          return ScheduleCourseCell(
                            item: item,
                            collection: progressMap[item.subjectId],
                            style: ScheduleCellStyle.chip,
                            enableDrag: true,
                            unreadCount: unreadBySubject[item.subjectId] ?? 0,
                            season: season,
                            onDragStarted: onDragStarted,
                            onDragEnded: onDragEnded,
                            onOpen: () => onOpen(item),
                            onActions: () => onActions(item),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// WakeUp-style week grid: Mon–Sun always fit; cells are drop targets.
class _CourseTable extends StatelessWidget {
  const _CourseTable({
    required this.today,
    required this.schedule,
    required this.progressMap,
    required this.dragging,
    required this.unreadBySubject,
    required this.season,
    required this.onDragStarted,
    required this.onDragEnded,
    required this.onAccept,
    required this.onOpen,
    required this.onActions,
  });

  final int today;
  final SeasonSchedule schedule;
  final Map<int, UserCollection> progressMap;
  final bool dragging;
  final Map<int, int> unreadBySubject;
  final SeasonKey season;
  final VoidCallback onDragStarted;
  final VoidCallback onDragEnded;
  final void Function(ScheduleDragPayload payload, int weekday, int slot)
  onAccept;
  final ValueChanged<ScheduleItem> onOpen;
  final ValueChanged<ScheduleItem> onActions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
        final cellStyle = dayWidth < 78
            ? ScheduleCellStyle.dense
            : ScheduleCellStyle.grid;
        final rowHeight = dense
            ? (dayWidth < 56 ? 82.0 : 90.0)
            : medium
            ? 96.0
            : 100.0;
        final headerHeight = math.max(
          dense ? 34.0 : 44.0,
          MediaQuery.textScalerOf(context).scale(dense ? 17 : 32) + 12,
        );
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
                          child: DragTarget<ScheduleDragPayload>(
                            onWillAcceptWithDetails: (details) =>
                                details.data.season == season,
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
                                    onActions: onActions,
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
    required this.onActions,
  });

  final int day;
  final int slot;
  final bool isToday;
  final bool dense;
  final ScheduleItem? item;
  final UserCollection? collection;
  final int unreadCount;
  final SeasonKey season;
  final ScheduleCellStyle cellStyle;
  final void Function(ScheduleDragPayload payload, int weekday, int slot)
  onAccept;
  final VoidCallback onDragStarted;
  final VoidCallback onDragEnded;
  final ValueChanged<ScheduleItem> onOpen;
  final ValueChanged<ScheduleItem> onActions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DragTarget<ScheduleDragPayload>(
      onWillAcceptWithDetails: (details) => details.data.season == season,
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
              : ScheduleCourseCell(
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
                  onActions: () => onActions(item!),
                ),
        );
      },
    );
  }
}
