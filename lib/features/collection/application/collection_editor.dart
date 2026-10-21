import 'dart:async';

import '../../../core/network/bangumi_api.dart';
import '../../../core/network/bangumi_support.dart';
import '../../../core/storage/bangumi_sync_store.dart';
import '../../../core/storage/snapshot_cache.dart';
import '../../../models/bangumi_models.dart';
import '../../../models/episode_edit.dart';
import '../../../models/library_batch.dart';
import '../domain/collection_reconciler.dart';
import 'collection_edit_view.dart';
import 'episode_collection_reader.dart';

/// Owns durable edits, per-subject ordering, revision tracking and undo.
/// A narrow view port keeps it independent of login state and Riverpod.
class CollectionEditor implements EpisodeCollectionReader {
  CollectionEditor({
    required this._api,
    required this._snapshotCache,
    required this._syncStore,
    required this.readAccount,
    required this.readView,
    required this.writeView,
    required this.isAlive,
    required this.syncPendingChanges,
    required this._refreshPendingCount,
    required this._messageFor,
    this.preferCachedReads,
  });

  final BangumiApi _api;
  final SnapshotCache _snapshotCache;
  final BangumiSyncStore _syncStore;
  final LibraryBatchAccount? Function() readAccount;
  final CollectionEditView Function() readView;
  final void Function(CollectionEditView view) writeView;
  final bool Function() isAlive;
  final Future<void> Function() syncPendingChanges;
  final Future<int> Function(String? username) _refreshPendingCount;
  final String Function(Object error) _messageFor;
  final bool Function()? preferCachedReads;
  bool _disposed = false;
  bool get mounted => !_disposed && isAlive();
  LibraryBatchAccount? get _account => mounted ? readAccount() : null;
  int get _authGeneration => _account?.generation ?? -1;
  bool _isCurrentAuth(int generation) =>
      mounted && _account?.generation == generation;
  CollectionEditView get _view => readView();
  set _view(CollectionEditView value) => writeView(value);

  final _subjectOperations = <String, Future<void>>{};
  final _episodeChanges = <int, EpisodeEdit>{};
  final _confirmedEpisodeRevisions = <int, int>{};
  int _localMutationRevision = 0;
  final _optimisticSubjects = <int>{};
  final _episodeSnapshots = <int, List<UserEpisodeCollection>>{};
  final _episodeSnapshotTimes = <int, DateTime>{};
  final _snapshotWrites = <String, Future<void>>{};
  Future<void> _cacheSnapshot(
    int subjectId,
    int generation,
    String username,
    Future<void> Function() work,
  ) async {
    final key = '$generation:$subjectId';
    final future = (_snapshotWrites[key] ?? Future<void>.value()).then((
      _,
    ) async {
      if (!_isCurrentAuth(generation) || _account?.username != username) return;
      try {
        await work();
      } catch (_) {
        /* The durable queue is authoritative. */
      }
    });
    _snapshotWrites[key] = future;
    unawaited(
      future.then((_) {
        if (identical(_snapshotWrites[key], future)) {
          _snapshotWrites.remove(key);
        }
      }),
    );
    // Fast cache writes normally finish in this turn; slow disks must not keep
    // the edit controls busy. Remaining writes retain their per-subject order.
    await future.timeout(const Duration(milliseconds: 50), onTimeout: () {});
  }

  int _beginMutation(int subjectId) {
    final revision = ++_localMutationRevision;
    _subjectMutationRevisions[subjectId] = revision;
    _optimisticSubjects.add(subjectId);
    return revision;
  }

  void _rememberEpisodes(
    int subjectId,
    List<UserEpisodeCollection> episodes,
    DateTime savedAt, {
    bool replace = false,
  }) {
    final byId = {
      if (!replace)
        for (final item
            in _episodeSnapshots[subjectId] ?? <UserEpisodeCollection>[])
          item.episode.id: item,
      for (final item in episodes) item.episode.id: item,
    };
    _episodeSnapshots.remove(subjectId);
    _episodeSnapshots[subjectId] = byId.values.toList();
    _episodeSnapshotTimes[subjectId] = savedAt;
    while (_episodeSnapshots.length > 24) {
      final oldest = _episodeSnapshots.keys.first;
      _episodeSnapshots.remove(oldest);
      _episodeSnapshotTimes.remove(oldest);
    }
  }

  final Map<int, int> _subjectMutationRevisions = {};

  List<UserCollection> get collections => _view.collections;
  EpisodeUndo? get pendingEpisodeUndo => mounted ? _view.episodeUndo : null;
  @override
  int get episodeRevision => _localMutationRevision;
  @override
  LibraryBatchAccount? get batchAccount => _account;
  bool isCurrentBatchAccount(LibraryBatchAccount account) {
    final current = _account;
    return current != null &&
        current.generation == account.generation &&
        current.userId == account.userId &&
        current.username == account.username;
  }

