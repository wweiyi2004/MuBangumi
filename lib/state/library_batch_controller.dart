import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/library_batch.dart';
import 'schedule_controller.dart';
import 'session_controller.dart';

abstract class LibraryBatchBackend {
  void finish(LibraryBatchPlan plan);
  bool isCurrent(LibraryBatchAccount account);
  Future<LibraryBatchOutcome> changeCollection(
    LibraryBatchPlan plan,
    LibraryBatchItem item,
  );
  Future<LibraryBatchGroupResult> addToSchedule(
    LibraryBatchPlan plan,
    List<LibraryBatchItem> items,
    bool Function() allowed,
  );
}

class AppLibraryBatchBackend implements LibraryBatchBackend {
  AppLibraryBatchBackend(this.session, [this.schedule]);
  final SessionController session;
  final ScheduleController? schedule;
  @override
  void finish(LibraryBatchPlan plan) {
    if (plan.kind == LibraryBatchKind.collection && isCurrent(plan.account)) {
      unawaited(session.syncPendingChanges());
    }
  }

  @override
  bool isCurrent(LibraryBatchAccount account) =>
      session.isCurrentBatchAccount(account);
  @override
  Future<LibraryBatchOutcome> changeCollection(
    LibraryBatchPlan plan,
    LibraryBatchItem item,
  ) async {
    if (!isCurrent(plan.account)) {
      return const LibraryBatchOutcome(
        LibraryBatchStatus.notStarted,
        message: '账号已变化',
      );
    }
    final current = session.batchCollection(item.id);
    if (current == null) {
      return const LibraryBatchOutcome(
        LibraryBatchStatus.skipped,
        message: '已不在收藏中',
      );
    }
    if (session.collectionMutationRevision(item.id) != item.revision) {
      return const LibraryBatchOutcome(
        LibraryBatchStatus.skipped,
        message: '期间已有新修改，未覆盖',
      );
    }
    if (current.type == plan.collectionType &&
        !(plan.completeEpisodes && current.subject.type.hasEpisodes)) {
      return const LibraryBatchOutcome(
        LibraryBatchStatus.skipped,
        message: '已是目标状态',
      );
    }
    var queued = false;
    final error = await session.changeCollection(
      current.subject,
      plan.collectionType,
      completeEpisodesWhenDone: plan.completeEpisodes,
      expectedAccount: plan.account,
      expectedRevision: item.revision,
      requireExisting: true,
      statusOnly: true,
      deferSync: true,
      queueKey: 'collection-batch:${plan.operationId}:${item.id}',
      onQueued: () => queued = true,
    );
    if (queued) return const LibraryBatchOutcome(LibraryBatchStatus.saved);
    if (!isCurrent(plan.account)) {
      return const LibraryBatchOutcome(
        LibraryBatchStatus.notStarted,
        message: '账号已变化，未保存',
      );
    }
    if (session.collectionMutationRevision(item.id) != item.revision ||
        session.batchCollection(item.id) == null) {
      return const LibraryBatchOutcome(
        LibraryBatchStatus.skipped,
        message: '作品已变化，未覆盖新改动',
      );
    }
    return LibraryBatchOutcome(
      LibraryBatchStatus.failed,
      message: error ?? '未能保存，请重试',
    );
  }

  @override
  Future<LibraryBatchGroupResult> addToSchedule(
    LibraryBatchPlan plan,
    List<LibraryBatchItem> items,
    bool Function() allowed,
  ) async {
    if (!allowed() || !isCurrent(plan.account)) {
      return LibraryBatchGroupResult({
        for (final item in items)
          item.id: const LibraryBatchOutcome(
            LibraryBatchStatus.notStarted,
            message: '操作已停止',
          ),
      });
    }
    final outcomes = <int, LibraryBatchOutcome>{};
    final valid = <LibraryBatchItem>[];
    for (final item in items) {
      if (session.batchCollection(item.id) == null) {
        outcomes[item.id] = const LibraryBatchOutcome(
          LibraryBatchStatus.skipped,
          message: '已不在收藏中',
        );
      } else {
        valid.add(item);
      }
    }
    if (valid.isEmpty) return LibraryBatchGroupResult(outcomes);
    final season = plan.season;
    if (season == null) throw StateError('未选择季度');
    final result = await schedule!.addBatchToSeason(
      [for (final item in valid) session.batchCollection(item.id)!.subject],
      season,
      weekday: plan.weekday,
      allowed: () => allowed() && isCurrent(plan.account),
    );
    for (final item in valid) {
      outcomes[item.id] = result.added.contains(item.id)
          ? const LibraryBatchOutcome(LibraryBatchStatus.saved)
          : result.existing.contains(item.id)
          ? const LibraryBatchOutcome(
              LibraryBatchStatus.skipped,
              message: '本季度已有，保留原安排',
            )
          : result.stopped
          ? const LibraryBatchOutcome(
              LibraryBatchStatus.notStarted,
              message: '操作已停止',
            )
          : LibraryBatchOutcome(
              LibraryBatchStatus.failed,
              message: result.error ?? '未能加入新番表',
            );
    }
    return LibraryBatchGroupResult(outcomes, warning: result.warning);
  }
}

