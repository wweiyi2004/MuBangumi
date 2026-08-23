import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/auth/bangumi_oauth.dart';
import 'package:mubangumi/core/auth/website_session.dart';
import 'package:mubangumi/core/network/bangumi_api.dart';
import 'package:mubangumi/core/network/bangumi_endpoints.dart';
import 'package:mubangumi/core/storage/bangumi_sync_store.dart';
import 'package:mubangumi/core/storage/snapshot_cache.dart';
import 'package:mubangumi/core/storage/token_store.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/state/session_controller.dart';

void main() {
  const config = OAuthConfig(clientId: 'client', clientSecret: 'secret');

  SessionController buildController({
    required TokenStore store,
    required BangumiOAuth oauth,
    BangumiApi? api,
    SnapshotCache? snapshotCache,
    BangumiSyncStore? syncStore,
  }) => SessionController(
    api ?? _FakeBangumiApi(),
    oauth,
    store,
    snapshotCache: snapshotCache ?? _MemorySnapshotCache(),
    syncStore: syncStore ?? _MemorySyncStore(),
    websiteSessionStore: _MemoryWebsiteSessionStore(),
  );

  test('transient OAuth refresh failure keeps stored credentials', () async {
    final store = _MemoryTokenStore(config: config);
    final controller = buildController(
      store: store,
      oauth: _FailingOAuth(const BangumiOAuthException('网络暂时不可用')),
    );
    addTearDown(controller.dispose);

    await _waitFor(() => controller.state.phase == SessionPhase.signedIn);

    expect(store.clearCalls, 0);
    expect(store.accessToken, 'stored-access-token');
    expect(store.refreshToken, 'stored-refresh-token');
  });

  test('invalid grant clears stored credentials', () async {
    final store = _MemoryTokenStore(config: config);
    final controller = buildController(
      store: store,
      oauth: _FailingOAuth(
        const BangumiOAuthException(
          'refresh token 已失效',
          invalidatesSession: true,
        ),
      ),
    );
    addTearDown(controller.dispose);

    await _waitFor(() => controller.state.phase == SessionPhase.signedOut);

    expect(store.clearCalls, 1);
    expect(store.accessToken, isNull);
    expect(store.refreshToken, isNull);
    expect(controller.state.message, contains('登录已过期'));
  });

  test('cancelling OAuth returns to login without an error message', () async {
    final store = _MemoryTokenStore(config: null)
      ..accessToken = null
      ..refreshToken = null
      ..expiresAt = null;
    final controller = buildController(
      store: store,
      oauth: _AuthorizeFailingOAuth(
        const BangumiOAuthException('已取消 Bangumi 授权', isCancelled: true),
      ),
    );
    addTearDown(controller.dispose);

    await _waitFor(() => controller.state.phase == SessionPhase.signedOut);
    final signedIn = await controller.signInWithOAuth(config);

    expect(signedIn, isFalse);
    expect(controller.state.phase, SessionPhase.signedOut);
    expect(controller.state.message, isNull);
    expect(store.config, config);
  });

  test(
    'OAuth authorize keeps signedOut so the auth UI can host launchers',
    () async {
      final store = _MemoryTokenStore(config: null)
        ..accessToken = null
        ..refreshToken = null
        ..expiresAt = null;
      final oauth = _PhaseObservingOAuth();
      final controller = buildController(store: store, oauth: oauth);
      addTearDown(controller.dispose);

      await _waitFor(() => controller.state.phase == SessionPhase.signedOut);

      late SessionPhase phaseDuringAuthorize;
      late bool refreshingDuringAuthorize;
      oauth.onAuthorize = () {
        phaseDuringAuthorize = controller.state.phase;
        refreshingDuringAuthorize = controller.state.isRefreshing;
      };

      var launcherCalled = false;
      final signedIn = await controller.signInWithOAuth(
        config,
        launchAuthorization: (uri, callback) async {
          launcherCalled = true;
          // AuthScreen must still be the host route (signedOut, not booting).
          expect(controller.state.phase, SessionPhase.signedOut);
          return false;
        },
      );

      expect(signedIn, isFalse);
      expect(launcherCalled, isTrue);
      expect(phaseDuringAuthorize, SessionPhase.signedOut);
      expect(refreshingDuringAuthorize, isTrue);
      expect(controller.state.phase, SessionPhase.signedOut);
    },
  );

  test(
    'late collection refresh cannot repopulate a signed-out session',
    () async {
      final api = _DelayedRefreshBangumiApi();
      final controller = buildController(
        store: _MemoryTokenStore(config: config),
        oauth: _FailingOAuth(const BangumiOAuthException('网络暂时不可用')),
        api: api,
      );
      addTearDown(controller.dispose);

      await _waitFor(
        () =>
            controller.state.phase == SessionPhase.signedIn &&
            !controller.state.isLoadingCollections,
      );
      api.delayNextAnimeLoad = true;
      final refresh = controller.refresh();
      await _waitFor(() => api.pendingAnimeLoad != null);

      await controller.signOut();
      api.pendingAnimeLoad!.complete(const [_testCollection]);
      await refresh;

      expect(controller.state.phase, SessionPhase.signedOut);
      expect(controller.state.collections, isEmpty);
    },
  );

  test(
    'late other-type collection load cannot repopulate a signed-out session',
    () async {
      final api = _DelayedOtherTypeBangumiApi();
      final controller = buildController(
        store: _MemoryTokenStore(config: config),
        oauth: _FailingOAuth(const BangumiOAuthException('网络暂时不可用')),
        api: api,
      );
      addTearDown(controller.dispose);

      await _waitFor(
        () =>
            controller.state.phase == SessionPhase.signedIn &&
            !controller.state.isLoadingCollections,
      );
      api.delayNextOtherTypeLoad = true;
      final refresh = controller.refresh();
      await _waitFor(() => api.pendingOtherTypeLoad != null);

      await controller.signOut();
      api.pendingOtherTypeLoad!.complete(const [_testCollection]);
      await refresh;

      expect(controller.state.phase, SessionPhase.signedOut);
      expect(controller.state.collections, isEmpty);
      expect(controller.state.isLoadingCollections, isFalse);
    },
  );

  test(
    'network-route persistence failure does not strand busy flags',
    () async {
      final api = _DelayedRefreshBangumiApi();
      final controller = buildController(
        store: _MemoryTokenStore(config: config)..failWriteNetworkRoute = true,
        oauth: _FailingOAuth(const BangumiOAuthException('网络暂时不可用')),
        api: api,
      );
      addTearDown(controller.dispose);

      await _waitFor(
        () =>
            controller.state.phase == SessionPhase.signedIn &&
            !controller.state.isLoadingCollections,
      );
      api.delayNextAnimeLoad = true;
      final refresh = controller.refresh();
      await _waitFor(() => api.pendingAnimeLoad != null);
      expect(controller.state.isRefreshing, isTrue);

      final error = await controller.setNetworkRoute(
        BangumiNetworkRoute.reverseProxy,
      );
      api.pendingAnimeLoad!.complete(const [_testCollection]);
      await refresh;

      expect(error, isNotNull);
      expect(error, contains('未能保存到本机'));
      expect(controller.state.networkRoute, BangumiNetworkRoute.reverseProxy);
      expect(controller.state.isRefreshing, isFalse);
      expect(controller.state.isLoadingCollections, isFalse);
    },
  );

  test('bootstrap shows cached collections before /me returns', () async {
    final api = _DelayedMeApi();
    const cachedUser = BangumiUser(
      id: 1,
      username: 'tester',
      nickname: '旧昵称',
      avatarUrl: '',
    );
    final cache = _MemorySnapshotCache()
      ..lastUser = cachedUser
      ..collections['tester'] = const [_testCollection];
    final controller = buildController(
      store: _MemoryTokenStore(config: config),
      oauth: _FailingOAuth(const BangumiOAuthException('网络暂时不可用')),
      api: api,
      snapshotCache: cache,
    );
    addTearDown(controller.dispose);

    await _waitFor(() => controller.state.phase == SessionPhase.signedIn);

    expect(controller.state.user?.nickname, '旧昵称');
    expect(controller.state.collections, isNotEmpty);
    expect(controller.state.isRefreshing, isFalse);
    expect(api.meCalls, 1);
    expect(api.completer.isCompleted, isFalse);

    api.completer.complete(
      const BangumiUser(
        id: 1,
        username: 'tester',
        nickname: '新昵称',
        avatarUrl: '',
      ),
    );
    await _waitFor(() => controller.state.user?.nickname == '新昵称');
    expect(cache.lastUser?.nickname, '新昵称');
  });

  test('snapshot survives a transient /me failure', () async {
    final cache = _MemorySnapshotCache()
      ..lastUser = const BangumiUser(
        id: 1,
        username: 'tester',
        nickname: '维依',
        avatarUrl: '',
      )
      ..collections['tester'] = const [_testCollection];
    final controller = buildController(
      store: _MemoryTokenStore(config: config),
      oauth: _FailingOAuth(const BangumiOAuthException('网络暂时不可用')),
      api: _FailingMeApi(const BangumiApiException('网络错误')),
      snapshotCache: cache,
    );
    addTearDown(controller.dispose);

    await _waitFor(
      () =>
          controller.state.phase == SessionPhase.signedIn &&
          (controller.state.message?.isNotEmpty ?? false),
    );

    expect(controller.state.collections, isNotEmpty);
    expect(controller.state.user?.username, 'tester');
    expect(controller.state.message, contains('本地缓存'));
  });

  test('account-switching /me drops the previous user snapshot', () async {
    final cache = _MemorySnapshotCache()
      ..lastUser = const BangumiUser(
        id: 1,
        username: 'old-user',
        nickname: '旧号',
        avatarUrl: '',
      )
      ..collections['old-user'] = const [_testCollection];
    final controller = buildController(
      store: _MemoryTokenStore(config: config),
      oauth: _FailingOAuth(const BangumiOAuthException('网络暂时不可用')),
      api: _FakeBangumiApi(),
      snapshotCache: cache,
    );
    addTearDown(controller.dispose);

    await _waitFor(
      () =>
          controller.state.phase == SessionPhase.signedIn &&
          controller.state.user?.username == 'tester',
    );

    expect(controller.state.collections, isEmpty);
    expect(cache.lastUser?.username, 'tester');
  });

  test('sign-out clears the persisted last user', () async {
    final cache = _MemorySnapshotCache()
      ..lastUser = const BangumiUser(
        id: 1,
        username: 'tester',
        nickname: 'Tester',
        avatarUrl: '',
      )
      ..collections['tester'] = const [_testCollection];
    final controller = buildController(
      store: _MemoryTokenStore(config: config),
      oauth: _FailingOAuth(const BangumiOAuthException('网络暂时不可用')),
      api: _FakeBangumiApi(),
      snapshotCache: cache,
    );
    addTearDown(controller.dispose);

    await _waitFor(() => controller.state.phase == SessionPhase.signedIn);
    await controller.signOut();

    expect(controller.state.phase, SessionPhase.signedOut);
    expect(cache.lastUser, isNull);
  });

  test('network route switch keeps OAuth busy flags intact', () async {
    final oauth = _HangingAuthorizeOAuth();
    final store = _MemoryTokenStore(config: null)
      ..accessToken = null
      ..refreshToken = null
      ..expiresAt = null;
    final controller = buildController(store: store, oauth: oauth);
    addTearDown(controller.dispose);

    await _waitFor(() => controller.state.phase == SessionPhase.signedOut);
    final signIn = controller.signInWithOAuth(config);
    await _waitFor(() => controller.state.isRefreshing);

    final error = await controller.setNetworkRoute(
      BangumiNetworkRoute.reverseProxy,
    );
    expect(error, isNull);
    expect(controller.state.networkRoute, BangumiNetworkRoute.reverseProxy);
    // The OAuth wait UI (spinner + cancel) must survive the switch.
    expect(controller.state.isRefreshing, isTrue);

    oauth.completer.completeError(
      const BangumiOAuthException('已取消 Bangumi 授权', isCancelled: true),
    );
    expect(await signIn, isFalse);
  });

  test(
    'offline collection edits stay local and coalesce until reconnect',
    () async {
      final api = _OfflineReplayApi();
      final syncStore = _MemorySyncStore();
      final snapshot = _MemorySnapshotCache();
      final controller = buildController(
        store: _MemoryTokenStore(config: config),
        oauth: _FailingOAuth(const BangumiOAuthException('网络暂时不可用')),
        api: api,
        snapshotCache: snapshot,
        syncStore: syncStore,
      );
      addTearDown(controller.dispose);

      await _waitFor(() => controller.state.phase == SessionPhase.signedIn);
      expect(
        await controller.changeCollection(
          _testSubject,
          CollectionType.wish,
          completeEpisodesWhenDone: false,
        ),
        isNull,
      );
      expect(
        await controller.changeCollection(
          _testSubject,
          CollectionType.done,
          completeEpisodesWhenDone: false,
        ),
        isNull,
      );
      await _waitFor(() => controller.state.pendingSyncCount == 1);
      await _waitFor(() => !controller.state.isSyncing);

      expect(
        controller.state.collectionFor(_testSubject.id)?.type,
        CollectionType.done,
      );
      expect(snapshot.collections['tester']?.single.type, CollectionType.done);
      final queued = await syncStore.pendingFor('tester');
      expect(queued, hasLength(1));
      expect(
        queued.single.payload['collection_type'],
        CollectionType.done.value,
      );

      await controller.refresh();
      expect(
        controller.state.collectionFor(_testSubject.id)?.type,
        CollectionType.done,
      );
      await _waitFor(() => !controller.state.isSyncing);

      api.offline = false;
      await controller.syncPendingChanges();

      expect(controller.state.pendingSyncCount, 0);
      expect(api.replayed, hasLength(1));
      expect(api.replayed.single['collection_type'], CollectionType.done.value);
    },
  );

  test(
    'mark next episode revalidates a stale snapshot before choosing',
    () async {
      final api = _FreshEpisodeApi();
      final snapshot = _MemorySnapshotCache()
        ..episodeCollections[_testSubject.id] = [
          _testEpisodeCollection(7, 1),
          _testEpisodeCollection(8, 2),
        ];
      final controller = buildController(
        store: _MemoryTokenStore(config: config),
        oauth: _FailingOAuth(const BangumiOAuthException('网络暂时不可用')),
        api: api,
        snapshotCache: snapshot,
      );
      addTearDown(controller.dispose);

      await _waitFor(() => controller.state.phase == SessionPhase.signedIn);
      final collection = controller.state.collectionFor(_testSubject.id)!;

      expect(await controller.markNextEpisode(collection), isNull);
      await _waitFor(() => api.replayed.isNotEmpty);

      expect(api.episodeCollectionCalls, 1);
      expect(api.replayed.single['episode_id'], 8);
      expect(
        snapshot.episodeCollections[_testSubject.id]!.map((item) => item.type),
        [2, 2],
      );
    },
  );

  test('newer local edit survives an older in-flight upload', () async {
    final api = _ControlledReplayApi();
    final syncStore = _MemorySyncStore();
    final controller = buildController(
      store: _MemoryTokenStore(config: config),
      oauth: _FailingOAuth(const BangumiOAuthException('网络暂时不可用')),
      api: api,
      syncStore: syncStore,
    );
    addTearDown(controller.dispose);

    await _waitFor(() => controller.state.phase == SessionPhase.signedIn);
    await controller.changeCollection(
      _testSubject,
      CollectionType.wish,
      completeEpisodesWhenDone: false,
    );
    await api.firstUploadStarted.future;
    await controller.changeCollection(
      _testSubject,
      CollectionType.done,
      completeEpisodesWhenDone: false,
    );
    api.releaseFirstUpload.complete();

    await _waitFor(
      () => api.replayed.length == 2 && controller.state.pendingSyncCount == 0,
    );
    expect(api.replayed.map((item) => item['collection_type']), [
      CollectionType.wish.value,
      CollectionType.done.value,
    ]);
  });

  test(
    'episode snapshot keeps the local edit after its upload lands',
    () async {
      final api = _ControlledReplayApi();
      final snapshot = _MemorySnapshotCache();
      final controller = buildController(
        store: _MemoryTokenStore(config: config),
        oauth: _FailingOAuth(const BangumiOAuthException('网络暂时不可用')),
        api: api,
        snapshotCache: snapshot,
      );
      addTearDown(controller.dispose);

      await _waitFor(() => controller.state.phase == SessionPhase.signedIn);
      snapshot.episodeCollections[_testSubject.id] = [
        _testEpisodeCollection(7, 1),
      ];

      expect(
        await controller.setEpisode(
          subjectId: _testSubject.id,
          episodeId: 7,
          type: 2,
          previousType: 0,
          trackGlobalBusy: false,
        ),
        isNull,
      );

      // Let the in-flight upload finish and remove the queue entry; the
      // snapshot must still carry the watch mark for a later offline read.
      api.releaseFirstUpload.complete();
      await _waitFor(() => controller.state.pendingSyncCount == 0);

      final cached = snapshot.episodeCollections[_testSubject.id];
      expect(cached, isNotNull);
      expect(cached!.single.type, 2);
    },
  );

  test(
    'edits enqueued during a drain upload without another trigger',
    () async {
      final api = _ControlledReplayApi();
      final snapshot = _MemorySnapshotCache();
      final controller = buildController(
        store: _MemoryTokenStore(config: config),
        oauth: _FailingOAuth(const BangumiOAuthException('网络暂时不可用')),
        api: api,
        snapshotCache: snapshot,
      );
      addTearDown(controller.dispose);

      await _waitFor(() => controller.state.phase == SessionPhase.signedIn);
      snapshot.episodeCollections[_testSubject.id] = [
        _testEpisodeCollection(7, 1),
        _testEpisodeCollection(8, 2),
      ];

      expect(
        await controller.setEpisode(
          subjectId: _testSubject.id,
          episodeId: 7,
          type: 2,
          previousType: 0,
          trackGlobalBusy: false,
        ),
        isNull,
      );
      await api.firstUploadStarted.future;
      // A different key enqueued mid-drain is outside the snapshot the running
      // drain already fetched; it must still upload without any new trigger.
      expect(
        await controller.setEpisode(
          subjectId: _testSubject.id,
          episodeId: 8,
          type: 2,
          previousType: 0,
          trackGlobalBusy: false,
        ),
        isNull,
      );
      api.releaseFirstUpload.complete();

      await _waitFor(
        () =>
            api.replayed.length == 2 && controller.state.pendingSyncCount == 0,
      );
      expect(api.replayed.map((item) => item['episode_id']), [7, 8]);
    },
  );

  test('manual retry runs even while a drain is already in flight', () async {
    final api = _ControlledReplayApi();
    final syncStore = _MemorySyncStore();
    // Seed a blocked entry left over from an earlier non-retryable failure.
    await syncStore.enqueue(
      username: 'tester',
      kind: BangumiMutationKind.episode,
      mutationKey: 'episode:99',
      payload: {'subject_id': _testSubject.id, 'episode_id': 99, 'type': 2},
    );
    final seeded = (await syncStore.pendingFor(
      'tester',
      includeBlocked: true,
    )).single;
    expect(
      await syncStore.markFailure(seeded, 'HTTP 400', blocked: true),
      isTrue,
    );

    final controller = buildController(
      store: _MemoryTokenStore(config: config),
      oauth: _FailingOAuth(const BangumiOAuthException('网络暂时不可用')),
      api: api,
      syncStore: syncStore,
    );
    addTearDown(controller.dispose);

    await _waitFor(() => controller.state.phase == SessionPhase.signedIn);
    await _waitFor(() => controller.state.blockedSyncCount == 1);
    await _waitFor(() => !controller.state.isSyncing);

    expect(
      await controller.setEpisode(
        subjectId: _testSubject.id,
        episodeId: 7,
        type: 2,
        previousType: 0,
        trackGlobalBusy: false,
      ),
      isNull,
    );
    await api.firstUploadStarted.future;

    // The manual retry must chain past the hanging drain instead of joining
    // it and returning without ever unblocking the seeded entry.
    final manualRetry = controller.syncPendingChanges(retryBlocked: true);
    api.releaseFirstUpload.complete();
    await manualRetry;

    expect(controller.state.pendingSyncCount, 0);
    expect(controller.state.blockedSyncCount, 0);
    expect(api.replayed.map((item) => item['episode_id']), [7, 99]);
  });
}

