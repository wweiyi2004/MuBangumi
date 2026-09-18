import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/bangumi_models.dart';
import '../../../models/schedule_models.dart';
import '../../../widgets/subject_widgets.dart';
import '../../../widgets/readable_subject_title.dart';
import '../../../models/episode_edit.dart';
import '../../../widgets/episode_undo_message.dart';
import '../../../widgets/schedule_reminder_sheet.dart';
import '../../../state/schedule_controller.dart';
import '../../../state/session_controller.dart';
import '../../../screens/rss_sheets.dart';

Future<void> showScheduleItemActions(
  BuildContext context,
  WidgetRef ref, {
  required ScheduleItem item,
  required SeasonKey season,
  required int unreadCount,
  required VoidCallback onOpen,
  required ValueChanged<int?> onMove,
  required VoidCallback onRemove,
}) async {
  final owner = ref.read(sessionProvider).user?.id;
  final collection = ref
      .read(sessionProvider)
      .collections
      .where((c) => c.subjectId == item.subjectId)
      .firstOrNull;
  final canProgress =
      collection == null ||
      (item.type.hasEpisodes &&
          (collection.subject.episodeCount <= 0 ||
              collection.episodeStatus < collection.subject.episodeCount));
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
            if (canProgress)
              ListTile(
                leading: Icon(
                  collection == null ? Icons.add_rounded : Icons.check_rounded,
                ),
                title: Text(collection == null ? '加入在看' : '看完一集'),
                onTap: () => Navigator.pop(context, 'progress'),
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
              subtitle: const Text('匹配订阅内容，显示未读更新'),
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
  if (!context.mounted || value == null) return;
  final current = ref.read(scheduleProvider);
  if (current.loading ||
      current.saving ||
      current.season != season ||
      !current.schedule.containsSubject(item.subjectId)) {
    showAppMessage(context, '安排已变化，请重新打开操作菜单');
    return;
  }
  if (value == 'progress') {
    if (ref.read(sessionProvider).user?.id != owner) {
      showAppMessage(context, '登录状态已变化，请重新操作');
      return;
    }
    await updateScheduleProgress(context, ref, item);
    return;
  }
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
    await showScheduleReminderSheet(
      context,
      item: current.schedule.items.firstWhere(
        (candidate) => candidate.subjectId == item.subjectId,
      ),
      expectedSeason: season,
    );
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

Future<void> updateScheduleProgress(
  BuildContext context,
  WidgetRef ref,
  ScheduleItem item,
) async {
  final session = ref.read(sessionProvider);
  if (session.updatingSubjects.contains(item.subjectId)) return;
  final collection = session.collections
      .where((c) => c.subjectId == item.subjectId)
      .firstOrNull;
  final controller = ref.read(sessionProvider.notifier);
  EpisodeUndo? undo;
  final error = collection == null
      ? await controller.changeCollection(
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
          ),
          CollectionType.doing,
        )
      : await controller.markNextEpisode(
          collection,
          onUndoReady: (value) => undo = value,
        );
  if (!context.mounted) return;
  if (error != null) {
    showAppMessage(context, error);
  } else if (undo != null) {
    showEpisodeUndoMessage(context, controller, undo!);
  } else if (collection == null) {
    showAppMessage(context, '已加入在看');
  }
}