  int collectionMutationRevision(int subjectId) =>
      _subjectMutationRevisions[subjectId] ?? 0;
  @override
  UserCollection? batchCollection(int subjectId) =>
      mounted ? _view.collectionFor(subjectId) : null;

  /// Reset account-local revisions, but keep old operation futures keyed by
  /// generation until they settle. They must still hit their account guards.
  void reset() {
    _optimisticSubjects.clear();
    _episodeSnapshots.clear();
    _episodeSnapshotTimes.clear();
    _subjectMutationRevisions.clear();
    _episodeChanges.clear();
    _confirmedEpisodeRevisions.clear();
    _localMutationRevision = 0;
  }

  void dispose() {
    _disposed = true;
    reset();
  }

  void _requireEditAccount(int generation, String username) {
    if (!_isCurrentAuth(generation) || _account?.username != username) {
      throw const BangumiApiException('登录状态已变化，请重新打开作品后操作');
    }
  }

  Future<T> _serializeSubject<T>(
    int subjectId,
    int generation,
    Future<T> Function() work,
  ) {
    final key = '$generation:$subjectId';
    final previous = _subjectOperations[key] ?? Future<void>.value();
    final next = previous.then((_) => work());
    final done = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    _subjectOperations[key] = done;
    unawaited(
      done.then((_) {
        if (identical(_subjectOperations[key], done)) {
          _subjectOperations.remove(key);
        }
      }),
    );
    return next;
  }

  Future<String?> _editSubject(
    int subjectId,
    Future<String?> Function(int generation, String username) work, {
    bool trackGlobalBusy = true,
  }) {
    if (!mounted) return Future.value('页面已关闭');
    final generation = _authGeneration;
    final username = _account?.username;
    if (username == null || username.isEmpty) return Future.value('请先登录后再修改');
    return _serializeSubject(subjectId, generation, () async {
      try {
        _requireEditAccount(generation, username);
        if (trackGlobalBusy) _setUpdating(subjectId, true);
        return await work(generation, username);
      } catch (error) {
        return _messageFor(error);
      } finally {
        if (_isCurrentAuth(generation) && trackGlobalBusy) {
          _setUpdating(subjectId, false);
        }
      }
    });
  }

  @override
  Future<List<UserEpisodeCollection>?> readEpisodeSnapshot(
    int subjectId,
  ) async {
    final generation = _authGeneration;
    final username = _account?.username;
    if (username == null) return null;
    final cached = await _snapshotCache.readEpisodeCollections(
      subjectId,
      username: username,
    );
    _requireEditAccount(generation, username);
    if (cached == null) return null;
    final merged = await applyPendingEpisodeChanges(
      subjectId,
      cached,
      afterRevision: _localMutationRevision,
    );
    final savedAt = cached is SnapshotItems<UserEpisodeCollection>
        ? cached.savedAt
        : DateTime(1970);
    final rememberedAt = _episodeSnapshotTimes[subjectId];
    if (rememberedAt == null || !savedAt.isBefore(rememberedAt)) {
      _rememberEpisodes(subjectId, merged, savedAt);
    }
    return cached is SnapshotItems<UserEpisodeCollection>
        ? SnapshotItems(merged, savedAt: cached.savedAt)
        : merged;
  }

  @override
  Future<List<UserEpisodeCollection>> loadEpisodeCollections(
    int subjectId, {
    int? episodeType,
  }) async {
    final generation = _authGeneration;
    final username = _account?.username;
    if (username == null) throw const BangumiApiException('请先登录');
    final revision = _localMutationRevision;
    final remote = await _api.getEpisodeCollections(
      subjectId,
      episodeType: episodeType,
    );
    _requireEditAccount(generation, username);
    return _serializeSubject(subjectId, generation, () async {
      _requireEditAccount(generation, username);
      for (final item in remote) {
        final local = _episodeChanges[item.episode.id];
        if (local != null &&
            local.revision <= revision &&
            local.type == item.type) {
          _confirmedEpisodeRevisions[item.episode.id] = local.revision;
        }
      }
      final merged = await applyPendingEpisodeChanges(
        subjectId,
        remote,
        afterRevision: revision,
      );
      _requireEditAccount(generation, username);
      if (episodeType != null) {
        if (episodeType == 0) {
          _rememberEpisodes(
            subjectId,
            [
              for (final item
                  in _episodeSnapshots[subjectId] ?? <UserEpisodeCollection>[])
                if (item.episode.type != 0) item,
              ...merged,
            ],
            DateTime.now(),
            replace: true,
          );
        }
        // A filtered response must not replace the complete offline snapshot
        // or mark unrelated main chapters as recently validated.
        return merged;
      }
      _rememberEpisodes(subjectId, merged, DateTime.now(), replace: true);
      try {
        await _snapshotCache.writeEpisodeCollections(
          subjectId,
          merged,
          username: username,
        );
      } catch (_) {}
      _requireEditAccount(generation, username);
      return merged;
    });
  }