const _testSubject = Subject(
  id: 99,
  name: 'late',
  nameCn: '迟到结果',
  imageUrl: '',
  summary: '',
  episodeCount: 1,
  score: 0,
  rank: 0,
  date: '',
);

const _testCollection = UserCollection(
  subjectId: 99,
  type: CollectionType.doing,
  rate: 0,
  episodeStatus: 0,
  updatedAt: null,
  subject: _testSubject,
);

UserEpisodeCollection _testEpisodeCollection(int id, int number) =>
    UserEpisodeCollection(
      episode: Episode(
        id: id,
        type: 0,
        number: number.toDouble(),
        sort: number.toDouble(),
        name: 'Episode $number',
        nameCn: '第$number话',
        airDate: '',
        description: '',
      ),
      type: 0,
      updatedAt: 0,
    );

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('Timed out waiting for asynchronous session state');
}

class _FailingOAuth extends BangumiOAuth {
  _FailingOAuth(this.error);

  final BangumiOAuthException error;

  @override
  Future<OAuthTokenBundle> refresh(
    OAuthConfig config,
    String refreshToken,
  ) async {
    throw error;
  }
}

class _AuthorizeFailingOAuth extends BangumiOAuth {
  _AuthorizeFailingOAuth(this.error);

  final BangumiOAuthException error;

