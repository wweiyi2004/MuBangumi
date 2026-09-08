import 'package:mubangumi/core/notifications/schedule_reminder_service.dart';
import 'package:mubangumi/core/storage/rss_store.dart';
import 'package:mubangumi/core/storage/schedule_store.dart';
import 'package:mubangumi/models/rss_models.dart';
import 'package:mubangumi/models/schedule_models.dart';

class MemorySchedules extends ScheduleStore {
  MemorySchedules() : super.test();
  final schedules = <String, SeasonSchedule>{};
  @override
  Future<SeasonSchedule> load(SeasonKey season) async =>
      schedules[season.id] ?? SeasonSchedule.empty(season);
  @override
  Future<List<SeasonKey>> listSeasons() async =>
      schedules.values.map((schedule) => schedule.season).toList();
  @override
  Future<List<SeasonSchedule>> loadAllSchedules() async =>
      schedules.values.toList();
  @override
  Future<void> save(SeasonSchedule schedule) async {
    schedules[schedule.season.id] = schedule;
  }

  @override
  Future<void> deleteSeason(SeasonKey season) async {
    schedules.remove(season.id);
  }
}

class MemoryScheduleReminders implements ScheduleReminderGateway {
  final syncs = <List<SeasonSchedule>>[];
  @override
  Future<ReminderPermissionResult> requestPermission() async =>
      const ReminderPermissionResult(ReminderPermissionStatus.granted);
  @override
  Future<void> syncSchedules(List<SeasonSchedule> schedules) async {
    syncs.add(schedules);
  }
}

class ScheduleRssStore extends RssStore {
  ScheduleRssStore() : super.test();
  @override
  Future<List<RssSource>> listSources() async => [];
  @override
  Future<List<RssBinding>> listBindings({
    int? subjectId,
    int? sourceId,
  }) async => const [
    RssBinding(id: 1, sourceId: 1, subjectId: 1, subjectName: '今日作品'),
  ];
  @override
  Future<Map<int, int>> unreadCountsBySubject() async => {1: 2};
  @override
  Future<int> totalUnread() async => 2;
}
