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

/// Regression tests for two reported session-controller bugs.
///
/// Bug 1: a local edit must not invalidate an unrelated background load of
/// the remaining collection types.
///
/// Bug 2: a refresh that lands while an episode edit is still pending must
/// retain the optimistic watch progress instead of persisting a stale value.
void main() {
  const config = OAuthConfig(clientId: 'client', clientSecret: 'secret');

  SessionController buildController({
    required TokenStore store,
    required BangumiOAuth oauth,
    required BangumiApi api,
  }) => SessionController(
    api,
    oauth,
    store,
    snapshotCache: _MemorySnapshotCache(),
    syncStore: _MemorySyncStore(),
    websiteSessionStore: _MemoryWebsiteSessionStore(),
  );

  Future<void> pump([int ms = 25]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  test(
    'episode edit does not abort the remaining collection-type load',
    () async {
      final api = _DelayedBookApi();
      final controller = buildController(
        store: _MemoryTokenStore(config: config),
        oauth: _TransientFailingOAuth(),
        api: api,
      );
      addTearDown(controller.dispose);

      // Bootstrap signs in; anime loads first, then background loop starts.
      await _waitFor(() => controller.state.phase == SessionPhase.signedIn);
      await _waitFor(() => api.bookRequested);

      // User taps an episode cell while book/music/game/real are loading.
      final editError = await controller.setEpisode(
        subjectId: 99,
        episodeId: 11,
        type: 2,
        previousType: 0,
        trackGlobalBusy: false,
      );
      expect(editError, isNull);

      // The pending book response finally arrives with data...
      api.pendingBookLoad!.complete([
        UserCollection(
          subjectId: 200,
          type: CollectionType.doing,
          rate: 0,
          episodeStatus: 0,
          updatedAt: null,
          subject: _bookSubject,
        ),
      ]);
      await pump(300);

      expect(
        controller.state.collections.any((item) => item.subjectId == 200),
        isTrue,
        reason: 'book data that arrived after the edit must still be merged',
      );
      expect(
        controller.state.collectionFor(99)!.episodeStatus,
        1,
        reason: 'the late collection response must not roll back the edit',
      );
      expect(
        controller.state.isLoadingCollections,
        isFalse,
        reason: 'the remaining collection-type load should finish normally',
      );
    },
  );

  test('CONTROL: same delayed book load merges fine without an edit', () async {
    final api = _DelayedBookApi();
    final controller = buildController(
      store: _MemoryTokenStore(config: config),
      oauth: _TransientFailingOAuth(),
      api: api,
    );
    addTearDown(controller.dispose);

    await _waitFor(() => controller.state.phase == SessionPhase.signedIn);
    await _waitFor(() => api.bookRequested);

    api.pendingBookLoad!.complete([
      UserCollection(
        subjectId: 200,
        type: CollectionType.doing,
        rate: 0,
        episodeStatus: 0,
        updatedAt: null,
        subject: _bookSubject,
      ),
    ]);
    // Give the background loop ample time to merge book and finish
    // music/game/real before drawing conclusions.
    await pump(300);

    expect(
      controller.state.collections.any((item) => item.subjectId == 200),
      isTrue,
      reason: 'without an edit the background load completes normally',
    );
  });

  test(
    'refresh retains optimistic episode progress while the mutation is pending',
    () async {
      final api = _OfflineReplayApiForBug2();
      final controller = buildController(
        store: _MemoryTokenStore(config: config),
        oauth: _TransientFailingOAuth(),
        api: api,
      );
      addTearDown(controller.dispose);

      await _waitFor(() => controller.state.phase == SessionPhase.signedIn);
      await _waitFor(() => !controller.state.isLoadingCollections);
      expect(controller.state.collectionFor(99)!.episodeStatus, 0);

      // Optimistic local progress: next episode marked watched. Replay fails
      // as retryable, so the episode mutation stays in the pending queue.
      final editError = await controller.setEpisode(
        subjectId: 99,
        episodeId: 11,
        type: 2,
        previousType: 0,
        trackGlobalBusy: false,
      );
      expect(editError, isNull);
      expect(controller.state.collectionFor(99)!.episodeStatus, 1);

      // A refresh lands while the mutation is still pending offline.
      await controller.refresh();

      expect(
        controller.state.collectionFor(99)!.episodeStatus,
        1,
        reason: 'pending local edit must survive a refresh (offline-first)',
      );
    },
  );
}

const _bookSubject = Subject(
  id: 200,
  name: 'book',
  nameCn: '书',
  imageUrl: '',
  summary: '',
  episodeCount: 0,
  score: 0,
  rank: 0,
  date: '',
);

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('Timed out waiting for asynchronous session state');
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

  @override
  Future<void> writeNetworkRoute(BangumiNetworkRoute route) async {}

  @override
  Future<void> writeTokens(OAuthTokenBundle tokens) async {
    accessToken = tokens.accessToken;
    refreshToken = tokens.refreshToken;
    expiresAt = tokens.expiresAt;
  }

  @override
  Future<void> clear() async {
    accessToken = null;
    refreshToken = null;
    expiresAt = null;
  }
}

class _TransientFailingOAuth extends BangumiOAuth {
  @override
  Future<OAuthTokenBundle> refresh(
    OAuthConfig config,
    String refreshToken,
  ) async {
    throw const BangumiOAuthException('网络暂时不可用');
  }
}

class _DelayedBookApi extends BangumiApi {
  Completer<List<UserCollection>>? pendingBookLoad;
  bool bookRequested = false;
  final List<Map<String, dynamic>> replayed = [];

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
  }) {
    if (subjectType == SubjectType.anime) {
      return Future.value(const [_animeCollection]);
    }
    if (subjectType == SubjectType.book) {
      bookRequested = true;
      return (pendingBookLoad ??= Completer<List<UserCollection>>()).future;
    }
    return Future.value(const []);
  }

  @override
  Future<void> replayPendingMutation(
    BangumiMutationKind kind,
    Map<String, dynamic> payload,
  ) async {
    replayed.add(Map<String, dynamic>.from(payload));
  }
}

class _OfflineReplayApiForBug2 extends BangumiApi {
  final List<Map<String, dynamic>> replayAttempts = [];

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
  }) async =>
      subjectType == SubjectType.anime ? const [_animeCollection] : const [];

  @override
  Future<void> replayPendingMutation(
    BangumiMutationKind kind,
    Map<String, dynamic> payload,
  ) async {
    replayAttempts.add(Map<String, dynamic>.from(payload));
    throw const BangumiApiException('没有网络', retryable: true);
  }
}

const _animeSubject = Subject(
  id: 99,
  name: 'anime',
  nameCn: '动画',
  imageUrl: '',
  summary: '',
  episodeCount: 12,
  score: 0,
  rank: 0,
  date: '',
);

const _animeCollection = UserCollection(
  subjectId: 99,
  type: CollectionType.doing,
  rate: 0,
  episodeStatus: 0,
  updatedAt: null,
  subject: _animeSubject,
);

class _MemorySnapshotCache extends SnapshotCache {
  final Map<String, List<UserCollection>> collections = {};
  final Map<int, List<UserEpisodeCollection>> episodeCollections = {};

  @override
  Future<BangumiUser?> readLastUser() async => null;

  @override
  Future<void> writeLastUser(BangumiUser user) async {}

  @override
  Future<void> clearLastUser() async {}

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
  Future<void> retryBlocked(String username) async {}
}