  @override
  Future<OAuthTokenBundle> authorize(
    OAuthConfig config, {
    OAuthAuthorizationLauncher? launchAuthorization,
  }) async {
    throw error;
  }
}

/// Invokes [onAuthorize] while still inside authorize so the session phase
/// can be asserted before tokens exist.
class _PhaseObservingOAuth extends BangumiOAuth {
  void Function()? onAuthorize;

  @override
  Future<OAuthTokenBundle> authorize(
    OAuthConfig config, {
    OAuthAuthorizationLauncher? launchAuthorization,
  }) async {
    onAuthorize?.call();
    // Never-completing callback: this test only cares about the session phase
    // around the launcher call, not a full code exchange.
    final pendingCallback = Completer<Uri>().future;
    final opened = launchAuthorization == null
        ? true
        : await launchAuthorization(
            Uri.parse('https://bgm.tv/oauth/authorize'),
            pendingCallback,
          );
    if (!opened) {
      throw const BangumiOAuthException('已取消 Bangumi 授权', isCancelled: true);
    }
    throw const BangumiOAuthException('unexpected open');
  }
}

class _DelayedMeApi extends _FakeBangumiApi {
  final completer = Completer<BangumiUser>();
  int meCalls = 0;

  @override
  Future<BangumiUser> getMe() {
    meCalls++;
    return completer.future;
  }
}

