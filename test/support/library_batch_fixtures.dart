import 'dart:async';

import 'package:mubangumi/core/auth/bangumi_oauth.dart';
import 'package:mubangumi/core/network/bangumi_api.dart';
import 'package:mubangumi/core/network/bangumi_endpoints.dart';
import 'package:mubangumi/core/storage/bangumi_sync_store.dart';
import 'package:mubangumi/core/storage/snapshot_cache.dart';
import 'package:mubangumi/core/storage/token_store.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/models/library_batch.dart';
import 'package:mubangumi/state/session_controller.dart';

UserCollection batchFixtureCollection(int id, {SubjectType? type}) =>
    UserCollection(
      subjectId: id,
      type: CollectionType.doing,
      rate: 8,
      episodeStatus: 3,
      volumeStatus: 2,
      updatedAt: DateTime(2026, 9, 8),
      comment: '保留吐槽$id',
      tags: ['保留标签$id'],
      private: true,
      subject: Subject(
        id: id,
        type: type ?? SubjectType.values[(id - 1) % SubjectType.values.length],
        name: '作品$id',
        nameCn: id == 1 ? '旅途中的新篇章与尚未说完的故事' : '收藏作品 $id',
        imageUrl: '',
        summary: '',
        episodeCount: 12,
        score: 8.5,
        rank: 100,
        date: '2026-01-01',
      ),
    );

class BatchTestApi extends BangumiApi {
  BatchTestApi(this.server);
  List<UserCollection> server;
  bool offline = true;
  final rejectedIds = <int>{};
  final replayed = <Map<String, dynamic>>[];
  final episodeUpdates = <List<int>>[];
  @override
  Future<List<UserCollection>> getUserCollections(
    String username, {
    SubjectType? subjectType,
    CollectionType? collectionType,
    int? maxItems,
    Future<bool> Function(List<UserCollection>)? onPage,
  }) async => server
      .where((item) => subjectType == null || item.subject.type == subjectType)
      .toList();
  @override
  Future<void> replayPendingMutation(
    BangumiMutationKind kind,
    Map<String, dynamic> payload,
  ) async {
    if (offline) throw const BangumiApiException('offline', retryable: true);
    if (rejectedIds.contains(payload['subject_id'])) {
      throw const BangumiApiException('服务器拒绝此项', statusCode: 400);
    }
    replayed.add(Map.from(payload));
    if (kind == BangumiMutationKind.collection) {
      server = [
        for (final item in server)
          if (item.subjectId != payload['subject_id'])
            item
          else
            item.copyWith(
              type: CollectionType.fromValue(payload['collection_type'] as int),
              rate: payload['status_only'] == true
                  ? null
                  : payload['rate'] as int?,
              comment: payload['status_only'] == true
                  ? null
                  : payload['comment'] as String?,
            ),
      ];
    }
  }

  @override
  Future<List<UserEpisodeCollection>> getEpisodeCollections(
    int subjectId, {
    int? episodeType = 0,
  }) async => [
    for (var id = 1; id <= 3; id++)
      UserEpisodeCollection(
        episode: Episode(
          id: subjectId * 100 + id,
          type: id == 3 ? 1 : 0,
          number: id.toDouble(),
          sort: id.toDouble(),
          name: 'EP$id',
          nameCn: '',
          airDate: '',
          description: '',
        ),
        type: 0,
        updatedAt: 0,
      ),
  ];
  @override
  Future<void> updateEpisodesBatch(
    int subjectId, {
    required List<int> episodeIds,
    int type = 2,
  }) async {
    episodeUpdates.add(episodeIds);
  }
}

class BatchTestCache extends SnapshotCache {
  bool failWrites = false;
  final episodes = <String, List<UserEpisodeCollection>>{};
  @override
  Future<List<UserEpisodeCollection>?> readEpisodeCollections(
    int subjectId, {
    String? username,
  }) async => episodes['$username/$subjectId'];
  @override
  Future<void> writeEpisodeCollections(
    int subjectId,
    List<UserEpisodeCollection> items, {
    String? username,
  }) async {
    if (failWrites) throw StateError('cache write');
    episodes['$username/$subjectId'] = items;
  }

  @override
  Future<void> writeCollections(
    String username,
    List<UserCollection> items,
  ) async {
    if (failWrites) throw StateError('cache write');
  }
}

