import 'dart:async';

import '../../../core/auth/bangumi_oauth.dart';
import '../../../core/network/bangumi_api.dart';
import '../../../core/network/bangumi_support.dart';
import '../../../core/storage/bangumi_sync_store.dart';
import '../../../models/bangumi_models.dart';

/// Identity of one login, including re-logins of the same username.
typedef SyncAccount = ({int generation, String username});

class SyncProgress {
  const SyncProgress({this.pendingCount, this.blockedCount, this.isSyncing});

  final int? pendingCount;
  final int? blockedCount;
  final bool? isSyncing;
}

/// Owns queue draining, request guards and retry timing. It reports progress
/// for a specific login instead of reading or mutating global session state.
class PendingSyncController {
  PendingSyncController({
    required this._api,
    required this._store,
    required this.readAccount,
    required this.onProgress,
    required this.messageFor,
  });

  final BangumiApi _api;
  final BangumiSyncStore _store;
  final SyncAccount? Function() readAccount;
  final void Function(SyncAccount account, SyncProgress progress) onProgress;
  final String Function(Object error) messageFor;
  Future<void>? _inFlight;
  Timer? _retryTimer;
  var _retryStep = 0;
  bool _disposed = false;

  bool _isCurrent(SyncAccount account) =>
      !_disposed && readAccount() == account;

  void _requireAccount(SyncAccount account) {
    if (!_isCurrent(account)) {
      throw const BangumiApiException('登录状态已变化，请重新打开作品后操作');
    }
  }

  Future<void> sync({bool retryBlocked = false}) {
    if (_disposed) return Future.value();
    final active = _inFlight;
    if (active == null) return _startDrain(retryBlocked: retryBlocked);
    if (!retryBlocked) return active;
    // Manual retry joins the current upload, then performs another pass.
    // Keep the whole chain registered so callers cannot start a parallel drain.
    final future = () async {
      try {
        await active;
      } catch (_) {}
      await _startDrain(retryBlocked: true);
    }();
    _inFlight = future;
    return future;
  }

  Future<void> _startDrain({required bool retryBlocked}) {
    final future = _drain(retryBlocked: retryBlocked);
    _inFlight = future;
    return future.whenComplete(() {
      if (identical(_inFlight, future)) _inFlight = null;
    });
  }

  Future<void> _drain({required bool retryBlocked}) async {
    if (_disposed) return;
    final account = readAccount();
    if (account == null) return;
    cancelRetry();
    if (retryBlocked) {
      try {
        await _store.retryBlocked(account.username);
      } catch (_) {
        return;
      }
    }
    if (!_isCurrent(account)) return;
    onProgress(account, const SyncProgress(isSyncing: true));
    var retryLater = false;
    var changedWhileSyncing = false;
    try {
      final pending = await _store.pendingFor(account.username);
      for (final mutation in pending) {
        if (!_isCurrent(account)) return;
        try {
          await _replay(account, mutation);
          final removed = await _store.removeIfUnchanged(mutation);
          if (!removed) {
            changedWhileSyncing = true;
            break;
          }
          _retryStep = 0;
        } catch (error) {
          retryLater = _isRetryable(error);
          final marked = await _store.markFailure(
            mutation,
            messageFor(error),
            blocked: !retryLater,
          );
          if (!marked) changedWhileSyncing = true;
          break;
        }
      }
    } catch (_) {
      retryLater = true;
    } finally {
      final remaining = await refreshCount(account: account);
      if (_isCurrent(account)) {
        onProgress(account, const SyncProgress(isSyncing: false));
      }
      if (!retryLater && remaining > 0) changedWhileSyncing = true;
      if (_isCurrent(account)) {
        if (changedWhileSyncing) {
          _scheduleRetry(immediate: true);
        } else if (retryLater) {
          _scheduleRetry();
        }
      } else if (!_disposed) {
        // New-account edits may have joined the old drain. Count the current
        // account explicitly; old completion must never update its UI state.
        final nextAccount = readAccount();
        if (nextAccount != null &&
            await refreshCount(account: nextAccount) > 0 &&
            _isCurrent(nextAccount)) {
          _scheduleRetry(immediate: true);
        }
      }
    }
  }

  Future<void> _replay(SyncAccount account, PendingBangumiMutation mutation) =>
      _api.withRequestGuard(
        () => _isCurrent(account) && account.username == mutation.username,
        () async {
          _requireAccount(account);
          await _api.replayPendingMutation(mutation.kind, mutation.payload);
          if (mutation.kind != BangumiMutationKind.collection ||
              mutation.payload['complete_episodes'] != true ||
              mutation.payload['collection_type'] !=
                  CollectionType.done.value) {
            return;
          }
          final subjectId = (mutation.payload['subject_id'] as num).toInt();
          _requireAccount(account);
          final episodes = await _api.getEpisodeCollections(subjectId);
          _requireAccount(account);
          final unfinished = BangumiSupport.unfinishedMainEpisodeIds(episodes);
          if (unfinished.isNotEmpty) {
            await _api.updateEpisodesBatch(
              subjectId,
              episodeIds: unfinished,
              type: 2,
            );
          }
        },
      );

  /// Returns unblocked work; stale completions never publish progress.
  Future<int> refreshCount({SyncAccount? account}) async {
    if (_disposed) return 0;
    account ??= readAccount();
    if (account == null) return 0;
    try {
      final counts = await Future.wait([
        _store.countFor(account.username),
        _store.blockedCountFor(account.username),
      ]);
      if (_isCurrent(account)) {
        onProgress(
          account,
          SyncProgress(pendingCount: counts[0], blockedCount: counts[1]),
        );
      }
      return counts[0] - counts[1];
    } catch (_) {
      return 0;
    }
  }

  bool _isRetryable(Object error) =>
      (error is BangumiApiException && error.retryable) ||
      (error is BangumiOAuthException && !error.invalidatesSession);

  void _scheduleRetry({bool immediate = false}) {
    if (_disposed || _retryTimer != null || readAccount() == null) return;
    const delays = [
      Duration(seconds: 20),
      Duration(minutes: 1),
      Duration(minutes: 2),
      Duration(minutes: 5),
    ];
    final index = _retryStep.clamp(0, delays.length - 1);
    if (!immediate) _retryStep++;
    _retryTimer = Timer(immediate ? Duration.zero : delays[index], () {
      _retryTimer = null;
      unawaited(sync());
    });
  }

  /// Logout cancels timers but keeps uploads serialized across logins.
  void cancelRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  void dispose() {
    _disposed = true;
    cancelRetry();
  }
}
