import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/notifications/schedule_reminder_service.dart';
import '../core/storage/schedule_store.dart';
import '../models/bangumi_models.dart';
import '../models/schedule_models.dart';
import '../models/library_batch.dart';

class ScheduleState {
  const ScheduleState({
    required this.season,
    this.schedule = const SeasonSchedule(
      season: SeasonKey(year: 0, quarter: 0),
    ),
    this.knownSeasons = const [],
    this.loading = true,
    this.saving = false,
    this.readFailed = false,
    this.message,
  });

  final SeasonKey season;
  final SeasonSchedule schedule;

  /// Seasons the user has opened/created (plus any already saved locally).
  final List<SeasonKey> knownSeasons;
  final bool loading;
  final bool saving;
  final bool readFailed;
  final String? message;

  ScheduleState copyWith({
    SeasonKey? season,
    SeasonSchedule? schedule,
    List<SeasonKey>? knownSeasons,
    bool? loading,
    bool? saving,
    bool? readFailed,
    String? message,
    bool clearMessage = false,
  }) => ScheduleState(
    season: season ?? this.season,
    schedule: schedule ?? this.schedule,
    knownSeasons: knownSeasons ?? this.knownSeasons,
    loading: loading ?? this.loading,
    saving: saving ?? this.saving,
    readFailed: readFailed ?? this.readFailed,
    message: clearMessage ? null : message ?? this.message,
  );
}

class ScheduleController extends StateNotifier<ScheduleState> {
  ScheduleController(this._store, [this._reminders])
    : super(ScheduleState(season: SeasonKey.current())) {
    load(SeasonKey.current());
  }

  final ScheduleStore _store;
  final ScheduleReminderGateway? _reminders;

  /// Guards rapid season switches: stale loads are dropped instead of
  /// overwriting a newer season's table.
  int _loadGeneration = 0;
  int _reminderSyncGeneration = 0;
  int _mutationGeneration = 0;
  Future<void> _writes = Future.value();
  Future<void> _reminderWrites = Future.value();
  bool _pausedForImport = false;

  Future<void> pauseForImport() async {
    _pausedForImport = true;
    _loadGeneration++;
    _mutationGeneration++;
    _reminderSyncGeneration++;
    await _writes;
    await _reminderWrites;
    await _store.flushWrites();
  }

  Future<bool> resumeAfterImport() async {
    _pausedForImport = false;
    if (!mounted) return false;
    state = state.copyWith(knownSeasons: [], saving: false);
    final loaded = await load(state.season, reconcileReminders: false);
    final reminders = await syncReminders(reportErrors: false);
    return loaded && reminders;
  }

  bool _rejectBusy() {
    if (!mounted || _pausedForImport) return true;
    if (state.readFailed) {
      state = state.copyWith(message: '新番表尚未读取成功，请先重试');
      return true;
    }
    if (!state.loading && !state.saving) return false;
    state = state.copyWith(message: '正在保存或切换季度，请稍后再操作');
    return true;
  }

  Future<bool> load(
    SeasonKey season, {
    bool rememberEmpty = false,
    bool reconcileReminders = true,
  }) async {
    if (!mounted || _pausedForImport) return false;
    final generation = ++_loadGeneration;
    state = state.copyWith(
      loading: true,
      readFailed: false,
      clearMessage: true,
    );
    try {
      await _writes;
      if (!mounted || generation != _loadGeneration) return false;
      final results = await Future.wait([
        _store.load(season),
        _store.listSeasons(),
      ]);
      if (!mounted || generation != _loadGeneration) {
        return false; // Stale load; drop.
      }
      final schedule = results[0] as SeasonSchedule;
      final saved = results[1] as List<SeasonKey>;
      final known = _mergeKnownSeasons([
        ...state.knownSeasons,
        ...saved,
        season,
        SeasonKey.current(),
      ]);
      // Ensure empty new seasons still appear in the picker after first open.
      if (rememberEmpty && schedule.items.isEmpty && !saved.contains(season)) {
        await _store.save(schedule);
      }
      if (!mounted || generation != _loadGeneration) {
        return false; // Stale load; drop.
      }
      state = state.copyWith(
        season: season,
        schedule: schedule,
        knownSeasons: known,
        loading: false,
        readFailed: false,
      );
      if (reconcileReminders) await syncReminders(reportErrors: false);
      return true;
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return false;
      final alignedSchedule = state.schedule.season == state.season
          ? state.schedule
          : SeasonSchedule.empty(state.season);
      state = state.copyWith(
        schedule: alignedSchedule,
        loading: false,
        message: '加载季度表失败：${_errorText(error)}',
        readFailed: true,
      );
      return false;
    }
  }

