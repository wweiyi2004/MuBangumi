import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/notifications/schedule_reminder_service.dart';
import 'package:mubangumi/core/storage/schedule_store.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/models/schedule_models.dart';
import 'package:mubangumi/state/schedule_controller.dart';

void main() {
  test(
    'quarter batch keeps existing entries and per-day order, failure is retryable',
    () async {
      final season = SeasonKey.current();
      final store = _FakeScheduleStore({
        season.id: _schedule(season, weekday: 2),
      });
      final controller = ScheduleController(store);
      addTearDown(controller.dispose);
      await _waitFor(() => !controller.state.loading);
      Subject subject(int id) => Subject(
        id: id,
        name: 'New $id',
        nameCn: '',
        imageUrl: '',
        summary: '',
        episodeCount: 12,
        score: 0,
        rank: 0,
        date: '',
      );
      final subjects = [
        subject(1),
        subject(2),
        subject(3),
        subject(3),
        subject(4),
      ];
      store.failSave = true;
      final failed = await controller.addBatchToSeason(
        subjects,
        season,
        allowed: () => true,
        weekdays: {1: 7, 2: 2, 3: 2},
      );
      expect(failed.error, isNotNull);
      expect(controller.state.schedule.items, hasLength(1));
      store.failSave = false;
      final result = await controller.addBatchToSeason(
        subjects,
        season,
        allowed: () => true,
        weekdays: {1: 7, 2: 2, 3: 2},
      );
      expect(result.added, {2, 3, 4});
      expect(result.existing, {1});
      expect(controller.state.schedule.items.first.weekday, 2);
      expect(controller.state.schedule.itemsOn(2).map((e) => e.sortOrder), [
        0,
        1,
        2,
      ]);
      expect(controller.state.schedule.unscheduled.single.subjectId, 4);
      final again = await controller.addBatchToSeason(
        subjects,
        season,
        allowed: () => true,
      );
      expect(again.added, isEmpty);
      expect(controller.state.schedule.items, hasLength(4));
      final invalid = await controller.addBatchToSeason(
        [subject(5)],
        season,
        allowed: () => true,
        weekdays: {5: 8},
      );
      expect(invalid.error, isNotNull);
    },
  );

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
  test(
    'late reminder permission never changes a newly selected season',
    () async {
      final current = SeasonKey.current(),
          other = SeasonKey(year: SeasonKey.current().year + 1, quarter: 0);
      final store = _FakeScheduleStore({
        current.id: _schedule(current, weekday: 2),
        other.id: _schedule(other, weekday: 3),
      });
      final gate = Completer<ReminderPermissionResult>();
      final reminders = _FakeReminderGateway()..pendingPermission = gate.future;
      final controller = ScheduleController(store, reminders);
      addTearDown(controller.dispose);
      await _waitFor(() => !controller.state.loading);
      final enable = controller.setReminder(
        1,
        enabled: true,
        hour: 21,
        minute: 10,
        expectedSeason: current,
      );
      await controller.setSeason(other);
      gate.complete(
        const ReminderPermissionResult(ReminderPermissionStatus.granted),
      );
      expect(await enable, isFalse);
      expect(controller.state.season, other);
      expect(controller.state.schedule.items.single.reminderEnabled, isFalse);
    },
  );

  test(
    'removing an item while permission is pending cannot resurrect its reminder',
    () async {
      final current = SeasonKey.current();
      final store = _FakeScheduleStore({
        current.id: _schedule(current, weekday: 2),
      });
      final gate = Completer<ReminderPermissionResult>();
      final reminders = _FakeReminderGateway()..pendingPermission = gate.future;
      final controller = ScheduleController(store, reminders);
      addTearDown(controller.dispose);
      await _waitFor(() => !controller.state.loading);
      final enable = controller.setReminder(
        1,
        enabled: true,
        hour: 21,
        minute: 0,
      );
      await controller.removeSubject(1);
      gate.complete(
        const ReminderPermissionResult(ReminderPermissionStatus.granted),
      );
      expect(await enable, isFalse);
      expect(controller.state.schedule.items, isEmpty);
    },
  );

  for (final fail in [false, true]) {
    test(
      'season load waits for an accepted save without mixing quarters, failure=$fail',
      () async {
        final current = SeasonKey.current(),
            other = SeasonKey(year: SeasonKey.current().year + 1, quarter: 0);
        final store = _FakeScheduleStore({
          current.id: _schedule(current, weekday: 2),
          other.id: _schedule(other, weekday: 5),
        });
        final controller = ScheduleController(store);
        addTearDown(controller.dispose);
        await _waitFor(() => !controller.state.loading);
        final gate = Completer<void>();
        store.saveGate = gate.future;
        store.failSave = fail;
        final move = controller.moveItem(1, weekday: 3);
        final load = controller.setSeason(other);
        expect(controller.state.loading, isTrue);
        gate.complete();
        await move;
        expect(await load, isTrue);
        expect(controller.state.season, other);
        expect(controller.state.schedule.items.single.weekday, 5);
        expect(controller.state.saving, isFalse);
        expect(store.schedules[current.id]!.items.single.weekday, fail ? 2 : 3);
      },
    );
  }

  test(
    'failed save restores the original schedule and can be retried',
    () async {
      final current = SeasonKey.current();
      final store = _FakeScheduleStore({
        current.id: _schedule(current, weekday: 2),
      });
      final controller = ScheduleController(store);
      addTearDown(controller.dispose);
      await _waitFor(() => !controller.state.loading);
      store.failSave = true;
      await controller.moveItem(1, weekday: 3);
      expect(controller.state.schedule.items.single.weekday, 2);
      expect(controller.state.message, contains('保存新番表失败'));
      store.failSave = false;
      await controller.moveItem(1, weekday: 3);
      expect(store.schedules[current.id]!.items.single.weekday, 3);
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
  Future<void>? saveGate;
  bool failSave = false;
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
    await saveGate;
    if (failSave) throw StateError('disk full');
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
  Future<ReminderPermissionResult>? pendingPermission;
  final List<List<SeasonSchedule>> syncs = [];

  @override
  Future<ReminderPermissionResult> requestPermission() async {
    permissionRequests++;
    if (pendingPermission != null) return pendingPermission!;
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