class _FailingMeApi extends _FakeBangumiApi {
  _FailingMeApi(this.error);

  final BangumiApiException error;

  @override
  Future<BangumiUser> getMe() async => throw error;
}

class _MemorySnapshotCache extends SnapshotCache {
  BangumiUser? lastUser;
  final Map<String, List<UserCollection>> collections = {};
  final Map<int, List<UserEpisodeCollection>> episodeCollections = {};

  @override
  Future<BangumiUser?> readLastUser() async => lastUser;

  @override
  Future<void> writeLastUser(BangumiUser user) async {
    lastUser = user;
  }

  @override
  Future<void> clearLastUser() async {
    lastUser = null;
  }

  @override
  Future<List<UserCollection>?> readCollections(String username) async =>
      collections[username.trim().toLowerCase()];

  @override
  Future<void> writeCollections(
    String username,
    List<UserCollection> items,
  ) async {
    collections[username.trim().toLowerCase()] = items;
  }

  @override
  Future<List<UserEpisodeCollection>?> readEpisodeCollections(
    int subjectId,
  ) async => episodeCollections[subjectId];

  @override
  Future<void> writeEpisodeCollections(
    int subjectId,
    List<UserEpisodeCollection> episodes,
  ) async {
    episodeCollections[subjectId] = episodes;
  }
}

