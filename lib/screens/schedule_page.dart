import '../navigation/app_destination.dart';
import '../widgets/season_anime_picker.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/bangumi_models.dart';
import '../models/schedule_models.dart';
import '../models/schedule_view.dart';
import '../state/schedule_view_controller.dart';
import '../widgets/schedule_list_view.dart';
import '../state/rss_controller.dart';
import '../state/schedule_controller.dart';
import '../state/session_controller.dart';
import '../widgets/schedule_export_poster.dart';
import '../widgets/subject_widgets.dart';
import 'rss_sheets.dart';
import '../features/schedule/presentation/schedule_board.dart';
import '../features/schedule/presentation/schedule_header.dart';
import '../features/schedule/presentation/schedule_search_sheet.dart';
import '../features/schedule/presentation/schedule_season_dialog.dart';
import '../features/schedule/presentation/schedule_item_actions.dart';

export '../features/schedule/presentation/schedule_item_actions.dart'
    show showScheduleItemActions;

/// Seasonal schedule as a WakeUp-style week grid (Mon–Sun always visible).
/// Subject info from Bangumi search; placement is local-only.
class SchedulePage extends ConsumerWidget {
  const SchedulePage({super.key});

  /// Wider chrome (FAB label, larger header) only — grid itself always fits 7 days.
  static const double wideBreakpoint = 720;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(scheduleProvider);
    final ownerId =
        ref.watch(sessionProvider.select((state) => state.user?.id)) ?? 0;
    final viewState = ref.watch(scheduleViewProvider(ownerId));
    final viewController = ref.read(scheduleViewProvider(ownerId).notifier);
    final view =
        viewState.selected ?? defaultScheduleView(Theme.of(context).platform);
    final today = ref.watch(scheduleDayProvider);
    ref.listen(scheduleDayProvider, (_, _) {
      unawaited(
        ref.read(scheduleProvider.notifier).syncReminders(reportErrors: false),
      );
    });
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
      appBar: state.readFailed ? AppBar(title: const Text('新番表')) : null,
      floatingActionButton: isWide
          ? FloatingActionButton.extended(
              onPressed: () => showScheduleSearchSheet(context),
              icon: const Icon(Icons.search_rounded),
              label: const Text('搜索加入'),
            )
          : FloatingActionButton(
              onPressed: () => showScheduleSearchSheet(context),
              tooltip: '搜索加入',
              child: const Icon(Icons.search_rounded),
            ),
      body: state.readFailed
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('新番表读取失败，原内容已保留。请重试读取；若数据损坏，请从数据备份恢复。'),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => ref
                          .read(scheduleProvider.notifier)
                          .load(state.season),
                      icon: const Icon(Icons.refresh),
                      label: const Text('重试读取'),
                    ),
                  ],
                ),
              ),
            )
          : state.loading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
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
                          ScheduleToolbar(
                            wide: isWide,
                            refreshing: rss.refreshing,
                            unread: rss.totalUnread,
                            onExport: () => showScheduleExportDialog(
                              context,
                              schedule: state.schedule,
                            ),
                            onUpdates: () => showRssUpdatesSheet(context),
                            onRefresh: () => ref
                                .read(rssProvider.notifier)
                                .refreshAll(force: true),
                            onSources: () => showRssSourcesSheet(context),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '前台每 30 分钟检查 RSS · 关闭应用后不抓取',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                              fontSize: isWide ? null : 13,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ScheduleSeasonPicker(
                            season: state.season,
                            currentSeason: SeasonKey.current(today),
                            compact: !isWide,
                            knownSeasons: state.knownSeasons,
                            onChanged: (season) => ref
                                .read(scheduleProvider.notifier)
                                .setSeason(season),
                            onCreate: () => showScheduleSeasonDialog(
                              context,
                              current: state.season,
                              onCreate: ref
                                  .read(scheduleProvider.notifier)
                                  .createSeason,
                            ),
                            onPick: state.saving
                                ? null
                                : () => showSeasonAnimePicker(
                                    context,
                                    season: state.season,
                                  ),
                            onDeleteCurrent:
                                !state.saving && state.schedule.items.isEmpty
                                ? () => ref
                                      .read(scheduleProvider.notifier)
                                      .deleteCurrentSeason(
                                        expectedSeason: state.season,
                                      )
                                : null,
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 16,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              SegmentedButton<ScheduleView>(
                                segments: [
                                  for (final mode in ScheduleView.values)
                                    ButtonSegment(
                                      value: mode,
                                      label: Text(mode.label),
                                    ),
                                ],
                                selected: {view},
                                showSelectedIcon: false,
                                onSelectionChanged: (selection) =>
                                    viewController.select(selection.single),
                              ),
                              if (isWide)
                                FilledButton.tonalIcon(
                                  onPressed: state.saving
                                      ? null
                                      : () => showSeasonAnimePicker(
                                          context,
                                          season: state.season,
                                        ),
                                  icon: const Icon(Icons.playlist_add_rounded),
                                  label: const Text('挑选本季新番'),
                                ),
                              Text(
                                '共 ${state.schedule.items.length} 部 · 待安排 ${state.schedule.items.where((item) => !item.isScheduled).length} 部',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                          if (viewState.error != null)
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    viewState.error!,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ),
                                TextButton(
                                  onPressed: viewController.retry,
                                  child: const Text('重试'),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: view != ScheduleView.board
                          ? ScheduleListView(
                              schedule: state.schedule,
                              view: view,
                              today: today,
                              progressMap: progressMap,
                              unreadBySubject: rss.unreadBySubject,
                              boundSubjects: {
                                for (final binding in rss.bindings)
                                  if (binding.enabled) binding.subjectId,
                              },
                              rssAvailable: rss.loaded,
                              updatingSubjects: ref.watch(
                                sessionProvider.select(
                                  (s) => s.updatingSubjects,
                                ),
                              ),
                              onProgress: (item) =>
                                  updateScheduleProgress(context, ref, item),
                              onViewUpdates: (item) => showRssUpdatesSheet(
                                context,
                                subjectId: item.subjectId,
                                subjectName: item.displayName,
                              ),
                              onOpen: (item) => _openSubject(context, item),
                              onActions: (item) =>
                                  _showActions(context, ref, item),
                              onViewWeek: () =>
                                  viewController.select(ScheduleView.week),
                              onAdd: () => showScheduleSearchSheet(context),
                            )
                          : state.schedule.items.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(24),
                              child: EmptyState(
                                icon: Icons.calendar_view_week_rounded,
                                title: '本季课表还是空的',
                                message: '点“挑选本季新番”批量加入，也可从右下角搜索作品。',
                              ),
                            )
                          : ScheduleBoard(
                              key: ValueKey(state.season.id),
                              schedule: state.schedule,
                              progressMap: progressMap,
                              compactChrome: !isWide,
                              today: today.weekday,
                              onOpen: (item) => _openSubject(context, item),
                              onActions: (item) =>
                                  _showActions(context, ref, item),
                              onPlace: (id, {weekday, insertIndex}) => ref
                                  .read(scheduleProvider.notifier)
                                  .moveItem(
                                    id,
                                    weekday: weekday,
                                    insertIndex: insertIndex,
                                  ),
                              onRemove: ref
                                  .read(scheduleProvider.notifier)
                                  .removeSubject,
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

  Future<void> _showActions(
    BuildContext context,
    WidgetRef ref,
    ScheduleItem item,
  ) {
    final state = ref.read(scheduleProvider);
    return showScheduleItemActions(
      context,
      ref,
      item: item,
      season: state.season,
      unreadCount: ref.read(rssProvider).unreadFor(item.subjectId),
      onOpen: () => _openSubject(context, item),
      onMove: (day) => ref
          .read(scheduleProvider.notifier)
          .moveItem(item.subjectId, weekday: day),
      onRemove: () =>
          ref.read(scheduleProvider.notifier).removeSubject(item.subjectId),
    );
  }
}

void _openSubject(BuildContext context, ScheduleItem item) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => SubjectRoute(
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
