import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

import '../../models/schedule_models.dart';
import '../storage/schedule_store.dart';

enum ReminderPermissionStatus { granted, denied, unsupported }

class ReminderPermissionResult {
  const ReminderPermissionResult(this.status, {this.message});

  final ReminderPermissionStatus status;
  final String? message;

  bool get granted => status == ReminderPermissionStatus.granted;
}

class ScheduleReminderTarget {
  const ScheduleReminderTarget({required this.season, required this.subjectId});

  final SeasonKey season;
  final int subjectId;
}

abstract interface class ScheduleReminderGateway {
  Future<ReminderPermissionResult> requestPermission();

  Future<void> syncSchedules(List<SeasonSchedule> schedules);
}

/// Returns the next occurrence strictly after [now].
@visibleForTesting
DateTime nextWeeklyReminder({
  required DateTime now,
  required int weekday,
  required int hour,
  required int minute,
}) {
  var daysAhead = (weekday - now.weekday + 7) % 7;
  DateTime atDay(int offset) => now is timezone.TZDateTime
      ? timezone.TZDateTime(
          now.location,
          now.year,
          now.month,
          now.day + offset,
          hour,
          minute,
        )
      : now.isUtc
      ? DateTime.utc(now.year, now.month, now.day + offset, hour, minute)
      : DateTime(now.year, now.month, now.day + offset, hour, minute);
  var candidate = atDay(daysAhead);
  if (!candidate.isAfter(now)) {
    daysAhead += 7;
    candidate = atDay(daysAhead);
  }
  return candidate;
}

class ScheduleReminderService implements ScheduleReminderGateway {
  ScheduleReminderService._() : _store = ScheduleStore.shared;

  @visibleForTesting
  ScheduleReminderService.test(this._store);

  static final shared = ScheduleReminderService._();

  static const _payloadPrefix = 'mubangumi:schedule:';
  static const _channelId = 'bangumi_weekly_updates';
  static const _channelName = '追番更新提醒';
  static const windowsReminderWeeks = 8;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final ScheduleStore _store;
  Future<void> _syncTail = Future<void>.value();
  final StreamController<ScheduleReminderTarget> _openedController =
      StreamController<ScheduleReminderTarget>.broadcast();

  Future<void>? _initializing;
  bool _ready = false;
  ScheduleReminderTarget? _pendingOpen;

  Stream<ScheduleReminderTarget> get openedTargets => _openedController.stream;