class LibraryBatchController extends ChangeNotifier {
  LibraryBatchController(this.plan, this.backend)
    : _outcomes = {
        for (final item in plan.items)
          item.id: const LibraryBatchOutcome(LibraryBatchStatus.notStarted),
      };
  final LibraryBatchPlan plan;
  final LibraryBatchBackend backend;
  final Map<int, LibraryBatchOutcome> _outcomes;
  Map<int, LibraryBatchOutcome> get outcomes => Map.unmodifiable(_outcomes);
  bool running = false, stopRequested = false, _disposed = false;
  String? notice;
  Future<void>? _active;
  int? currentId;
  bool get sameAccount => backend.isCurrent(plan.account);
  int count(LibraryBatchStatus status) =>
      _outcomes.values.where((item) => item.status == status).length;
  Set<int> get completedIds => {
    for (final entry in _outcomes.entries)
      if (entry.value.status == LibraryBatchStatus.saved ||
          entry.value.status == LibraryBatchStatus.skipped)
        entry.key,
  };
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void stop() {
    stopRequested = true;
    _notify();
  }

  Future<void> run({bool retryFailed = false}) {
    if (_disposed || !sameAccount) return Future.value();
    if (running) return _active ?? Future.value();
    final items = plan.items
        .where(
          (item) =>
              _outcomes[item.id]!.status ==
              (retryFailed
                  ? LibraryBatchStatus.failed
                  : LibraryBatchStatus.notStarted),
        )
        .toList();
    if (items.isEmpty) return Future.value();
    running = true;
    stopRequested = false;
    notice = null;
    _notify();
    return _active = _run(items);
  }

  Future<void> _run(List<LibraryBatchItem> items) async {
    bool allowed() => !_disposed && !stopRequested && sameAccount;
    try {
      if (plan.kind == LibraryBatchKind.schedule) {
        if (!allowed()) return;
        for (final item in items) {
          _outcomes[item.id] = const LibraryBatchOutcome(
            LibraryBatchStatus.processing,
          );
        }
        _notify();
        final report = await backend.addToSchedule(plan, items, allowed);
        _outcomes.addAll(report.outcomes);
        notice = report.warning;
      } else {
        for (final item in items) {
          if (!allowed()) break;
          currentId = item.id;
          _outcomes[item.id] = const LibraryBatchOutcome(
            LibraryBatchStatus.processing,
          );
          _notify();
          try {
            _outcomes[item.id] = await backend.changeCollection(plan, item);
          } catch (error) {
            _outcomes[item.id] = LibraryBatchOutcome(
              LibraryBatchStatus.failed,
              message: error.toString(),
            );
          }
          _notify();
        }
      }
    } catch (error) {
      for (final item in items) {
        _outcomes[item.id] = LibraryBatchOutcome(
          LibraryBatchStatus.failed,
          message: error.toString(),
        );
      }
    } finally {
      backend.finish(plan);
      running = false;
      currentId = null;
      _active = null;
      if (!sameAccount) {
        notice = '账号已变化，未开始的项目已停止';
      } else if (stopRequested && count(LibraryBatchStatus.notStarted) > 0) {
        notice = '已停止后续项目，返回后会保留未完成的选择';
      }
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    stopRequested = true;
    super.dispose();
  }
}