  List<UserCollection> preserveCollectionsChangedAfter(
    List<UserCollection> source,
    int requestMutationRevision,
  ) {
    final preserved = CollectionReconciler.preserveChangedAfter(
      source,
      requestMutationRevision,
      current: _view.collections,
      subjectRevisions: _subjectMutationRevisions,
    );
    final byId = {for (final item in preserved) item.subjectId: item};
    for (final item in _view.collections) {
      if (_optimisticSubjects.contains(item.subjectId)) {
        byId[item.subjectId] = item;
      }
    }
    return byId.values.toList();
  }

  Future<List<UserCollection>> overlayPendingCollections(
    String username,
    List<UserCollection> source, {
    bool sort = true,
  }) async {
    final snapshot = List<UserCollection>.from(source);
    List<PendingBangumiMutation> pending = const [];
    try {
      pending = await _syncStore.pendingFor(username, includeBlocked: true);
    } catch (_) {}
    return CollectionReconciler.overlayCollections(
      snapshot,
      pending,
      sort: sort,
    );
  }

  @override
  Future<List<UserEpisodeCollection>> applyPendingEpisodeChanges(
    int subjectId,
    List<UserEpisodeCollection> source, {
    int? afterRevision,
  }) async {
    final generation = _authGeneration;
    final username = _account?.username;
    if (username == null || username.isEmpty) return source;
    final snapshot = List<UserEpisodeCollection>.from(source);
    List<PendingBangumiMutation> pending = const [];
    try {
      pending = await _syncStore.pendingFor(username, includeBlocked: true);
    } catch (_) {}
    final merged = CollectionReconciler.overlayEpisodes(
      subjectId,
      snapshot,
      pending,
    );
    _requireEditAccount(generation, username);
    if (afterRevision != null) {
      for (var index = 0; index < merged.length; index++) {
        final change = _episodeChanges[merged[index].episode.id];
        if (change != null &&
            change.subjectId == subjectId &&
            (change.revision > afterRevision ||
                _confirmedEpisodeRevisions[change.episodeId] !=
                    change.revision)) {
          merged[index] = merged[index].copyWith(type: change.type);
        }
      }
    }
    return merged;
  }

  /// Keeps the episode snapshot in step with a just-enqueued edit, so a
  /// later offline read still shows it after the queue entry that carried
  /// it has been uploaded and removed. The direct edit covers the entry
  /// that may already be gone; the queue fold overlays any newer local
  /// _view for the same subject.
  Future<void> _persistEpisodeSnapshot(
    int subjectId, {
    required String username,
    required int generation,
    int? episodeId,
    int? type,
  }) async {
    try {
      final cached = await _snapshotCache.readEpisodeCollections(
        subjectId,
        username: username,
      );
      _requireEditAccount(generation, username);
      if (cached == null || cached.isEmpty) return;
      final edited = [
        for (final item in cached)
          if (episodeId != null && item.episode.id == episodeId)
            item.copyWith(type: type ?? item.type)
          else
            item,
      ];
      final merged = await applyPendingEpisodeChanges(
        subjectId,
        edited,
        afterRevision: _localMutationRevision,
      );
      _requireEditAccount(generation, username);
      final latest = {
        for (final item in merged) item.episode.id: item,
        for (final item
            in _episodeSnapshots[subjectId] ?? <UserEpisodeCollection>[])
          item.episode.id: item,
      };
      await _snapshotCache.writeEpisodeCollections(
        subjectId,
        latest.values.toList(),
        username: username,
      );
    } catch (_) {
      // The queue entry is durable on its own; a snapshot hiccup must not
      // surface as a failed edit.
    }
  }

  Future<List<PendingBangumiMutation>> blockedSyncMutations() async {
    final generation = _authGeneration;
    final username = _account?.username;
    if (username == null || username.isEmpty) return const [];
    final mutations = await _syncStore.blockedFor(username);
    if (!_isCurrentAuth(generation) || _account?.username != username) {
      return const [];
    }
    return mutations;
  }

