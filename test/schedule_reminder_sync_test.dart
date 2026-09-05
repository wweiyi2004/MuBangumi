import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/notifications/schedule_reminder_service.dart';
import 'package:mubangumi/core/storage/schedule_store.dart';
import 'package:mubangumi/models/schedule_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const notificationChannel = MethodChannel(
    'dexterous.com/flutter/local_notifications',
  );
  const timezoneChannel = MethodChannel('flutter_timezone');
  final pending = <int, Map<String, Object?>>{};
  late _MemoryReminderStore store;
  late ScheduleReminderService service;
  Completer<Object?>? pendingGate;
  Completer<void>? pendingEntered;
  var failSchedule = false;
  var failCancel = false;
  final season = SeasonKey.current();
  final enabled = SeasonSchedule(
    season: season,
    items: const [
      ScheduleItem(
        subjectId: 42,
        name: 'Review',
        nameCn: '',
        imageUrl: '',
        weekday: 1,
        reminderEnabled: true,
      ),
    ],
  );

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    store = _MemoryReminderStore();
    service = ScheduleReminderService.test(store);
    pending.clear();
    pendingGate = null;
    pendingEntered = null;
    failSchedule = false;
    failCancel = false;
    messenger.setMockMethodCallHandler(
      timezoneChannel,
      (_) async => 'Asia/Shanghai',
    );
    messenger.setMockMethodCallHandler(notificationChannel, (call) async {
      switch (call.method) {
        case 'initialize':
          return true;
        case 'getNotificationAppLaunchDetails':
          return {'notificationLaunchedApp': false};
        case 'pendingNotificationRequests':
          final blocker = pendingGate;
          if (blocker != null) {
            pendingGate = null;
            pendingEntered!.complete();
            return blocker.future;
          }
          return pending.values.toList();
        case 'cancel':
          if (failCancel) throw PlatformException(code: 'cancel_failed');
          pending.remove((call.arguments as Map)['id']);
          return null;
        case 'zonedSchedule':
          final args = call.arguments as Map;
          final id = args['id'] as int;
          // Match the Windows plugin: pending requests contain IDs, no payload.
          pending[id] = {
            'id': id,
            'title': null,
            'body': null,
            'payload': null,
          };
          if (failSchedule) throw PlatformException(code: 'schedule_failed');
          return null;
      }
      throw StateError('Unexpected method ${call.method}');
    });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(timezoneChannel, null);
    messenger.setMockMethodCallHandler(notificationChannel, null);
  });

  test(
    'removes payload-less notifications after restart and season deletion',
    () async {
      await service.syncSchedules([enabled]);
      expect(pending, hasLength(1));
      final restarted = ScheduleReminderService.test(store);
      await restarted.syncSchedules([]);
      expect(pending, isEmpty);
      expect(store.ids, isEmpty);
    },
  );

  test(
    'rescheduling replaces the existing payload-less notification',
    () async {
      await service.syncSchedules([enabled]);
      final id = pending.keys.single;
      await service.syncSchedules([
        enabled.copyWith(
          items: [enabled.items.single.copyWith(reminderHour: 21)],
        ),
      ]);
      expect(pending.keys, [id]);
      expect(store.ids, {id});
      await service.syncSchedules([
        enabled.copyWith(
          items: [enabled.items.single.copyWith(reminderEnabled: false)],
        ),
      ]);
      expect(pending, isEmpty);
    },
  );

  test('a newer disable waits for an older reconciliation and wins', () async {
    await service.syncSchedules([enabled]);
    final blocker = Completer<Object?>();
    pendingGate = blocker;
    pendingEntered = Completer<void>();
    final oldSync = service.syncSchedules([enabled]);
    await pendingEntered!.future;
    final newSync = service.syncSchedules([]);
    blocker.complete(pending.values.toList());
    await Future.wait([oldSync, newSync]);
    expect(pending, isEmpty);
    expect(store.ids, isEmpty);
  });

  test(
    'a partial scheduling failure remains cancellable after restart',
    () async {
      failSchedule = true;
      await expectLater(
        service.syncSchedules([enabled]),
        throwsA(isA<PlatformException>()),
      );
      expect(pending, hasLength(1));
      expect(store.ids, pending.keys.toSet());
      failSchedule = false;
      await ScheduleReminderService.test(store).syncSchedules([]);
      expect(pending, isEmpty);
    },
  );

  test(
    'failed cancellation retains ownership and does not poison the queue',
    () async {
      await service.syncSchedules([enabled]);
      failCancel = true;
      await expectLater(
        service.syncSchedules([]),
        throwsA(isA<PlatformException>()),
      );
      expect(store.ids, pending.keys.toSet());
      failCancel = false;
      await service.syncSchedules([]);
      expect(pending, isEmpty);
    },
  );

  test(
    'ownership must be durable before scheduling any notification',
    () async {
      store.failWrites = true;
      await expectLater(service.syncSchedules([enabled]), throwsStateError);
      expect(pending, isEmpty);
      store.failWrites = false;
      await service.syncSchedules([enabled]);
      expect(pending, hasLength(1));
    },
  );

  test(
    'unrelated notifications survive cancellation and ID collisions',
    () async {
      await service.syncSchedules([enabled]);
      final foreignId = pending.keys.single;
      // Simulate a different producer owning the hash this reminder would use.
      store.ids = {};
      await service.syncSchedules([enabled]);
      expect(pending, hasLength(2));
      expect(store.ids, isNot(contains(foreignId)));
      await service.syncSchedules([]);
      expect(pending.keys, [foreignId]);
    },
  );

  test(
    'first Windows upgrade adopts pre-ledger reminders from deleted seasons',
    () async {
      store.ids = null;
      pending[123] = {'id': 123, 'title': null, 'body': null, 'payload': null};
      await service.syncSchedules([]);
      expect(pending, isEmpty);
      expect(store.ids, isEmpty);
    },
    skip: !Platform.isWindows,
  );
}

class _MemoryReminderStore extends ScheduleStore {
  _MemoryReminderStore() : super.test();

  Set<int>? ids = {};
  bool failWrites = false;

  @override
  Future<Set<int>?> readReminderIds() async => ids?.toSet();

  @override
  Future<void> writeReminderIds(Set<int> value) async {
    if (failWrites) throw StateError('database unavailable');
    ids = value.toSet();
  }
}
