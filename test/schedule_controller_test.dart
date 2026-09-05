import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/notifications/schedule_reminder_service.dart';
import 'package:mubangumi/core/storage/schedule_store.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/models/schedule_models.dart';
import 'package:mubangumi/state/schedule_controller.dart';

void main() {
  test('initial load failure still aligns the empty schedule', () async {
    final current = SeasonKey.current();
    final store = _FakeScheduleStore({})
      ..loadError = Exception('database unavailable');
    final controller = ScheduleController(store);
    addTearDown(controller.dispose);
    await _waitFor(() => !controller.state.loading);

    expect(controller.state.season, current);
    expect(controller.state.schedule.season, current);
    expect(controller.state.schedule.items, isEmpty);
    expect(controller.state.message, contains('database unavailable'));
  });

  test('failed season switch keeps season and schedule aligned', () async {
    final current = SeasonKey.current();
    final target = SeasonKey(year: current.year + 1, quarter: current.quarter);
    final store = _FakeScheduleStore({current.id: _schedule(current)});
    final controller = ScheduleController(store);
    addTearDown(controller.dispose);
    await _waitFor(() => !controller.state.loading);

    store.loadError = Exception('database unavailable');
    final switched = await controller.setSeason(target);

    expect(switched, isFalse);
    expect(controller.state.season, current);
    expect(controller.state.schedule.season, current);
    expect(controller.state.schedule.items, hasLength(1));
    expect(controller.state.message, contains('database unavailable'));
  });

  test('failed season creation does not announce success', () async {
    final current = SeasonKey.current();
    final target = SeasonKey(year: current.year + 1, quarter: current.quarter);
    final store = _FakeScheduleStore({current.id: _schedule(current)});
    final controller = ScheduleController(store);
    addTearDown(controller.dispose);
    await _waitFor(() => !controller.state.loading);

    store.loadError = Exception('database unavailable');
    await controller.createSeason(target);

    expect(controller.state.season, current);
    expect(controller.state.knownSeasons, isNot(contains(target)));
    expect(controller.state.message, contains('加载季度表失败'));
    expect(controller.state.message, isNot(contains('已打开')));
  });

  test(
    'enables one subject reminder after permission and reschedules',
    () async {
      final current = SeasonKey.current();
      final store = _FakeScheduleStore({
        current.id: _schedule(current, weekday: DateTime.wednesday),
      });
      final reminders = _FakeReminderGateway();
      final controller = ScheduleController(store, reminders);
      addTearDown(controller.dispose);
      await _waitFor(() => !controller.state.loading);
      reminders.syncs.clear();

      final saved = await controller.setReminder(
        1,
        enabled: true,
        hour: 19,
        minute: 45,
      );

      expect(saved, isTrue);
      expect(reminders.permissionRequests, 1);
      expect(reminders.syncs, hasLength(1));
      final item = controller.state.schedule.items.single;
      expect(item.reminderEnabled, isTrue);
      expect(item.reminderHour, 19);
      expect(item.reminderMinute, 45);
    },
  );

  test('permission denial leaves the subject reminder disabled', () async {
    final current = SeasonKey.current();
    final store = _FakeScheduleStore({
      current.id: _schedule(current, weekday: DateTime.wednesday),
    });
    final reminders = _FakeReminderGateway(permissionGranted: false);
    final controller = ScheduleController(store, reminders);
    addTearDown(controller.dispose);
    await _waitFor(() => !controller.state.loading);
    reminders.syncs.clear();

    final saved = await controller.setReminder(
      1,
      enabled: true,
      hour: 20,
      minute: 0,
    );

    expect(saved, isFalse);
    expect(controller.state.schedule.items.single.reminderEnabled, isFalse);
    expect(controller.state.message, contains('系统设置'));
    expect(reminders.syncs, isEmpty);
  });

  test(
    'a delayed reminder snapshot cannot overwrite a newer season deletion',
    () async {
      final current = SeasonKey.current();
      final oldSchedule = _schedule(current, weekday: DateTime.wednesday);
      final store = _FakeScheduleStore({current.id: oldSchedule});
      final reminders = _FakeReminderGateway();
      final controller = ScheduleController(store, reminders);
      addTearDown(controller.dispose);
      await _waitFor(() => !controller.state.loading);
      await controller.syncReminders();
      reminders.syncs.clear();

      final oldRead = Completer<List<SeasonSchedule>>();
      store.loadAllOverride = () => oldRead.future;
      final oldSync = controller.syncReminders();
      store.loadAllOverride = null;
      store.schedules.clear();
      await controller.syncReminders();
      oldRead.complete([oldSchedule]);
      await oldSync;

      expect(reminders.syncs, hasLength(1));
      expect(reminders.syncs.single, isEmpty);
    },
  );

  test(
    'moving a reminded subject to the pool disables and reconciles it',
    () async {
      final current = SeasonKey.current();
      final schedule = _schedule(current, weekday: DateTime.wednesday);
      final store = _FakeScheduleStore({
        current.id: schedule.copyWith(
          items: [schedule.items.single.copyWith(reminderEnabled: true)],
        ),
      });
      final reminders = _FakeReminderGateway();
      final controller = ScheduleController(store, reminders);
      addTearDown(controller.dispose);
      await _waitFor(() => !controller.state.loading);
      reminders.syncs.clear();

      await controller.moveItem(1, weekday: null);

      final item = controller.state.schedule.items.single;
      expect(item.weekday, isNull);
      expect(item.reminderEnabled, isFalse);
      expect(controller.state.message, contains('系统提醒已关闭'));
      expect(reminders.syncs, hasLength(1));
    },
  );
}

SeasonSchedule _schedule(SeasonKey season, {int? weekday}) => SeasonSchedule(
  season: season,
  items: [
    ScheduleItem(
      subjectId: 1,
      name: 'Subject',
      nameCn: '条目',
      imageUrl: '',
      type: SubjectType.anime,
      weekday: weekday,
    ),
  ],
);

class _FakeScheduleStore extends ScheduleStore {
  _FakeScheduleStore(this.schedules) : super.test();

  final Map<String, SeasonSchedule> schedules;
  Object? loadError;
  Future<List<SeasonSchedule>> Function()? loadAllOverride;

  @override
  Future<SeasonSchedule> load(SeasonKey season) async {
    final error = loadError;
    if (error != null) throw error;
    return schedules[season.id] ?? SeasonSchedule.empty(season);
  }

  @override
  Future<List<SeasonKey>> listSeasons() async => [
    for (final schedule in schedules.values) schedule.season,
  ];

  @override
  Future<void> save(SeasonSchedule schedule) async {
    schedules[schedule.season.id] = schedule;
  }

  @override
  Future<List<SeasonSchedule>> loadAllSchedules() async {
    final loader = loadAllOverride;
    return loader != null ? loader() : schedules.values.toList();
  }
}

class _FakeReminderGateway implements ScheduleReminderGateway {
  _FakeReminderGateway({this.permissionGranted = true});

  final bool permissionGranted;
  int permissionRequests = 0;
  final List<List<SeasonSchedule>> syncs = [];

  @override
  Future<ReminderPermissionResult> requestPermission() async {
    permissionRequests++;
    return ReminderPermissionResult(
      permissionGranted
          ? ReminderPermissionStatus.granted
          : ReminderPermissionStatus.denied,
      message: permissionGranted ? null : '请在系统设置中允许通知',
    );
  }

  @override
  Future<void> syncSchedules(List<SeasonSchedule> schedules) async {
    syncs.add(schedules);
  }
}

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('condition not reached');
}
