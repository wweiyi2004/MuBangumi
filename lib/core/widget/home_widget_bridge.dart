import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../../models/schedule_models.dart';

/// Syncs today's schedule + RSS unread counts to the Android home widget.
///
/// No-op on non-Android platforms (Windows/desktop intentionally unsupported).
class HomeWidgetBridge {
  HomeWidgetBridge._();

  static const androidProviderName = 'TodayScheduleWidgetProvider';

  static const _keyTitle = 'today_title';
  static const _keySummary = 'today_summary';
  static const _keyUnread = 'today_unread';
  static const _keyEmpty = 'today_empty';
  static const _keyLines = [
    'today_line1',
    'today_line2',
    'today_line3',
    'today_line4',
  ];

  static bool get isSupported =>
      !kIsWeb && (Platform.isAndroid /* || Platform.isIOS */ );

  /// Push snapshot used by [TodayScheduleWidgetProvider].
  static Future<void> sync({
    required SeasonSchedule schedule,
    required Map<int, int> unreadBySubject,
    int? totalUnread,
  }) async {
    if (!isSupported) return;
    try {
      final today = DateTime.now().weekday;
      final items = schedule.itemsOn(today);
      final unread = totalUnread ??
          unreadBySubject.values.fold<int>(0, (a, b) => a + b);
      final dayLabel = weekdayLabel(today);

      final title = '今日新番 · $dayLabel';
      final summary = items.isEmpty
          ? (unread > 0 ? '未读更新 $unread · 今天无排期' : '今天课表还是空的')
          : '今天 ${items.length} 部'
              '${unread > 0 ? ' · 未读 $unread' : ''}';

      await HomeWidget.saveWidgetData<String>(_keyTitle, title);
      await HomeWidget.saveWidgetData<String>(_keySummary, summary);
      await HomeWidget.saveWidgetData<int>(_keyUnread, unread);
      await HomeWidget.saveWidgetData<String>(
        _keyEmpty,
        '今天还没有安排 · 打开 App 加番',
      );

      for (var i = 0; i < _keyLines.length; i++) {
        if (i < items.length) {
          final item = items[i];
          final badge = unreadBySubject[item.subjectId] ?? 0;
          final prefix = badge > 0 ? '● ' : '· ';
          await HomeWidget.saveWidgetData<String>(
            _keyLines[i],
            '$prefix${item.displayName}',
          );
        } else {
          await HomeWidget.saveWidgetData<String>(_keyLines[i], '');
        }
      }

      await HomeWidget.updateWidget(
        name: androidProviderName,
        androidName: androidProviderName,
      );
    } catch (_) {
      // Widget is best-effort; never break the app.
    }
  }

  static Future<void> clear() async {
    if (!isSupported) return;
    try {
      await HomeWidget.saveWidgetData<String>(_keyTitle, '今日新番');
      await HomeWidget.saveWidgetData<String>(_keySummary, '打开 App 同步课表');
      await HomeWidget.saveWidgetData<int>(_keyUnread, 0);
      for (final key in _keyLines) {
        await HomeWidget.saveWidgetData<String>(key, '');
      }
      await HomeWidget.updateWidget(
        name: androidProviderName,
        androidName: androidProviderName,
      );
    } catch (_) {}
  }
}