  Future<bool> setSeason(SeasonKey season) => load(season, rememberEmpty: true);

  /// Create/open an arbitrary year-quarter table (local only).
  Future<void> createSeason(SeasonKey season) async {
    if (await load(season, rememberEmpty: true) && mounted) {
      state = state.copyWith(message: '已打开 ${season.label}');
    }
  }

  Future<void> deleteCurrentSeason({SeasonKey? expectedSeason}) async {
    if (_rejectBusy()) return;
    if ((expectedSeason != null && expectedSeason != state.season) ||
        state.schedule.items.isNotEmpty) {
      state = state.copyWith(message: '季度已变化或表中仍有作品，只能删除当前空表');
      return;
    }
    final season = state.season;
    final generation = ++_loadGeneration;
    state = state.copyWith(loading: true);
    final deletion = Future<void>.sync(() => _store.deleteSeason(season));
    _writes = deletion.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    try {
      await deletion;
    } catch (error) {
      if (mounted && generation == _loadGeneration) {
        state = state.copyWith(
          loading: false,
          message: '删除季度表失败：${_errorText(error)}',
        );
      }
      return;
    }
    if (!mounted || generation != _loadGeneration) return;
    final remaining = [
      for (final key in state.knownSeasons)
        if (key != season) key,
    ];
    final next = remaining.isNotEmpty ? remaining.first : SeasonKey.current();
    state = state.copyWith(knownSeasons: remaining);
    final followUp = _loadGeneration + 1;
    final loaded = await load(next);
    if (!mounted || followUp != _loadGeneration) return;
    if (loaded) {
      state = state.copyWith(message: '已删除 ${season.label}');
    } else {
      state = state.copyWith(
        season: next,
        schedule: SeasonSchedule.empty(next),
        knownSeasons: remaining,
      );
    }
  }

  List<SeasonKey> _mergeKnownSeasons(Iterable<SeasonKey> raw) {
    final map = <String, SeasonKey>{};
    for (final key in raw) {
      if (key.year < 1990 || key.year > 2100) continue;
      if (key.quarter < 0 || key.quarter > 3) continue;
      map[key.id] = key;
    }
    final list = map.values.toList()
      ..sort((a, b) {
        final byYear = b.year.compareTo(a.year);
        if (byYear != 0) return byYear;
        return b.quarter.compareTo(a.quarter);
      });
    return list;
  }

  Future<void> addSubject(Subject subject, {int? weekday}) async {
    if (_rejectBusy() || subject.id <= 0) return;
    final current = state.schedule;
    if (current.containsSubject(subject.id)) {
      state = state.copyWith(message: '已在本季新番表中');
      return;
    }
    final sortOrder = weekday == null
        ? current.unscheduled.length
        : current.itemsOn(weekday).length;
    final items = [
      ...current.items,
      ScheduleItem.fromSubject(subject, weekday: weekday, sortOrder: sortOrder),
    ];
    final place = weekday == null ? '待安排' : weekdayLabel(weekday);
    await _persist(
      current.copyWith(items: items),
      message: '已加入$place：${subject.displayName}',
    );
  }