class _MemorySyncStore extends BangumiSyncStore {
  final List<PendingBangumiMutation> mutations = [];
  var _nextId = 1;

  @override
  Future<void> enqueue({
    required String username,
    required BangumiMutationKind kind,
    required String mutationKey,
    required Map<String, dynamic> payload,
  }) async {
    final index = mutations.indexWhere(
      (item) => item.username == username && item.mutationKey == mutationKey,
    );
    if (index < 0) {
      mutations.add(
        PendingBangumiMutation(
          id: _nextId++,
          username: username,
          kind: kind,
          mutationKey: mutationKey,
          payload: Map<String, dynamic>.from(payload),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          revision: 1,
          attempts: 0,
          blocked: false,
        ),
      );
      return;
    }
    final existing = mutations[index];
    mutations[index] = PendingBangumiMutation(
      id: existing.id,
      username: username,
      kind: kind,
      mutationKey: mutationKey,
      payload: Map<String, dynamic>.from(payload),
      createdAt: existing.createdAt,
      updatedAt: DateTime.now(),
      revision: existing.revision + 1,
      attempts: 0,
      blocked: false,
    );
  }

  @override
  Future<List<PendingBangumiMutation>> pendingFor(
    String username, {
    bool includeBlocked = false,
  }) async => [
    for (final item in mutations)
      if (item.username == username && (includeBlocked || !item.blocked)) item,
  ];

