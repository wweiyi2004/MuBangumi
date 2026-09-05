import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/schedule_models.dart';
import '../state/schedule_controller.dart';

Future<void> showScheduleReminderSheet(
  BuildContext context, {
  required ScheduleItem item,
}) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (_) => _ScheduleReminderSheet(item: item),
);

class _ScheduleReminderSheet extends ConsumerStatefulWidget {
  const _ScheduleReminderSheet({required this.item});

  final ScheduleItem item;

  @override
  ConsumerState<_ScheduleReminderSheet> createState() =>
      _ScheduleReminderSheetState();
}

class _ScheduleReminderSheetState
    extends ConsumerState<_ScheduleReminderSheet> {
  late bool _enabled = widget.item.reminderEnabled;
  late TimeOfDay _time = TimeOfDay(
    hour: widget.item.reminderHour,
    minute: widget.item.reminderMinute,
  );
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final scheduled = widget.item.isScheduled;
    final day = scheduled ? weekdayLabel(widget.item.weekday!) : '待安排';
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('系统更新提醒', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              widget.item.displayName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _enabled && scheduled,
              onChanged: _saving || !scheduled
                  ? null
                  : (value) => setState(() => _enabled = value),
              secondary: Icon(
                _enabled && scheduled
                    ? Icons.notifications_active_rounded
                    : Icons.notifications_none_rounded,
              ),
              title: const Text('每周提醒'),
              subtitle: Text(scheduled ? '$day · 每部番可独立开关' : '先把这部番安排到具体星期'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              enabled: _enabled && scheduled && !_saving,
              leading: const Icon(Icons.schedule_rounded),
              title: const Text('提醒时间'),
              subtitle: Text('$day ${_time.format(context)}'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () async {
                final selected = await showTimePicker(
                  context: context,
                  initialTime: _time,
                  helpText: '选择每周提醒时间',
                );
                if (selected != null && mounted) {
                  setState(() => _time = selected);
                }
              },
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: .55),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _helpText,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _saving ? null : () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _saving || (!scheduled && _enabled) ? null : _save,
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_rounded),
                  label: Text(_saving ? '保存中…' : '保存'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String get _helpText {
    final platformNote = defaultTargetPlatform == TargetPlatform.windows
        ? 'Windows 会安排下一次通知，并在应用启动或恢复时续排。'
        : '系统会按所选星期和时间每周重复通知。';
    return '这是本机播出时间提醒，不依赖 RSS 是否已绑定。$platformNote'
        '受系统省电和勿扰设置影响，送达时间可能略有延迟。';
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final saved = await ref
        .read(scheduleProvider.notifier)
        .setReminder(
          widget.item.subjectId,
          enabled: _enabled,
          hour: _time.hour,
          minute: _time.minute,
        );
    if (!mounted) return;
    setState(() => _saving = false);
    if (saved) Navigator.pop(context);
  }
}