  Future<void> addCollection(UserCollection collection, {int? weekday}) =>
      addSubject(collection.subject, weekday: weekday);

  Future<SeasonSchedule> inspectBatchSeason(SeasonKey season) async {
    await _writes;
    return _store.load(season);
  }

  /// A bulk addition is one local row write and one reminder reconciliation.
  /// Existing entries keep their weekday, position, notes and reminder settings.
  Future<ScheduleBatchAddResult> addBatchToSeason(
    List<Subject> subjects,
    SeasonKey season, {
    int? weekday,
    required bool Function() allowed,
    Map<int, int> weekdays = const {},
  }) async {
    if (_rejectBusy()) {
      return const ScheduleBatchAddResult(error: '正在保存或切换新番表，请稍后重试');
    }
    if (season.year < 1990 ||
        season.year > 2100 ||
        season.quarter < 0 ||
        season.quarter > 3 ||
        (weekday != null && (weekday < 1 || weekday > 7)) ||
        weekdays.values.any((day) => day < 1 || day > 7)) {
      return const ScheduleBatchAddResult(error: '季度或星期无效');
    }
    final generation = _loadGeneration;
    final mutation = ++_mutationGeneration;
    state = state.copyWith(saving: true, clearMessage: true);
    SeasonSchedule? updated;
    final existingKnown = <int>{};
    final work = Future<ScheduleBatchAddResult>.sync(() async {
      if (!allowed()) return const ScheduleBatchAddResult(stopped: true);
      final current = await _store.load(season);
      if (!allowed()) return const ScheduleBatchAddResult(stopped: true);
      final added = <int>{}, existing = existingKnown;
      final items = [...current.items];
      final orders = <int?, int>{
        null: current.unscheduled.length,
        for (var day = 1; day <= 7; day++) day: current.itemsOn(day).length,
      };
      for (final subject in subjects) {
        if (subject.id <= 0) continue;
        if (added.contains(subject.id)) continue;
        if (items.any((item) => item.subjectId == subject.id)) {
          existing.add(subject.id);
          continue;
        }
        final day = weekdays[subject.id] ?? weekday;
        items.add(
          ScheduleItem.fromSubject(
            subject,
            weekday: day,
            sortOrder: orders[day]!,
          ),
        );
        orders[day] = orders[day]! + 1;
        added.add(subject.id);
      }
      if (added.isEmpty) return ScheduleBatchAddResult(existing: existing);
      if (!allowed()) return const ScheduleBatchAddResult(stopped: true);
      updated = current.copyWith(items: items);
      await _store.save(updated!);
      return ScheduleBatchAddResult(added: added, existing: existing);
    });
    _writes = work.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    ScheduleBatchAddResult result;
    try {
      result = await work;
    } catch (error) {
      result = ScheduleBatchAddResult(
        error: '保存季度表失败：${_errorText(error)}',
        existing: existingKnown,
      );
    }
    if (!mounted) return result;
    state = state.copyWith(
      saving: false,
      schedule:
          updated != null &&
              result.error == null &&
              generation == _loadGeneration &&
              state.season == season
          ? updated
          : null,
      knownSeasons: result.added.isNotEmpty
          ? _mergeKnownSeasons([...state.knownSeasons, season])
          : null,
    );
    if (result.added.isNotEmpty && !await syncReminders(reportErrors: false)) {
      if (mounted && mutation == _mutationGeneration) {
        state = state.copyWith(message: '新番表已保存，但系统提醒暂未同步');
      }
      return ScheduleBatchAddResult(
        added: result.added,
        existing: result.existing,
        warning: '新番表已保存，但系统提醒暂未同步，可稍后重试提醒同步',
      );
    }
    return result;
  }

  Future<void> removeSubject(int subjectId) async {
    if (_rejectBusy()) return;
    final removed = state.schedule.items
        .where((item) => item.subjectId == subjectId)
        .map((item) => item.displayName)
        .firstOrNull;
    final items = [
      for (final item in state.schedule.items)
        if (item.subjectId != subjectId) item,
    ];
    await _persist(
      state.schedule.copyWith(items: items),
      message: removed == null ? '已删除安排' : '已删除安排：$removed',
    );
  }

