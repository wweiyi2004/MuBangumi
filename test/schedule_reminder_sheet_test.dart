import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/notifications/schedule_reminder_service.dart';
import 'package:mubangumi/core/storage/schedule_store.dart';
import 'package:mubangumi/models/schedule_models.dart';
import 'package:mubangumi/state/schedule_controller.dart';
import 'package:mubangumi/widgets/schedule_reminder_sheet.dart';

void main() {
  testWidgets('enables and saves a per-subject system reminder', (
    tester,
  ) async {
    final season = SeasonKey.current();
    const item = ScheduleItem(
      subjectId: 42,
      name: 'Reminder Show',
      nameCn: '提醒番剧',
      imageUrl: '',
      weekday: DateTime.thursday,
    );
    final store = _FakeScheduleStore(
      SeasonSchedule(season: season, items: const [item]),
    );
    final reminders = _FakeReminderGateway();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          scheduleStoreProvider.overrideWithValue(store),
          scheduleReminderProvider.overrideWithValue(reminders),
        ],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) {
              final state = ref.watch(scheduleProvider);
              return Scaffold(
                body: Center(
                  child: FilledButton(
                    onPressed: state.loading
                        ? null
                        : () => showScheduleReminderSheet(context, item: item),
                    child: const Text('打开提醒'),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开提醒'));
    await tester.pumpAndSettle();

    expect(find.text('系统更新提醒'), findsOneWidget);
    expect(find.text('提醒番剧'), findsOneWidget);
    expect(find.textContaining('周四'), findsWidgets);

    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(find.text('系统更新提醒'), findsNothing);
    expect(store.schedule.items.single.reminderEnabled, isTrue);
    expect(reminders.permissionRequests, 1);
    expect(reminders.syncCount, greaterThan(0));
  });
}

class _FakeScheduleStore extends ScheduleStore {
  _FakeScheduleStore(this.schedule) : super.test();

  SeasonSchedule schedule;

  @override
  Future<SeasonSchedule> load(SeasonKey season) async => schedule;

  @override
  Future<List<SeasonKey>> listSeasons() async => [schedule.season];

  @override
  Future<List<SeasonSchedule>> loadAllSchedules() async => [schedule];

  @override
  Future<void> save(SeasonSchedule value) async => schedule = value;
}

class _FakeReminderGateway implements ScheduleReminderGateway {
  int permissionRequests = 0;
  int syncCount = 0;

  @override
  Future<ReminderPermissionResult> requestPermission() async {
    permissionRequests++;
    return const ReminderPermissionResult(ReminderPermissionStatus.granted);
  }

  @override
  Future<void> syncSchedules(List<SeasonSchedule> schedules) async {
    syncCount++;
  }
}