  Future<String?> retryBlockedMutation(PendingBangumiMutation mutation) async {
    final generation = _authGeneration;
    final username = _account?.username;
    if (username == null || username.isEmpty) return '请先登录后再重试';
    if (mutation.username != username) return '该同步记录不属于当前账号';
    if (mutation.superseded) return '已有后续修改，旧操作不能再重试；请重新编辑需要同步的内容';
    try {
      final retried = await _syncStore.retryIfUnchanged(mutation);
      await _refreshPendingCount(username);
      if (!retried) {
        final latest = (await _syncStore.blockedFor(
          username,
        )).where((item) => item.id == mutation.id).firstOrNull;
        if (latest?.superseded == true) return '已有后续修改，旧操作不能再重试；请重新编辑需要同步的内容';
        return '同步记录已变化，请刷新列表后重试';
      }
      if (!_isCurrentAuth(generation) || _account?.username != username) {
        return '登录状态已变化';
      }
      await syncPendingChanges();
      return null;
    } catch (error) {
      return _messageFor(error);
    }
  }

  Future<String?> discardBlockedMutation(PendingBangumiMutation mutation) {
    final subjectId = (mutation.payload['subject_id'] as num?)?.toInt();
    if (subjectId == null || subjectId <= 0) return Future.value('同步记录缺少作品信息');
    return _editSubject(subjectId, (generation, username) async {
      if (mutation.username != username) return '该同步记录不属于当前账号';
      final discarded = await _syncStore.discardIfUnchanged(mutation);
      await _refreshPendingCount(username);
      _requireEditAccount(generation, username);
      if (!discarded) return '同步记录已变化，请刷新列表后重试';
      if (mutation.superseded) return null;
      _subjectMutationRevisions[subjectId] = ++_localMutationRevision;
      for (final change
          in _episodeChanges.values
              .where((change) => change.subjectId == subjectId)
              .toList()) {
        _episodeChanges.remove(change.episodeId);
        _confirmedEpisodeRevisions.remove(change.episodeId);
      }
      if (_view.episodeUndo?.change.subjectId == subjectId) {
        _view = _view.copyWith(clearEpisodeUndo: true);
      }
      try {
        await _snapshotCache.invalidateCollection(username, subjectId);
        if (mutation.kind != BangumiMutationKind.collection ||
            mutation.payload['complete_episodes'] == true ||
            ((mutation.payload['watched_through'] as num?)?.toInt() ?? 0) > 0) {
          await _snapshotCache.clearEpisodeCollections(
            subjectId,
            username: username,
          );
        }
      } catch (_) {}
      return null;
    });
  }

