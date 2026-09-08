import 'dart:async';

import 'package:mubangumi/core/auth/bangumi_oauth.dart';
import 'package:mubangumi/core/network/bangumi_api.dart';
import 'package:mubangumi/core/network/bangumi_endpoints.dart';
import 'package:mubangumi/core/storage/bangumi_sync_store.dart';
import 'package:mubangumi/core/storage/snapshot_cache.dart';
import 'package:mubangumi/core/storage/token_store.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/state/session_controller.dart';

UserCollection progressCollection(int id) => UserCollection(
  subjectId: id,
  type: CollectionType.doing,
  rate: 8,
  episodeStatus: 0,
  updatedAt: null,
  subject: Subject(
    id: id,
    name: '作品$id',
    nameCn: id == 1 ? '葬送的芙莉莲：旅途中还没有说完的故事' : '正在追的作品 $id',
    imageUrl: '',
    summary: '',
    episodeCount: 12,
    score: 8.5,
    rank: 50,
    date: '',
  ),
);
Episode progressEpisode(int id) => Episode(
  id: id,
  type: 0,
  number: id.toDouble(),
  sort: id.toDouble(),
  name: 'Episode $id',
  nameCn: '第 $id 话',
  airDate: '',
  description: '',
);

class ProgressApi extends BangumiApi {
  final types = <int, int>{};
  final writes = <int>[];
  bool offline = false;
  @override
  Future<List<UserEpisodeCollection>> getEpisodeCollections(
    int subjectId, {
    int? episodeType = 0,
  }) async => [
    for (var id = 1; id <= 12; id++)
      UserEpisodeCollection(
        episode: progressEpisode(id),
        type: types[id] ?? 0,
        updatedAt: 0,
      ),
  ];
  @override
  Future<void> replayPendingMutation(
    BangumiMutationKind kind,
    Map<String, dynamic> payload,
  ) async {
    if (offline) throw const BangumiApiException('offline', retryable: true);
    if (kind == BangumiMutationKind.episode) {
      types[payload['episode_id'] as int] = payload['type'] as int;
      writes.add(payload['type'] as int);
    }
  }
}

class ProgressCache extends SnapshotCache {
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
    episodes['$username/$subjectId'] = List.from(items);
  }

  @override
  Future<void> writeCollections(
    String username,
    List<UserCollection> items,
  ) async {}
}

class ProgressSession extends SessionController {
  ProgressSession(ProgressApi api, ProgressCache cache)
    : super(
        api,
        BangumiOAuth(),
        _Tokens(),
        snapshotCache: cache,
        syncStore: _Queue(),
      ) {
    switchUser(1);
  }
  void switchUser(int id) => state = SessionState(
    phase: SessionPhase.signedIn,
    user: BangumiUser(
      id: id,
      username: 'account$id',
      nickname: '小沐',
      avatarUrl: '',
    ),
    collections: [for (var id = 1; id <= 20; id++) progressCollection(id)],
  );
  void finish(int id) => state = state.copyWith(
    collections: [
      for (final item in state.collections)
        item.subjectId == id ? item.copyWith(type: CollectionType.done) : item,
    ],
  );
}

class _Tokens extends TokenStore {
  @override
  Future<BangumiNetworkRoute> readNetworkRoute() =>
      Completer<BangumiNetworkRoute>().future;
}

class _Queue extends BangumiSyncStore {
  final items = <String, PendingBangumiMutation>{};
  int sequence = 0;
  @override
  Future<void> enqueue({
    required String username,
    required BangumiMutationKind kind,
    required String mutationKey,
    required Map<String, dynamic> payload,
  }) async {
    final key = '$username/$mutationKey',
        previous = items['$username/$mutationKey'];
    items[key] = PendingBangumiMutation(
      id: ++sequence,
      username: username,
      kind: kind,
      mutationKey: mutationKey,
      payload: Map.from(payload),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      revision: (previous?.revision ?? 0) + 1,
      attempts: 0,
      blocked: false,
    );
  }

  @override
  Future<List<PendingBangumiMutation>> pendingFor(
    String username, {
    bool includeBlocked = false,
  }) async =>
      items.values.where((item) => item.username == username).toList()
        ..sort((a, b) => a.id.compareTo(b.id));
  @override
  Future<int> countFor(String username) async =>
      items.values.where((item) => item.username == username).length;
  @override
  Future<int> blockedCountFor(String username) async => 0;
  @override
  Future<bool> removeIfUnchanged(PendingBangumiMutation mutation) async {
    final key = '${mutation.username}/${mutation.mutationKey}';
    if (items[key]?.id != mutation.id) return false;
    items.remove(key);
    return true;
  }

  @override
  Future<bool> markFailure(
    PendingBangumiMutation mutation,
    String message, {
    required bool blocked,
  }) async => true;
}
