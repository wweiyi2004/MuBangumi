import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/storage/browsing_store.dart';
import '../core/storage/pending_personal_writes.dart';
import '../core/backup/backup_archive.dart';
import '../models/schedule_view.dart';

class ScheduleViewState {
  const ScheduleViewState({this.selected, this.loading = true, this.error});
  final ScheduleView? selected;
  final bool loading;
  final String? error;
}

final scheduleViewProvider = StateNotifierProvider.autoDispose
    .family<ScheduleViewController, ScheduleViewState, int>(
      (ref, owner) => ScheduleViewController(
        ref.watch(scheduleViewRepositoryProvider),
        owner,
      ),
    );

class ScheduleViewController extends StateNotifier<ScheduleViewState> {
  ScheduleViewController(this.repository, this.ownerId)
    : super(const ScheduleViewState()) {
    unawaited(load());
  }
  final ScheduleViewRepository repository;
  final int ownerId;
  int _generation = 0;
  Future<void> _writes = Future.value();

  Future<void> load() async {
    if (!mounted) return;
    final generation = ++_generation;
    try {
      final selected = await repository.readScheduleView(ownerId);
      if (mounted && generation == _generation) {
        state = ScheduleViewState(selected: selected, loading: false);
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        state = ScheduleViewState(
          selected: state.selected,
          loading: false,
          error: '视图偏好读取失败，可以重试',
        );
      }
    }
  }

  Future<void> select(ScheduleView view) {
    if (!mounted) return Future.value();
    final generation = ++_generation;
    state = ScheduleViewState(selected: view, loading: false);
    final save = _writes.then(
      (_) => repository.saveScheduleView(ownerId, view),
    );
    _writes = save.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    PendingPersonalWrites.track(ownerId, BackupCategory.browsing, _writes);
    return save.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {
        if (mounted && generation == _generation) {
          state = ScheduleViewState(
            selected: view,
            loading: false,
            error: '视图已切换，但偏好未能保存，请重试',
          );
        }
      },
    );
  }

  Future<void> retry() =>
      state.selected == null ? load() : select(state.selected!);
}

final scheduleNowProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);
final scheduleDayProvider =
    StateNotifierProvider.autoDispose<ScheduleDayController, DateTime>(
      (ref) => ScheduleDayController(ref.watch(scheduleNowProvider)),
    );

/// Uses local calendar dates rather than adding 24 hours, and rechecks the
/// wall clock while visible so system clock/time-zone changes are picked up.
class ScheduleDayController extends StateNotifier<DateTime> {
  ScheduleDayController(this.now) : super(now()) {
    _lifecycle = AppLifecycleListener(
      onStateChange: (value) {
        _active =
            value == AppLifecycleState.resumed ||
            value == AppLifecycleState.inactive;
        if (_active) {
          refresh();
        } else {
          _timer?.cancel();
        }
      },
    );
    _arm();
  }
  final DateTime Function() now;
  late final AppLifecycleListener _lifecycle;
  Timer? _timer;
  bool _active = true;

  void refresh() {
    if (!mounted) return;
    final next = now();
    if (next.year != state.year ||
        next.month != state.month ||
        next.day != state.day ||
        next.timeZoneOffset != state.timeZoneOffset) {
      state = next;
    }
    _arm();
  }

  void _arm() {
    _timer?.cancel();
    if (!_active || !mounted) return;
    final current = now();
    final midnight = DateTime(current.year, current.month, current.day + 1);
    final delay = midnight.difference(current).inMilliseconds.clamp(1, 60000);
    _timer = Timer(Duration(milliseconds: delay), refresh);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }
}
