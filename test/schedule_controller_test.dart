import 'package:flutter_test/flutter_test.dart';
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
}

SeasonSchedule _schedule(SeasonKey season) => SeasonSchedule(
  season: season,
  items: const [
    ScheduleItem(
      subjectId: 1,
      name: 'Subject',
      nameCn: '条目',
      imageUrl: '',
      type: SubjectType.anime,
    ),
  ],
);

class _FakeScheduleStore extends ScheduleStore {
  _FakeScheduleStore(this.schedules) : super.test();

  final Map<String, SeasonSchedule> schedules;
  Object? loadError;

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
}

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('condition not reached');
}
