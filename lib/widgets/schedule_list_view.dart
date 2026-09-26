import 'package:flutter/material.dart';

import '../models/bangumi_models.dart';
import '../models/schedule_models.dart';
import '../models/schedule_view.dart';
import 'subject_widgets.dart';
import '../core/theme/app_tokens.dart';

class ScheduleListView extends StatelessWidget {
  const ScheduleListView({
    super.key,
    required this.schedule,
    required this.view,
    required this.today,
    required this.progressMap,
    required this.unreadBySubject,
    required this.onOpen,
    required this.onActions,
    required this.onViewWeek,
    required this.onAdd,
    this.boundSubjects = const {},
    this.rssAvailable = true,
    this.onProgress,
    this.onViewUpdates,
    this.updatingSubjects = const {},
  });
  final SeasonSchedule schedule;
  final ScheduleView view;
  final DateTime today;
  final Map<int, UserCollection> progressMap;
  final Map<int, int> unreadBySubject;
  final ValueChanged<ScheduleItem> onOpen;
  final ValueChanged<ScheduleItem> onActions;
  final VoidCallback onViewWeek;
  final VoidCallback onAdd;
  final Set<int> boundSubjects;
  final bool rssAvailable;
  final ValueChanged<ScheduleItem>? onProgress, onViewUpdates;
  final Set<int> updatingSubjects;

  @override
  Widget build(BuildContext context) {
    final currentSeason = schedule.season == SeasonKey.current(today);
    final sections = scheduleSections(schedule, view, today);
    final rows = <Widget>[
      if (!currentSeason)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            '正在查看${schedule.season.label}的每周安排；日期标记仅用于当前季度。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      if (schedule.items.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 28),
          child: EmptyState(
            icon: Icons.calendar_today_outlined,
            title: '本季还没有安排',
            message: '搜索喜欢的作品，加入这个季度的新番表。',
            action: FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: const Text('搜索加入'),
            ),
          ),
        )
      else
        for (final section in sections) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
            child: Text(
              section.weekday == null
                  ? '待安排 · ${section.items.length} 部'
                  : '${section.weekday == today.weekday && currentSeason ? '今天 · ' : ''}${weekdayLabel(section.weekday!)}${section.date == null ? '' : '  ${section.date!.month}/${section.date!.day}'} · ${section.items.length} 部',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: section.weekday == today.weekday
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
            ),
          ),
          if (section.items.isEmpty && view == ScheduleView.today)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    view == ScheduleView.today
                        ? currentSeason
                              ? '今天没有安排，轻松休息一下。'
                              : '所选季度的${weekdayLabel(today.weekday)}没有安排。'
                        : '暂无安排',
                  ),
                  if (view == ScheduleView.today)
                    TextButton(
                      onPressed: onViewWeek,
                      child: const Text('查看整周安排'),
                    ),
                ],
              ),
            ),
          for (final item in section.items)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ScheduleListCard(
                key: ValueKey('schedule-list-${item.subjectId}'),
                item: item,
                collection: progressMap[item.subjectId],
                unread: unreadBySubject[item.subjectId] ?? 0,
                bound: boundSubjects.contains(item.subjectId),
                rssAvailable: rssAvailable,
                onProgress: onProgress == null ? null : () => onProgress!(item),
                onViewUpdates: onViewUpdates == null
                    ? null
                    : () => onViewUpdates!(item),
                updating: updatingSubjects.contains(item.subjectId),
                onOpen: () => onOpen(item),
                onActions: () => onActions(item),
              ),
            ),
        ],
    ];
    return ListView.builder(
      key: ValueKey(
        'schedule-${view.name}-${schedule.season.id}-${view == ScheduleView.today ? '${today.year}-${today.month}-${today.day}' : DateTime(today.year, today.month, today.day - today.weekday + 1)}',
      ),
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 100),
      itemCount: rows.length,
      itemBuilder: (_, index) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: SizedBox(width: double.infinity, child: rows[index]),
        ),
      ),
    );
  }
}

class _ScheduleListCard extends StatelessWidget {
  const _ScheduleListCard({
    super.key,
    required this.item,
    required this.collection,
    required this.unread,
    required this.onOpen,
    required this.onActions,
    required this.bound,
    required this.rssAvailable,
    this.onProgress,
    this.onViewUpdates,
    this.updating = false,
  });
  final ScheduleItem item;
  final UserCollection? collection;
  final int unread;
  final bool bound, rssAvailable;
  final VoidCallback onOpen, onActions;
  final VoidCallback? onProgress, onViewUpdates;
  final bool updating;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subject =
        collection?.subject ??
        Subject(
          id: item.subjectId,
          type: item.type,
          name: item.name,
          nameCn: item.nameCn,
          imageUrl: item.imageUrl,
          summary: '',
          episodeCount: item.episodeCount,
          score: 0,
          rank: 0,
          date: '',
        );
    final count = subject.episodeCount;
    final progress = collection == null
        ? '未加入收藏'
        : item.type.hasEpisodes
        ? '看过 ${collection!.episodeStatus}${count > 0 ? ' / $count' : ''} 话'
        : item.type.hasVolumes
        ? '读到 ${collection!.episodeStatus} 话 · ${collection!.volumeStatus} 卷'
        : collection!.type.labelFor(item.type);
    final reminder = !item.isScheduled
        ? '待安排到具体星期'
        : item.reminderEnabled
        ? '每周 ${item.reminderHour.toString().padLeft(2, '0')}:${item.reminderMinute.toString().padLeft(2, '0')} 提醒'
        : '系统提醒已关闭';
    final rssText = unread > 0
        ? 'RSS 已发现 $unread 条未读更新'
        : !rssAvailable
        ? 'RSS 状态暂未就绪'
        : bound
        ? 'RSS 暂无未读更新'
        : '尚未绑定 RSS';
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: AppRadius.large,
      child: InkWell(
        borderRadius: AppRadius.large,
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 8, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        item.displayName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '安排操作',
                    onPressed: onActions,
                    icon: const Icon(Icons.more_vert_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SubjectCover(
                    subject: subject,
                    width: 56,
                    height: 78,
                    borderRadius: 10,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(progress, style: theme.textTheme.bodySmall),
                        const SizedBox(height: 6),
                        Text(
                          reminder,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          rssText,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: unread > 0
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (item.note.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(item.note, style: theme.textTheme.bodySmall),
              ],
              if (onProgress != null || onViewUpdates != null) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (onProgress != null &&
                        (collection == null ||
                            (item.type.hasEpisodes &&
                                (count <= 0 ||
                                    collection!.episodeStatus < count))))
                      FilledButton.tonalIcon(
                        onPressed: updating ? null : onProgress,
                        icon: Icon(
                          collection == null
                              ? Icons.add_rounded
                              : Icons.check_rounded,
                          size: 18,
                        ),
                        label: Text(
                          updating
                              ? '保存中…'
                              : collection == null
                              ? '加入在看'
                              : '看完一集',
                        ),
                      ),
                    if (onViewUpdates != null && (bound || unread > 0))
                      TextButton.icon(
                        onPressed: onViewUpdates,
                        icon: const Icon(Icons.rss_feed_rounded, size: 18),
                        label: Text(unread > 0 ? '查看更新 ($unread)' : '查看更新'),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