  bool get _supported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isWindows);

  Future<void> initialize() async {
    if (_ready || !_supported) return;
    final pending = _initializing ??= _initialize();
    try {
      await pending;
    } finally {
      if (identical(_initializing, pending)) _initializing = null;
    }
  }

  Future<void> _initialize() async {
    timezone_data.initializeTimeZones();
    final zone = await FlutterTimezone.getLocalTimezone();
    timezone.setLocalLocation(timezone.getLocation(zone.identifier));

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('ic_launcher_monochrome'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
      windows: WindowsInitializationSettings(
        appName: 'MuBangumi',
        appUserModelId: 'wweiyi.MuBangumi',
        guid: 'e44445e2-3470-4d4a-938a-bd05522facb2',
      ),
    );
    final initialized = await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (response) {
        _handlePayload(response.payload);
      },
    );
    if (initialized == false) {
      throw StateError('系统通知初始化失败');
    }
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true) {
      _handlePayload(launch?.notificationResponse?.payload);
    }
    _ready = true;
  }

  @override
  Future<ReminderPermissionResult> requestPermission() async {
    if (!_supported) {
      return const ReminderPermissionResult(
        ReminderPermissionStatus.unsupported,
        message: '当前平台暂不支持系统更新提醒',
      );
    }
    try {
      await initialize();
      bool granted;
      if (Platform.isAndroid) {
        granted =
            await _plugin
                .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin
                >()
                ?.requestNotificationsPermission() ??
            true;
      } else if (Platform.isIOS) {
        granted =
            await _plugin
                .resolvePlatformSpecificImplementation<
                  IOSFlutterLocalNotificationsPlugin
                >()
                ?.requestPermissions(alert: true, sound: true) ??
            false;
      } else {
        granted = true;
      }
      return ReminderPermissionResult(
        granted
            ? ReminderPermissionStatus.granted
            : ReminderPermissionStatus.denied,
        message: granted ? null : '未获得系统通知权限，请在系统设置中允许 MuBangumi 通知',
      );
    } catch (error) {
      return ReminderPermissionResult(
        ReminderPermissionStatus.unsupported,
        message: '系统通知不可用：${_errorText(error)}',
      );
    }
  }

  @override
  Future<void> syncSchedules(List<SeasonSchedule> schedules) {
    if (!_supported) return Future.value();
    // Cancellation and scheduling form one operation. A later request must
    // finish after the older one, including when the older operation fails.
    final snapshot = [
      for (final schedule in schedules)
        schedule.copyWith(items: List.unmodifiable(schedule.items)),
    ];
    final future = _syncTail.then((_) => _syncSchedules(snapshot));
    _syncTail = future.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return future;
  }

  Future<void> _syncSchedules(List<SeasonSchedule> schedules) async {
    await initialize();
    // Refresh after a device time-zone change while preserving local wall time.
    final zone = await FlutterTimezone.getLocalTimezone();
    timezone.setLocalLocation(timezone.getLocation(zone.identifier));

    final pending = await _plugin.pendingNotificationRequests();
    final storedIds = await _store.readReminderIds();
    final ownedIds = storedIds ?? <int>{};
    for (final request in pending) {
      // One-time upgrade: before ID tracking, weekly reminders were this app's
      // only local notifications. Adopt Windows' payload-less pending toasts,
      // including reminders whose season has already been deleted.
      final legacyWindowsReminder =
          storedIds == null && Platform.isWindows && request.payload == null;
      if (legacyWindowsReminder ||
          request.payload?.startsWith(_payloadPrefix) == true) {
        ownedIds.add(request.id);
      }
    }

    // A subject may have been copied to another season. The newest saved
    // quarter wins so one show never produces duplicate weekly notifications.
    final reminders = <int, (SeasonKey, ScheduleItem)>{};
    for (final schedule in schedules) {
      for (final item in schedule.items) {
        if (item.reminderEnabled && item.isScheduled) {
          reminders.putIfAbsent(item.subjectId, () => (schedule.season, item));
        }
      }
    }

    // Preserve other notification producers, even if a generated ID collides.
    final usedIds = {
      for (final request in pending)
        if (!ownedIds.contains(request.id)) request.id,
    };
    final planned = <int, (SeasonKey, ScheduleItem, int)>{};
    for (final entry in reminders.values) {
      final (season, item) = entry;
      for (
        var week = 0;
        week < (Platform.isWindows ? windowsReminderWeeks : 1);
        week++
      ) {
        var id = _notificationId(season, item.subjectId, week);
        while (!usedIds.add(id)) {
          id = (id + 1) & 0x7fffffff;
        }
        planned[id] = (season, item, week);
      }
    }

    // Persist BEFORE touching the OS. If cancellation/scheduling fails or the
    // process exits midway, the next reconciliation can still clean up every
    // attempted ID. Windows pending requests have no payload to recover it from.
    await _store.writeReminderIds({...ownedIds, ...planned.keys});
    for (final request in pending) {
      if (ownedIds.contains(request.id)) {
        await _plugin.cancel(id: request.id);
      }
    }
    final now = timezone.TZDateTime.now(timezone.local);
    for (final entry in planned.entries) {
      final (season, item, week) = entry.value;
      await _schedule(
        id: entry.key,
        season: season,
        item: item,
        week: week,
        now: now,
      );
    }
    await _store.writeReminderIds(planned.keys.toSet());
  }

  ScheduleReminderTarget? takePendingOpen() {
    final target = _pendingOpen;
    _pendingOpen = null;
    return target;
  }

  Future<void> _schedule({
    required int id,
    required SeasonKey season,
    required ScheduleItem item,
    required int week,
    required timezone.TZDateTime now,
  }) async {
    final next = nextWeeklyReminder(
      now: timezone.TZDateTime(
        now.location,
        now.year,
        now.month,
        now.day + week * 7,
        now.hour,
        now.minute,
        now.second,
        now.millisecond,
        now.microsecond,
      ),
      weekday: item.weekday!,
      hour: item.reminderHour,
      minute: item.reminderMinute,
    );
    final scheduled = timezone.TZDateTime(
      timezone.local,
      next.year,
      next.month,
      next.day,
      next.hour,
      next.minute,
    );
    await _plugin.zonedSchedule(
      id: id,
      title: '${item.displayName} 追番提醒',
      body: '到了你安排的追番时间，打开新番表查看进度与更新',
      scheduledDate: scheduled,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: '按每部番设置的星期和时间发送每周更新提醒',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          category: AndroidNotificationCategory.reminder,
        ),
        iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
        windows: WindowsNotificationDetails(subtitle: '每周追番提醒'),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: Platform.isWindows
          ? null
          : DateTimeComponents.dayOfWeekAndTime,
      payload: '$_payloadPrefix${season.id}:${item.subjectId}',
    );
  }

  void _handlePayload(String? payload) {
    if (payload == null || !payload.startsWith(_payloadPrefix)) return;
    final parts = payload.substring(_payloadPrefix.length).split(':');
    if (parts.length != 2) return;
    final subjectId = int.tryParse(parts[1]);
    if (subjectId == null || subjectId <= 0) return;
    final target = ScheduleReminderTarget(
      season: SeasonKey.fromId(parts[0]),
      subjectId: subjectId,
    );
    if (_openedController.hasListener) {
      _openedController.add(target);
    } else {
      _pendingOpen = target;
    }
  }

  int _notificationId(SeasonKey season, int subjectId, int week) {
    var hash = 0x811c9dc5;
    for (final unit
        in '${season.id}:$subjectId${week == 0 ? '' : ':$week'}'.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash & 0x7fffffff;
  }

  static String _errorText(Object error) => error
      .toString()
      .replaceFirst('Exception: ', '')
      .replaceFirst('Bad state: ', '');
}