  Future<String> _enqueueMutation({
    required BangumiMutationKind kind,
    required String mutationKey,
    required Map<String, dynamic> payload,
    void Function()? onSaved,
    bool deferSync = false,
    int? reservedRevision,
  }) async {
    final generation = _authGeneration;
    final username = _account?.username;
    if (username == null || username.isEmpty) {
      throw const BangumiApiException('请先登录后再修改');
    }
    await _syncStore.enqueue(
      username: username,
      kind: kind,
      mutationKey: mutationKey,
      payload: payload,
    );
    onSaved?.call();
    if (!_isCurrentAuth(generation) || _account?.username != username) {
      throw const BangumiApiException('登录状态已变化，修改已保存在原账号的本地队列中');
    }
    final subjectId = (payload['subject_id'] as num?)?.toInt();
    if (subjectId != null && subjectId > 0) {
      if (_view.episodeUndo?.change.subjectId == subjectId) {
        _view = _view.copyWith(clearEpisodeUndo: true);
      }
      if (reservedRevision == null) {
        _localMutationRevision++;
        _subjectMutationRevisions[subjectId] = _localMutationRevision;
      }
    }
    unawaited(
      _refreshPendingCount(
        username,
      ).then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
    if (!deferSync) unawaited(syncPendingChanges());
    return username;
  }

  Future<String?> markNextEpisode(
    UserCollection collection, {
    void Function(EpisodeUndo)? onUndoReady,
  }) {
    final subjectId = collection.subjectId;
    if (_subjectOperations.containsKey('$_authGeneration:$subjectId')) {
      return Future.value('章节修改正在保存');
    }
    return _editSubject(subjectId, (generation, username) async {
      final revision = _localMutationRevision;
      List<UserEpisodeCollection> episodes;
      final memory = _episodeSnapshots[subjectId];
      final savedAt = _episodeSnapshotTimes[subjectId];
      final fresh =
          savedAt != null &&
          DateTime.now().difference(savedAt) < const Duration(minutes: 2);
      if (memory != null &&
          memory.any((item) => item.episode.type == 0) &&
          (fresh || preferCachedReads?.call() == true)) {
        episodes = List.of(memory);
      } else if (preferCachedReads?.call() == true) {
        episodes = await readEpisodeSnapshot(subjectId) ?? const [];
        if (!episodes.any((item) => item.episode.type == 0)) {
          return '该作品尚未缓存章节，请联网打开详情后再更新进度';
        }
      } else {
        final cached = await readEpisodeSnapshot(subjectId);
        final cachedAt = _episodeSnapshotTimes[subjectId];
        if (!(memory != null && !fresh) &&
            cached != null &&
            cached.any((item) => item.episode.type == 0) &&
            cachedAt != null &&
            DateTime.now().difference(cachedAt) < const Duration(minutes: 2)) {
          episodes = cached;
        } else {
          try {
            episodes = await _api.getEpisodeCollections(
              subjectId,
              episodeType: null,
            );
            _requireEditAccount(generation, username);
            _episodeSnapshotTimes[subjectId] = DateTime.now();
            episodes = await applyPendingEpisodeChanges(
              subjectId,
              episodes,
              afterRevision: revision,
            );
          } catch (_) {
            _requireEditAccount(generation, username);
            episodes = cached ?? const [];
            if (episodes.isEmpty) rethrow;
          }
        }
      }
      _requireEditAccount(generation, username);
      episodes = [
        for (final item in episodes)
          _episodeChanges[item.episode.id] != null
              ? item.copyWith(type: _episodeChanges[item.episode.id]!.type)
              : item,
      ];
      _rememberEpisodes(
        subjectId,
        episodes,
        _episodeSnapshotTimes[subjectId] ?? DateTime(1970),
        replace: true,
      );
      final target = BangumiSupport.nextUnwatchedMain(episodes);
      if (target == null) return '已经没有下一集了';
      _requireEditAccount(generation, username);
      final watchedCount = BangumiSupport.watchedMainCountAfterMark(
        episodes,
        target.episode.id,
      );
      final result = await _saveEpisodeEdit(
        subjectId: subjectId,
        episodeId: target.episode.id,
        type: 2,
        previousType: target.type,
        nextCount: watchedCount,
        previousCount: watchedCount - 1,
        episode: target.episode,
        generation: generation,
        username: username,
        onUndoReady: onUndoReady,
      );
      _requireEditAccount(generation, username);
      if (result == null) {
        await _cacheSnapshot(subjectId, generation, username, () async {
          final latest = _episodeSnapshots[subjectId];
          if (latest != null) {
            final cached = await _snapshotCache.readEpisodeCollections(
              subjectId,
              username: username,
            );
            _requireEditAccount(generation, username);
            final combined = {
              for (final item in cached ?? <UserEpisodeCollection>[])
                if (item.episode.type != 0) item.episode.id: item,
              for (final item in _episodeSnapshots[subjectId] ?? latest)
                item.episode.id: item,
            };
            await _snapshotCache.writeEpisodeCollections(
              subjectId,
              combined.values.toList(),
              username: username,
            );
          }
        });
      }
      return result;
    });
  }

  Future<String?> setEpisode({
    required int subjectId,
    required int episodeId,
    required int type,
    int? previousType,
    Episode? episode,
    bool trackGlobalBusy = true,
    void Function(EpisodeUndo)? onUndoReady,
  }) {
    final requestRevision = _localMutationRevision;
    return _editSubject(subjectId, (generation, username) async {
      final collection = _view.collectionFor(subjectId);
      final newer = _episodeChanges[episodeId];
      final before = newer != null && newer.revision > requestRevision
          ? newer.type
          : previousType;
      if (before == type) return null;
      final countsMain = episode == null || episode.type == 0;
      final previousCount = countsMain ? collection?.episodeStatus : null;
      final delta = before == null
          ? 0
          : (type == 2 ? 1 : 0) - (before == 2 ? 1 : 0);
      final nextCount = previousCount == null || before == null
          ? null
          : (previousCount + delta).clamp(0, 1 << 30);
      return _saveEpisodeEdit(
        subjectId: subjectId,
        episodeId: episodeId,
        type: type,
        previousType: before,
        nextCount: nextCount,
        previousCount: previousCount,
        episode: episode,
        generation: generation,
        username: username,
        onUndoReady: onUndoReady,
      );
    }, trackGlobalBusy: trackGlobalBusy);
  }

  Future<String?> _saveEpisodeEdit({
    required int subjectId,
    required int episodeId,
    required int type,
    required int? previousType,
    required int? nextCount,
    required int? previousCount,
    required int generation,
    required String username,
    Episode? episode,
    void Function(EpisodeUndo)? onUndoReady,
    bool createUndo = true,
  }) async {
    _requireEditAccount(generation, username);
    final beforeView = _view;
    final beforeCollection = _view.collectionFor(subjectId);
    final beforeChange = _episodeChanges[episodeId];
    final beforeRevision = collectionMutationRevision(subjectId);
    final beforeMemory = _episodeSnapshots[subjectId];
    final revision = _beginMutation(subjectId);
    var saved = false;
    final change = EpisodeEdit(
      subjectId: subjectId,
      episodeId: episodeId,
      type: type,
      revision: revision,
    );
    _episodeChanges[episodeId] = change;
    final current = _view.collectionFor(subjectId);
    final undo = createUndo && previousType != null
        ? EpisodeUndo(
            userId: _account!.userId,
            username: username,
            authGeneration: generation,
            change: change,
            previousType: previousType,
            previousCount: previousCount,
            subjectTitle: current?.subject.displayName ?? '作品 $subjectId',
            episodeLabel: episode == null
                ? '章节 $episodeId'
                : episode.type == 0
                ? '本篇 ${episode.label}'
                : episode.label,
          )
        : null;
    if (current != null && nextCount != null) {
      _replaceCollection(current.copyWith(episodeStatus: nextCount));
    }
    _view = _view.copyWith(
      lastEpisodeEdit: change,
      episodeUndo: undo,
      clearEpisodeUndo: undo == null,
    );
    final remembered = _episodeSnapshots[subjectId];
    if (remembered != null) {
      _episodeSnapshots[subjectId] = [
        for (final item in remembered)
          item.episode.id == episodeId ? item.copyWith(type: type) : item,
      ];
    }
    try {
      await _enqueueMutation(
        reservedRevision: revision,
        onSaved: () => saved = true,
        kind: BangumiMutationKind.episode,
        mutationKey: 'episode:$episodeId',
        payload: {
          'subject_id': subjectId,
          'episode_id': episodeId,
          'type': type,
          'activity_before': previousType,
          'activity_undo': !createUndo,
          'local_episode_status': ?nextCount,
        },
      );
      _requireEditAccount(generation, username);
      // Enqueue clears old undo; the new durable edit now owns the undo action.
      _view = _view.copyWith(episodeUndo: undo, clearEpisodeUndo: undo == null);
      if (undo != null) onUndoReady?.call(undo);
      await _cacheSnapshot(subjectId, generation, username, () async {
        await _persistEpisodeSnapshot(
          subjectId,
          username: username,
          generation: generation,
          episodeId: episodeId,
          type: type,
        );
        _requireEditAccount(generation, username);
        await _snapshotCache.writeCollections(username, _view.collections);
      });
      _requireEditAccount(generation, username);
      return null;
    } catch (_) {
      if (!saved &&
          _isCurrentAuth(generation) &&
          _account?.username == username) {
        _subjectMutationRevisions[subjectId] = beforeRevision;
        if (beforeChange == null) {
          _episodeChanges.remove(episodeId);
        } else {
          _episodeChanges[episodeId] = beforeChange;
        }
        if (beforeMemory != null) _episodeSnapshots[subjectId] = beforeMemory;
        if (beforeCollection != null) _replaceCollection(beforeCollection);
        final restoreUndo =
            identical(_view.episodeUndo, undo) &&
            identical(_view.lastEpisodeEdit, change);
        final retainedUndo = restoreUndo
            ? beforeView.episodeUndo
            : _view.episodeUndo;
        _view = _view.copyWith(
          lastEpisodeEdit: EpisodeEdit(
            subjectId: subjectId,
            episodeId: episodeId,
            type: previousType ?? 0,
            revision: ++_localMutationRevision,
          ),
          episodeUndo: retainedUndo,
          clearEpisodeUndo: retainedUndo == null,
        );
      }
      rethrow;
    } finally {
      if (_isCurrentAuth(generation)) _optimisticSubjects.remove(subjectId);
    }
  }

  Future<String?> undoEpisode(EpisodeUndo undo) =>
      _editSubject(undo.change.subjectId, (generation, username) async {
        if (!identical(_view.episodeUndo, undo) ||
            undo.authGeneration != generation ||
            undo.userId != _account?.userId ||
            undo.username != username ||
            _subjectMutationRevisions[undo.change.subjectId] !=
                undo.change.revision) {
          return '这次操作已失效，后续修改保持不变';
        }
        return _saveEpisodeEdit(
          subjectId: undo.change.subjectId,
          episodeId: undo.change.episodeId,
          type: undo.previousType,
          previousType: undo.change.type,
          nextCount: undo.previousCount,
          previousCount: null,
          generation: generation,
          username: username,
          createUndo: false,
        );
      });

  void dismissEpisodeUndo(EpisodeUndo undo) {
    if (mounted && identical(_view.episodeUndo, undo)) {
      _view = _view.copyWith(clearEpisodeUndo: true);
    }
  }

  Future<String?> changeCollection(
    Subject subject,
    CollectionType type, {
    bool completeEpisodesWhenDone = true,
    int? watchedThrough,
    int? rate,
    String? comment,
    List<String>? tags,
    bool? private,
    int? episodeStatus,
    int? volumeStatus,
    LibraryBatchAccount? expectedAccount,
    int? expectedRevision,
    bool requireExisting = false,
    void Function()? onQueued,
    bool statusOnly = false,
    String? queueKey,
    bool deferSync = false,
  }) => _editSubject(subject.id, (generation, username) async {
    UserCollection? beforeCollection;
    int? beforeRevision;
    var saved = false;
    var optimistic = false;
    try {
      if (expectedAccount != null && !isCurrentBatchAccount(expectedAccount)) {
        return '登录状态已变化，未保存';
      }
      if (expectedRevision != null &&
          collectionMutationRevision(subject.id) != expectedRevision) {
        return '作品已有新的修改，未覆盖新改动';
      }
      final old = _view.collectionFor(subject.id);
      if (requireExisting && old == null) return '作品已不在收藏中，未重新加入';
      final nextRate = rate ?? old?.rate ?? 0;
      final nextComment = comment ?? old?.comment ?? '';
      final nextTags = tags ?? old?.tags ?? const <String>[];
      final nextPrivate = private ?? old?.private ?? false;
      // Books only: OpenAPI documents ep_status/vol_status for book progress.
      final nextEpisodeStatus = subject.type.hasVolumes
          ? (episodeStatus ?? old?.episodeStatus ?? 0)
          : (old?.episodeStatus ?? 0);
      final nextVolumeStatus = subject.type.hasVolumes
          ? (volumeStatus ?? old?.volumeStatus ?? 0)
          : (old?.volumeStatus ?? 0);
      final shouldCompleteEpisodes =
          completeEpisodesWhenDone &&
          type == CollectionType.done &&
          subject.type.hasEpisodes;
      final targetThrough =
          !shouldCompleteEpisodes &&
              watchedThrough != null &&
              watchedThrough > 0 &&
              subject.type.hasEpisodes
          ? watchedThrough
          : null;
      var resolvedEpisodeStatus =
          shouldCompleteEpisodes && subject.episodeCount > 0
          ? subject.episodeCount
          : targetThrough != null
          ? (subject.episodeCount > 0
                ? targetThrough.clamp(0, subject.episodeCount)
                : targetThrough)
          : nextEpisodeStatus;
      beforeCollection = old;
      beforeRevision = collectionMutationRevision(subject.id);
      final revision = _beginMutation(subject.id);
      optimistic = true;
      final immediate = old != null
          ? old.copyWith(
              type: type,
              rate: nextRate,
              comment: nextComment,
              tags: nextTags,
              private: nextPrivate,
              episodeStatus: resolvedEpisodeStatus,
              volumeStatus: nextVolumeStatus,
            )
          : UserCollection(
              subjectId: subject.id,
              type: type,
              rate: nextRate,
              episodeStatus: resolvedEpisodeStatus,
              volumeStatus: nextVolumeStatus,
              updatedAt: DateTime.now(),
              subject: subject,
              comment: nextComment,
              tags: nextTags,
              private: nextPrivate,
            );
      if (old == null) {
        _view = _view.copyWith(collections: [immediate, ..._view.collections]);
      } else {
        _replaceCollection(immediate);
      }
      List<UserEpisodeCollection>? cachedEpisodes;
      if (shouldCompleteEpisodes || targetThrough != null) {
        try {
          cachedEpisodes =
              _episodeSnapshots[subject.id] ??
              await _snapshotCache.readEpisodeCollections(
                subject.id,
                username: username,
              );
        } catch (_) {}
        if (shouldCompleteEpisodes) {
          if (cachedEpisodes != null && cachedEpisodes.isNotEmpty) {
            resolvedEpisodeStatus = BangumiSupport.mainEpisodeCollections(
              cachedEpisodes,
            ).length;
          } else if (subject.episodeCount > 0) {
            resolvedEpisodeStatus = subject.episodeCount;
          }
        } else if (targetThrough != null) {
          if (cachedEpisodes != null && cachedEpisodes.isNotEmpty) {
            final mainTotal = BangumiSupport.mainEpisodeCollections(
              cachedEpisodes,
            ).length;
            resolvedEpisodeStatus = mainTotal > 0
                ? targetThrough.clamp(0, mainTotal)
                : targetThrough;
          } else if (subject.episodeCount > 0) {
            resolvedEpisodeStatus = targetThrough.clamp(
              0,
              subject.episodeCount,
            );
          } else {
            resolvedEpisodeStatus = targetThrough;
          }
        }
      }
      _requireEditAccount(generation, username);
      await _enqueueMutation(
        reservedRevision: revision,
        kind: BangumiMutationKind.collection,
        mutationKey: queueKey ?? 'collection:${subject.id}',
        onSaved: () {
          saved = true;
          onQueued?.call();
        },
        deferSync: deferSync,
        payload: {
          'subject_id': subject.id,
          'subject': subject.toJson(),
          'collection_type': type.value,
          if (statusOnly) 'status_only': true,
          'rate': nextRate,
          'comment': nextComment,
          'tags': nextTags,
          'private': nextPrivate,
          'episode_status': subject.type.hasVolumes ? nextEpisodeStatus : null,
          'local_episode_status': resolvedEpisodeStatus,
          'volume_status': subject.type.hasVolumes ? nextVolumeStatus : null,
          'complete_episodes': shouldCompleteEpisodes,
          'watched_through': ?targetThrough,
          'local_updated_at': DateTime.now().toIso8601String(),
        },
      );
      _requireEditAccount(generation, username);
      Future<void> Function()? saveEpisodes;
      if ((shouldCompleteEpisodes || targetThrough != null) &&
          cachedEpisodes != null) {
        final targetIds = shouldCompleteEpisodes
            ? {
                for (final item in cachedEpisodes)
                  if (item.episode.type == 0) item.episode.id,
              }
            : {
                for (final item in BangumiSupport.mainEpisodeCollections(
                  cachedEpisodes,
                ).take(targetThrough!))
                  item.episode.id,
              };
        for (final episodeId in targetIds) {
          _episodeChanges[episodeId] = EpisodeEdit(
            subjectId: subject.id,
            episodeId: episodeId,
            type: 2,
            revision: _subjectMutationRevisions[subject.id]!,
          );
        }
        final completed = [
          for (final item in cachedEpisodes)
            if (targetIds.contains(item.episode.id))
              item.copyWith(type: 2)
            else
              item,
        ];
        _rememberEpisodes(subject.id, completed, DateTime.now());
        saveEpisodes = () => _snapshotCache.writeEpisodeCollections(
          subject.id,
          completed,
          username: username,
        );
      }
      if (!_isCurrentAuth(generation) || _account?.username != username) {
        return '登录状态已变化，修改已保存在原账号的本地队列中';
      }
      if (old != null) {
        if (statusOnly) {
          final latest = _view.collectionFor(subject.id) ?? old;
          _replaceCollection(
            latest.copyWith(
              type: type,
              episodeStatus: shouldCompleteEpisodes || targetThrough != null
                  ? resolvedEpisodeStatus
                  : null,
            ),
          );
        } else {
          _replaceCollection(
            old.copyWith(
              type: type,
              rate: nextRate,
              comment: nextComment,
              tags: nextTags,
              private: nextPrivate,
              episodeStatus: resolvedEpisodeStatus,
              volumeStatus: nextVolumeStatus,
            ),
          );
        }
      } else {
        _replaceCollection(
          UserCollection(
            subjectId: subject.id,
            type: type,
            rate: nextRate,
            episodeStatus: resolvedEpisodeStatus,
            volumeStatus: nextVolumeStatus,
            updatedAt: DateTime.now(),
            subject: subject,
            comment: nextComment,
            tags: nextTags,
            private: nextPrivate,
          ),
        );
      }
      await _cacheSnapshot(subject.id, generation, username, () async {
        if (saveEpisodes != null) await saveEpisodes();
        _requireEditAccount(generation, username);
        await _snapshotCache.writeCollections(username, _view.collections);
      });
      _requireEditAccount(generation, username);
      return null;
    } catch (error) {
      if (optimistic &&
          !saved &&
          _isCurrentAuth(generation) &&
          _account?.username == username) {
        _subjectMutationRevisions[subject.id] = beforeRevision!;
        if (beforeCollection != null) {
          _replaceCollection(beforeCollection);
        } else {
          _view = _view.copyWith(
            collections: _view.collections
                .where((item) => item.subjectId != subject.id)
                .toList(),
          );
        }
      }
      return _messageFor(error);
    } finally {
      if (_isCurrentAuth(generation)) _optimisticSubjects.remove(subject.id);
    }
  });

  void _replaceCollection(UserCollection updated) {
    _view = _view.copyWith(
      collections: [
        for (final item in _view.collections)
          if (item.subjectId == updated.subjectId) updated else item,
      ],
    );
  }

  void _setUpdating(int subjectId, bool updating) {
    final subjects = {..._view.updatingSubjects};
    updating ? subjects.add(subjectId) : subjects.remove(subjectId);
    _view = _view.copyWith(updatingSubjects: subjects);
  }
}