  @override
  Future<int> countFor(String username) async =>
      mutations.where((item) => item.username == username).length;

  @override
  Future<int> blockedCountFor(String username) async => mutations
      .where((item) => item.username == username && item.blocked)
      .length;

  @override
  Future<bool> removeIfUnchanged(PendingBangumiMutation mutation) async {
    final before = mutations.length;
    mutations.removeWhere(
      (item) => item.id == mutation.id && item.revision == mutation.revision,
    );
    return mutations.length < before;
  }

  @override
  Future<bool> markFailure(
    PendingBangumiMutation mutation,
    String message, {
    required bool blocked,
  }) async {
    final index = mutations.indexWhere(
      (item) => item.id == mutation.id && item.revision == mutation.revision,
    );
    if (index < 0) return false;
    final item = mutations[index];
    mutations[index] = PendingBangumiMutation(
      id: item.id,
      username: item.username,
      kind: item.kind,
      mutationKey: item.mutationKey,
      payload: item.payload,
      createdAt: item.createdAt,
      updatedAt: DateTime.now(),
      revision: item.revision,
      attempts: item.attempts + 1,
      blocked: blocked,
      lastError: message,
    );
    return true;
  }

  @override
  Future<void> retryBlocked(String username) async {
    for (var index = 0; index < mutations.length; index++) {
      final item = mutations[index];
      if (item.username != username || !item.blocked) continue;
      mutations[index] = PendingBangumiMutation(
        id: item.id,
        username: item.username,
        kind: item.kind,
        mutationKey: item.mutationKey,
        payload: item.payload,
        createdAt: item.createdAt,
        updatedAt: DateTime.now(),
        revision: item.revision,
        attempts: 0,
        blocked: false,
      );
    }
  }
}