  /// Move to a weekday (`1–7`) or `null` 待安排. Optional insert index in that day.
  Future<void> setWeekday(int subjectId, int? weekday, {int? insertIndex}) =>
      moveItem(subjectId, weekday: weekday, insertIndex: insertIndex);

  /// Place [subjectId] within the current season (drag-and-drop / menu).
  Future<void> moveItem(int subjectId, {int? weekday, int? insertIndex}) async {
    if (_rejectBusy()) return;
    final current = state.schedule;
    final moving = current.items
        .where((item) => item.subjectId == subjectId)
        .firstOrNull;
    if (moving == null) return;

    final others = [
      for (final item in current.items)
        if (item.subjectId != subjectId) item,
    ];

    List<ScheduleItem> bucket(int? day) {
      final list = [
        for (final item in others)
          if (day == null ? !item.isScheduled : item.weekday == day) item,
      ]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      return list;
    }

    final rebuilt = <ScheduleItem>[];

    for (var day = DateTime.monday; day <= DateTime.sunday; day++) {
      final dayItems = bucket(day);
      if (weekday == day) {
        final at = (insertIndex ?? dayItems.length).clamp(0, dayItems.length);
        dayItems.insert(at, moving.copyWith(weekday: day, sortOrder: at));
      }
      for (var i = 0; i < dayItems.length; i++) {
        rebuilt.add(dayItems[i].copyWith(weekday: day, sortOrder: i));
      }
    }

    final pool = bucket(null);
    if (weekday == null) {
      final at = (insertIndex ?? pool.length).clamp(0, pool.length);
      pool.insert(
        at,
        moving.copyWith(
          clearWeekday: true,
          sortOrder: at,
          reminderEnabled: false,
        ),
      );
    }
    for (var i = 0; i < pool.length; i++) {
      rebuilt.add(pool[i].copyWith(clearWeekday: true, sortOrder: i));
    }

    final place = weekday == null ? '待安排' : weekdayLabel(weekday);
    final reminderSuffix = weekday == null && moving.reminderEnabled
        ? '，系统提醒已关闭'
        : '';
    await _persist(
      current.copyWith(items: rebuilt),
      message: '已改到$place$reminderSuffix',
    );
  }

  Future<void> reorderOnDay(int weekday, List<int> subjectIds) async {
    if (_rejectBusy()) return;
    final order = {
      for (var index = 0; index < subjectIds.length; index++)
        subjectIds[index]: index,
    };
    final items = [
      for (final item in state.schedule.items)
        if (item.weekday == weekday && order.containsKey(item.subjectId))
          item.copyWith(sortOrder: order[item.subjectId]!)
        else
          item,
    ];
    await _persist(state.schedule.copyWith(items: items));
  }