class BatchTestSession extends SessionController {
  BatchTestSession(this.api, this.queue, {BatchTestCache? cache})
    : super(
        api,
        BangumiOAuth(),
        _Tokens(),
        snapshotCache: cache ?? BatchTestCache(),
        syncStore: queue,
      ) {
    switchUser(1);
  }
  final BatchTestApi api;
  final BangumiSyncStore queue;
  void switchUser(int id) => state = SessionState(
    phase: SessionPhase.signedIn,
    user: BangumiUser(
      id: id,
      username: 'batch$id',
      nickname: '测试账号$id',
      avatarUrl: '',
    ),
    collections: api.server,
  );
  void removeLocally(int id) => state = state.copyWith(
    collections: state.collections
        .where((item) => item.subjectId != id)
        .toList(),
  );
  LibraryBatchItem target(int id) => LibraryBatchItem(
    subject: state.collectionFor(id)!.subject,
    revision: collectionMutationRevision(id),
  );
}

class BatchTestQueue extends BangumiSyncStore {
  BatchTestQueue({super.databasePath});
  final failingIds = <int>{};
  Future<void>? saveGate;
  int calls = 0;
  @override
  Future<void> enqueue({
    required String username,
    required BangumiMutationKind kind,
    required String mutationKey,
    required Map<String, dynamic> payload,
  }) async {
    calls++;
    await saveGate;
    if (failingIds.contains(payload['subject_id'])) {
      throw StateError('disk failure');
    }
    return super.enqueue(
      username: username,
      kind: kind,
      mutationKey: mutationKey,
      payload: payload,
    );
  }
}

class _Tokens extends TokenStore {
  @override
  Future<BangumiNetworkRoute> readNetworkRoute() =>
      Completer<BangumiNetworkRoute>().future;
}

class MemoryBatchQueue extends BangumiSyncStore {
  final items = <PendingBangumiMutation>[];
  final failingIds = <int>{};
  Future<void>? saveGate;
  int calls = 0, _id = 0;
  @override
  Future<void> enqueue({
    required String username,
    required BangumiMutationKind kind,
    required String mutationKey,
    required Map<String, dynamic> payload,
  }) async {
    calls++;
    await saveGate;
    if (failingIds.contains(payload['subject_id'])) {
      throw StateError('save failed');
    }
    final previous = items
        .where(
          (item) =>
              item.username == username && item.mutationKey == mutationKey,
        )
        .firstOrNull;
    items.removeWhere(
      (item) => item.username == username && item.mutationKey == mutationKey,
    );
    items.add(
      PendingBangumiMutation(
        id: ++_id,
        username: username,
        kind: kind,
        mutationKey: mutationKey,
        payload: Map.from(payload),
        createdAt: previous?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
        revision: (previous?.revision ?? 0) + 1,
        attempts: 0,
        blocked: false,
      ),
    );
  }

  @override
  Future<List<PendingBangumiMutation>> pendingFor(
    String username, {
    bool includeBlocked = false,
  }) async => items
      .where(
        (item) =>
            item.username == username && (includeBlocked || !item.blocked),
      )
      .toList();
  @override
  Future<List<PendingBangumiMutation>> blockedFor(String username) async =>
      items.where((item) => item.username == username && item.blocked).toList();
  @override
  Future<int> countFor(String username) async =>
      items.where((item) => item.username == username).length;
  @override
  Future<int> blockedCountFor(String username) async =>
      items.where((item) => item.username == username && item.blocked).length;
  @override
  Future<bool> removeIfUnchanged(PendingBangumiMutation mutation) async {
    final before = items.length;
    items.removeWhere(
      (item) => item.id == mutation.id && item.revision == mutation.revision,
    );
    return items.length < before;
  }

  bool _replace(
    PendingBangumiMutation mutation, {
    required bool blocked,
    required int attempts,
    String? error,
  }) {
    final index = items.indexWhere(
      (item) => item.id == mutation.id && item.revision == mutation.revision,
    );
    if (index < 0) return false;
    items[index] = PendingBangumiMutation(
      id: mutation.id,
      username: mutation.username,
      kind: mutation.kind,
      mutationKey: mutation.mutationKey,
      payload: mutation.payload,
      createdAt: mutation.createdAt,
      updatedAt: DateTime.now(),
      revision: mutation.revision,
      attempts: attempts,
      blocked: blocked,
      lastError: error,
    );
    return true;
  }

  @override
  Future<bool> markFailure(
    PendingBangumiMutation mutation,
    String message, {
    required bool blocked,
  }) async => _replace(
    mutation,
    blocked: blocked,
    attempts: mutation.attempts + 1,
    error: message,
  );
  @override
  Future<bool> retryIfUnchanged(PendingBangumiMutation mutation) async =>
      _replace(mutation, blocked: false, attempts: 0);
  @override
  Future<void> retryBlocked(String username) async {
    for (final item
        in items
            .where((item) => item.username == username && item.blocked)
            .toList()) {
      _replace(item, blocked: false, attempts: 0);
    }
  }

  @override
  Future<bool> discardIfUnchanged(PendingBangumiMutation mutation) async =>
      mutation.blocked && await removeIfUnchanged(mutation);
}