class _FakeBangumiApi extends BangumiApi {
  @override
  Future<BangumiUser> getMe() async => const BangumiUser(
    id: 1,
    username: 'tester',
    nickname: 'Tester',
    avatarUrl: '',
  );

  @override
  Future<List<UserCollection>> getUserCollections(
    String username, {
    SubjectType? subjectType,
    CollectionType? collectionType,
    int? maxItems,
  }) async => const [];
}

class _OfflineReplayApi extends _FakeBangumiApi {
  bool offline = true;
  final List<Map<String, dynamic>> replayed = [];

  @override
  Future<List<UserCollection>> getUserCollections(
    String username, {
    SubjectType? subjectType,
    CollectionType? collectionType,
    int? maxItems,
  }) async =>
      subjectType == SubjectType.anime ? const [_testCollection] : const [];

  @override
  Future<void> replayPendingMutation(
    BangumiMutationKind kind,
    Map<String, dynamic> payload,
  ) async {
    if (offline) {
      throw const BangumiApiException('没有网络', retryable: true);
    }
    replayed.add(Map<String, dynamic>.from(payload));
  }
}

class _FreshEpisodeApi extends _OfflineReplayApi {
  _FreshEpisodeApi() {
    offline = false;
  }

  int episodeCollectionCalls = 0;

  @override
  Future<List<UserEpisodeCollection>> getEpisodeCollections(
    int subjectId, {
    int? episodeType = 0,
  }) async {
    episodeCollectionCalls++;
    return [
      _testEpisodeCollection(7, 1).copyWith(type: 2),
      _testEpisodeCollection(8, 2),
    ];
  }
}