  Future<bool> setReminder(
    int subjectId, {
    required bool enabled,
    required int hour,
    required int minute,
    SeasonKey? expectedSeason,
  }) async {
    if (_rejectBusy()) return false;
    final generation = _loadGeneration;
    final mutationGeneration = _mutationGeneration;
    final season = state.season;
    if (expectedSeason != null && expectedSeason != season) {
      state = state.copyWith(message: '季度已变化，请重新打开提醒设置');
      return false;
    }
    final item = state.schedule.items
        .where((candidate) => candidate.subjectId == subjectId)
        .firstOrNull;
    if (item == null) {
      state = state.copyWith(message: '这部番已不在当前新番表中');
      return false;
    }
    if (enabled && !item.isScheduled) {
      state = state.copyWith(message: '请先把这部番安排到具体星期');
      return false;
    }
    if (enabled) {
      final permission = await _reminders?.requestPermission();
      if (!mounted) return false;
      if (generation != _loadGeneration ||
          season != state.season ||
          mutationGeneration != _mutationGeneration ||
          state.loading ||
          state.saving) {
        state = state.copyWith(message: '安排已变化，请重新打开提醒设置');
        return false;
      }
      if (permission != null && !permission.granted) {
        state = state.copyWith(message: permission.message ?? '未获得系统通知权限');
        return false;
      }
    }

    final safeHour = hour.clamp(0, 23);
    final safeMinute = minute.clamp(0, 59);
    final items = [
      for (final candidate in state.schedule.items)
        if (candidate.subjectId == subjectId)
          candidate.copyWith(
            reminderEnabled: enabled,
            reminderHour: safeHour,
            reminderMinute: safeMinute,
          )
        else
          candidate,
    ];
    final formatted =
        '${safeHour.toString().padLeft(2, '0')}:'
        '${safeMinute.toString().padLeft(2, '0')}';
    return _persist(
      state.schedule.copyWith(items: items),
      message: enabled
          ? '已开启${item.displayName}的每周更新提醒 · $formatted'
          : '已关闭${item.displayName}的系统更新提醒',
    );
  }

  /// Reconciles all saved quarters with native scheduled notifications.
  Future<bool> syncReminders({bool reportErrors = true}) async {
    if (!mounted || _pausedForImport) return true;
    final reminders = _reminders;
    if (reminders == null) return true;
    final generation = ++_reminderSyncGeneration;
    try {
      final schedules = await _store.loadAllSchedules();
      // A slow database read must not submit stale settings after a newer read.
      if (!mounted || generation != _reminderSyncGeneration) return true;
      final syncing = reminders.syncSchedules(schedules);
      _reminderWrites = Future.wait([
        _reminderWrites,
        syncing,
      ]).then<void>((_) {}, onError: (Object _, StackTrace _) {});
      await syncing;
      return true;
    } catch (error) {
      if (mounted && reportErrors && generation == _reminderSyncGeneration) {
        state = state.copyWith(message: '同步系统更新提醒失败：${_errorText(error)}');
      }
      return false;
    }
  }

  void clearMessage() => state = state.copyWith(clearMessage: true);

  Future<bool> _persist(SeasonSchedule schedule, {String? message}) async {
    if (_rejectBusy()) return false;
    final previous = state.schedule;
    final generation = _loadGeneration;
    final mutation = ++_mutationGeneration;
    state = state.copyWith(
      schedule: schedule,
      saving: true,
      clearMessage: true,
    );
    final saved = Future<void>.sync(() => _store.save(schedule));
    _writes = saved.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    try {
      await saved;
    } catch (error) {
      if (mounted) {
        state = state.copyWith(
          saving: false,
          schedule: identical(state.schedule, schedule) ? previous : null,
          message: generation == _loadGeneration
              ? '保存新番表失败：${_errorText(error)}'
              : null,
        );
      }
      return false;
    }
    if (!mounted) return true;
    state = state.copyWith(
      saving: false,
      message: generation == _loadGeneration ? message : null,
    );
    if (!await syncReminders(reportErrors: false) &&
        mounted &&
        generation == _loadGeneration &&
        mutation == _mutationGeneration) {
      state = state.copyWith(message: '设置已保存，但系统更新提醒暂未同步；下次启动会重试');
    }
    return true;
  }

  String _errorText(Object error) => error
      .toString()
      .replaceFirst('Exception: ', '')
      .replaceFirst('FormatException: ', '');
}

final scheduleStoreProvider = Provider<ScheduleStore>(
  (ref) => ScheduleStore.shared,
);

final scheduleReminderProvider = Provider<ScheduleReminderGateway>(
  (ref) => ScheduleReminderService.shared,
);

final scheduleProvider =
    StateNotifierProvider<ScheduleController, ScheduleState>((ref) {
      return ScheduleController(
        ref.watch(scheduleStoreProvider),
        ref.watch(scheduleReminderProvider),
      );
    });