class _ControlledReplayApi extends _OfflineReplayApi {
  _ControlledReplayApi() {
    offline = false;
  }

  final firstUploadStarted = Completer<void>();
  final releaseFirstUpload = Completer<void>();

  @override
  Future<void> replayPendingMutation(
    BangumiMutationKind kind,
    Map<String, dynamic> payload,
  ) async {
    replayed.add(Map<String, dynamic>.from(payload));
    if (replayed.length == 1) {
      firstUploadStarted.complete();
      await releaseFirstUpload.future;
    }
  }
}

class _DelayedRefreshBangumiApi extends _FakeBangumiApi {
  bool delayNextAnimeLoad = false;
  Completer<List<UserCollection>>? pendingAnimeLoad;

  @override
  Future<List<UserCollection>> getUserCollections(
    String username, {
    SubjectType? subjectType,
    CollectionType? collectionType,
    int? maxItems,
  }) {
    if (delayNextAnimeLoad && subjectType == SubjectType.anime) {
      delayNextAnimeLoad = false;
      final completer = Completer<List<UserCollection>>();
      pendingAnimeLoad = completer;
      return completer.future;
    }
    return Future.value(const []);
  }
}

class _DelayedOtherTypeBangumiApi extends _FakeBangumiApi {
  bool delayNextOtherTypeLoad = false;
  Completer<List<UserCollection>>? pendingOtherTypeLoad;

  @override
  Future<List<UserCollection>> getUserCollections(
    String username, {
    SubjectType? subjectType,
    CollectionType? collectionType,
    int? maxItems,
  }) {
    if (delayNextOtherTypeLoad &&
        subjectType != null &&
        subjectType != SubjectType.anime) {
      delayNextOtherTypeLoad = false;
      final completer = Completer<List<UserCollection>>();
      pendingOtherTypeLoad = completer;
      return completer.future;
    }
    return Future.value(const []);
  }
}

class _HangingAuthorizeOAuth extends BangumiOAuth {
  final Completer<OAuthTokenBundle> completer = Completer<OAuthTokenBundle>();

  @override
  Future<OAuthTokenBundle> authorize(
    OAuthConfig config, {
    OAuthAuthorizationLauncher? launchAuthorization,
  }) => completer.future;
}

class _MemoryWebsiteSessionStore extends WebsiteSessionStore {
  WebsiteSessionSnapshot? snapshot;

  @override
  Future<WebsiteSessionSnapshot?> read() async => snapshot;

  @override
  Future<void> write(WebsiteSessionSnapshot snapshot) async {
    this.snapshot = snapshot;
  }

  @override
  Future<void> clear() async {
    snapshot = null;
  }
}

class _MemoryTokenStore extends TokenStore {
  _MemoryTokenStore({required this.config});

  String? accessToken = 'stored-access-token';
  String? refreshToken = 'stored-refresh-token';
  DateTime? expiresAt = DateTime.now().subtract(const Duration(minutes: 1));
  OAuthConfig? config;
  int clearCalls = 0;

  @override
  Future<String?> read() async => accessToken;

  @override
  Future<String?> readRefreshToken() async => refreshToken;

  @override
  Future<DateTime?> readExpiresAt() async => expiresAt;

  @override
  Future<OAuthConfig?> readOAuthConfig() async => config;

  @override
  Future<void> writeOAuthConfig(OAuthConfig config) async {
    this.config = config;
  }

  @override
  Future<BangumiNetworkRoute> readNetworkRoute() async =>
      BangumiNetworkRoute.official;

  bool failWriteNetworkRoute = false;
  BangumiNetworkRoute? storedNetworkRoute;

  @override
  Future<void> writeNetworkRoute(BangumiNetworkRoute route) async {
    if (failWriteNetworkRoute) {
      throw StateError('secure storage unavailable');
    }
    storedNetworkRoute = route;
  }

  @override
  Future<void> writeTokens(OAuthTokenBundle tokens) async {
    accessToken = tokens.accessToken;
    refreshToken = tokens.refreshToken;
    expiresAt = tokens.expiresAt;
  }

  @override
  Future<void> clear() async {
    clearCalls++;
    accessToken = null;
    refreshToken = null;
    expiresAt = null;
  }
}
