import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/bangumi_oauth.dart';
import '../core/network/bangumi_api.dart';
import '../core/network/bangumi_endpoints.dart';
import '../core/network/bangumi_support.dart';
import '../core/network/community_service.dart';
import '../core/auth/website_cookie_bridge.dart';
import '../core/auth/website_session.dart';
import '../core/storage/snapshot_cache.dart';
import '../core/storage/token_store.dart';
import '../models/bangumi_models.dart';
import 'website_session_controller.dart';

final bangumiApiProvider = Provider<BangumiApi>((ref) => BangumiApi());
final bangumiOAuthProvider = Provider<BangumiOAuth>((ref) => BangumiOAuth());
final tokenStoreProvider = Provider<TokenStore>((ref) => TokenStore());

enum SessionPhase { booting, signedOut, signedIn }

class SessionState {
  const SessionState({
    this.phase = SessionPhase.booting,
    this.user,
    this.collections = const [],
    this.isRefreshing = false,
    this.isLoadingCollections = false,
    this.updatingSubjects = const {},
    this.networkRoute = BangumiNetworkRoute.official,
    this.message,
  });

  final SessionPhase phase;
  final BangumiUser? user;
  final List<UserCollection> collections;
  final bool isRefreshing;

  /// True while remaining subject types are still loading in the background.
  final bool isLoadingCollections;
  final Set<int> updatingSubjects;
  final BangumiNetworkRoute networkRoute;
  final String? message;

  UserCollection? collectionFor(int subjectId) {
    for (final collection in collections) {
      if (collection.subjectId == subjectId) return collection;
    }
    return null;
  }

  SessionState copyWith({
    SessionPhase? phase,
    BangumiUser? user,
    List<UserCollection>? collections,
    bool? isRefreshing,
    bool? isLoadingCollections,
    Set<int>? updatingSubjects,
    BangumiNetworkRoute? networkRoute,
    String? message,
    bool clearMessage = false,
    bool clearUser = false,
  }) => SessionState(
    phase: phase ?? this.phase,
    user: clearUser ? null : user ?? this.user,
    collections: collections ?? this.collections,
    isRefreshing: isRefreshing ?? this.isRefreshing,
    isLoadingCollections: isLoadingCollections ?? this.isLoadingCollections,
    updatingSubjects: updatingSubjects ?? this.updatingSubjects,
    networkRoute: networkRoute ?? this.networkRoute,
    message: clearMessage ? null : message ?? this.message,
  );
}

class SessionController extends StateNotifier<SessionState> {
  SessionController(
    this._api,
    this._oauth,
    this._tokenStore, {
    SnapshotCache? snapshotCache,
    WebsiteSessionStore? websiteSessionStore,
    this.onWebsiteSessionCleared,
  }) : _snapshotCache = snapshotCache ?? SnapshotCache.shared,
       _websiteSessionStore = websiteSessionStore ?? WebsiteSessionStore(),
       super(const SessionState()) {
    _api.ensureFreshToken = _ensureFreshToken;
    _api.onUnauthorizedRefresh = tryRefreshAccessToken;
    CommunityService.shared.onUnauthorizedRefresh = tryRefreshAccessToken;
    unawaited(_bootstrap());
  }

  final BangumiApi _api;
  final BangumiOAuth _oauth;
  final TokenStore _tokenStore;
  final SnapshotCache _snapshotCache;
  final WebsiteSessionStore _websiteSessionStore;

  /// Optional UI hook so Riverpod website-session state stays in sync.
  final void Function()? onWebsiteSessionCleared;
  BangumiNetworkRoute _networkRoute = BangumiNetworkRoute.official;
  Future<bool>? _refreshInFlight;
  Future<void>? _collectionsInFlight;

  /// In-memory OAuth cache so each API call does not hit secure storage.
  String? _cachedRefreshToken;
  DateTime? _cachedExpiresAt;
  OAuthConfig? _cachedOAuthConfig;
  int _collectionsGeneration = 0;

  Future<void> _bootstrap() async {
    // Parallel secure-storage reads: sequential waits were a cold-start tax.
    final bootstrap = await Future.wait([
      _tokenStore.readNetworkRoute(),
      _tokenStore.read(),
      _tokenStore.readRefreshToken(),
      _tokenStore.readExpiresAt(),
      _tokenStore.readOAuthConfig(),
    ]);
    _networkRoute = bootstrap[0]! as BangumiNetworkRoute;
    var token = bootstrap[1] as String?;
    final refreshToken = bootstrap[2] as String?;
    final expiresAt = bootstrap[3] as DateTime?;
    final config = bootstrap[4] as OAuthConfig?;
    _api.setNetworkRoute(_networkRoute);
    BangumiEndpoints.setRoute(_networkRoute);
    state = state.copyWith(networkRoute: _networkRoute);
    _cachedRefreshToken = refreshToken;
    _cachedExpiresAt = expiresAt;
    _cachedOAuthConfig = config;

    final shouldRefresh =
        refreshToken != null &&
        refreshToken.isNotEmpty &&
        config != null &&
        (token == null ||
            expiresAt == null ||
            expiresAt.isBefore(DateTime.now().add(const Duration(minutes: 5))));
    if (shouldRefresh) {
      try {
        final tokens = await _oauth.refresh(config, refreshToken);
        await _persistTokens(tokens);
        token = tokens.accessToken;
      } catch (error) {
        if (_invalidatesSession(error)) {
          await _forceSignOut(message: '登录已过期，请重新授权：${_messageFor(error)}');
          return;
        }
        if (token == null || token.trim().isEmpty) {
          state = SessionState(
            phase: SessionPhase.signedOut,
            networkRoute: _networkRoute,
            message: '暂时无法刷新登录状态：${_messageFor(error)}',
          );
          return;
        }
      }
    }
    if (token == null || token.trim().isEmpty) {
      await _forceSignOut();
      return;
    }
    final restored = await _restoreSignedInSnapshot(token);
    await _authenticate(token, persist: false, alreadyRestored: restored);
  }

  /// Paint last user + collections before `/me`. Returns true when HomeShell
  /// can open immediately; `/me` still runs in [_authenticate].
  Future<bool> _restoreSignedInSnapshot(String token) async {
    final lastUser = await _snapshotCache.readLastUser();
    if (lastUser == null) return false;
    final cached = await _snapshotCache.readCollections(lastUser.username);
    if (cached == null || cached.isEmpty) return false;
    _api.setAccessToken(token);
    CommunityService.shared.setAccessToken(token);
    CommunityService.shared.setCurrentUsername(
      lastUser.username,
      nickname: lastUser.nickname,
      avatarUrl: lastUser.avatarUrl,
    );
    state = SessionState(
      phase: SessionPhase.signedIn,
      user: lastUser,
      collections: cached,
      networkRoute: _networkRoute,
      isLoadingCollections: true,
      isRefreshing: false,
    );
    return true;
  }

  Future<bool> signIn(String rawToken) async {
    final token = rawToken.trim().replaceFirst(
      RegExp(r'^Bearer\s+', caseSensitive: false),
      '',
    );
    if (token.isEmpty) {
      state = state.copyWith(message: '请粘贴 Access Token');
      return false;
    }
    return _authenticate(token, persist: true);
  }

  Future<bool> signInWithOAuth(
    OAuthConfig config, {
    OAuthAuthorizationLauncher? launchAuthorization,
  }) async {
    // Stay signedOut while authorizing so AuthScreen (and the Windows WebView
    // dialog that needs its navigator) remains mounted. Booting starts only
    // after tokens exist, inside _authenticate.
    state = state.copyWith(isRefreshing: true, clearMessage: true);
    try {
      await _tokenStore.writeOAuthConfig(config);
      _cachedOAuthConfig = config;
      final tokens = await _oauth.authorize(
        config,
        launchAuthorization: launchAuthorization,
      );
      await _persistTokens(tokens);
      return _authenticate(tokens.accessToken, persist: false);
    } catch (error) {
      state = SessionState(
        phase: SessionPhase.signedOut,
        networkRoute: _networkRoute,
        message: error is BangumiOAuthException && error.isCancelled
            ? null
            : _messageFor(error),
      );
      return false;
    }
  }

  /// Abort an in-flight OAuth authorize (local callback wait / browser flow).
  Future<void> cancelOAuthAuthorization() => _oauth.cancelAuthorization();

  Future<bool> _authenticate(
    String token, {
    required bool persist,
    bool alreadyRestored = false,
  }) async {
    if (!alreadyRestored) {
      state = state.copyWith(
        phase: SessionPhase.booting,
        isRefreshing: true,
        isLoadingCollections: true,
        clearMessage: true,
      );
    }
    _api.setAccessToken(token);
    CommunityService.shared.setAccessToken(token);
    try {
      final user = await _api.getMe();
      CommunityService.shared.setCurrentUsername(
        user.username,
        nickname: user.nickname,
        avatarUrl: user.avatarUrl,
      );
      if (persist) {
        await _tokenStore.write(token);
        _cachedRefreshToken = null;
        _cachedExpiresAt = null;
      }
      await _snapshotCache.writeLastUser(user);
      final switchedAccount =
          alreadyRestored && state.user?.username != user.username;
      final cached = switchedAccount || !alreadyRestored
          ? await _snapshotCache.readCollections(user.username)
          : state.collections;
      final hasCache = cached != null && cached.isNotEmpty;
      state = SessionState(
        phase: SessionPhase.signedIn,
        user: user,
        collections: cached ?? const [],
        networkRoute: _networkRoute,
        isLoadingCollections: true,
        isRefreshing: !hasCache,
      );
      unawaited(_loadCollectionsAfterSignIn(user.username));
      return true;
    } catch (error) {
      if (alreadyRestored && !_invalidatesSession(error)) {
        state = state.copyWith(
          isRefreshing: false,
          message: '收藏同步失败，已显示本地缓存：${_messageFor(error)}',
        );
        return true;
      }
      if (!persist && _invalidatesSession(error)) {
        await _forceSignOut(message: _messageFor(error));
      } else {
        _api.setAccessToken(null);
        CommunityService.shared.setAccessToken(null);
        CommunityService.shared.setCurrentUsername(null);
        state = SessionState(
          phase: SessionPhase.signedOut,
          networkRoute: _networkRoute,
          message: _messageFor(error),
        );
      }
      return false;
    }
  }

  Future<void> _loadCollectionsAfterSignIn(String username) async {
    final generation = ++_collectionsGeneration;
    try {
      final anime = await _api.getUserCollections(
        username,
        subjectType: SubjectType.anime,
      );
      if (generation != _collectionsGeneration ||
          state.phase != SessionPhase.signedIn ||
          state.user?.username != username) {
        return;
      }
      // Replace only anime bucket; keep other types from snapshot until refreshed.
      final merged = _replaceType(state.collections, SubjectType.anime, anime);
      _sortCollections(merged);
      state = state.copyWith(
        collections: merged,
        isRefreshing: false,
        isLoadingCollections: true,
      );
      unawaited(_snapshotCache.writeCollections(username, merged));
      await _loadRemainingCollections(username);
    } catch (error) {
      if (generation != _collectionsGeneration) return;
      final keepStale = state.collections.isNotEmpty;
      state = state.copyWith(
        isRefreshing: false,
        isLoadingCollections: false,
        message: keepStale
            ? '收藏同步失败，已显示本地缓存：${_messageFor(error)}'
            : '收藏同步失败：${_messageFor(error)}',
      );
    }
  }

  Future<void> _loadRemainingCollections(String username) {
    final generation = ++_collectionsGeneration;
    final future = _fetchAndMergeOtherTypes(username, generation);
    _collectionsInFlight = future;
    return future.whenComplete(() {
      if (identical(_collectionsInFlight, future)) {
        _collectionsInFlight = null;
      }
    });
  }

  Future<void> _fetchAndMergeOtherTypes(String username, int generation) async {
    try {
      // Load other types one-by-one so the UI stays responsive and the
      // network stack is not flooded after login.
      final otherTypes = SubjectType.values
          .where((type) => type != SubjectType.anime)
          .toList();
      var merged = List<UserCollection>.from(state.collections);
      for (final type in otherTypes) {
        if (generation != _collectionsGeneration ||
            state.phase != SessionPhase.signedIn ||
            state.user?.username != username) {
          return;
        }
        final page = await _api.getUserCollections(username, subjectType: type);
        // The loop-head guard can be invalidated while this request is in
        // flight (e.g. sign-out). Re-check before merging so a late response
        // never repopulates a session that was reset meanwhile.
        if (generation != _collectionsGeneration ||
            state.phase != SessionPhase.signedIn ||
            state.user?.username != username) {
          return;
        }
        merged = _replaceType(merged, type, page);
        _sortCollections(merged);
        // Incremental UI update keeps library usable while sync continues.
        state = state.copyWith(
          collections: merged,
          isLoadingCollections: true,
          isRefreshing: false,
        );
        unawaited(_snapshotCache.writeCollections(username, merged));
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }
      if (generation != _collectionsGeneration) return;
      state = state.copyWith(
        collections: merged,
        isLoadingCollections: false,
        isRefreshing: false,
      );
      unawaited(_snapshotCache.writeCollections(username, merged));
    } catch (error) {
      if (generation != _collectionsGeneration) return;
      state = state.copyWith(
        isLoadingCollections: false,
        isRefreshing: false,
        message: state.collections.isNotEmpty
            ? '部分收藏同步失败，已保留本地数据：${_messageFor(error)}'
            : '部分收藏同步失败：${_messageFor(error)}',
      );
    }
  }

  List<UserCollection> _replaceType(
    List<UserCollection> current,
    SubjectType type,
    List<UserCollection> page,
  ) => [...current.where((item) => item.subject.type != type), ...page];

  Future<List<UserCollection>> _loadAllCollections(String username) async {
    final pages = await Future.wait([
      for (final type in SubjectType.values)
        _api.getUserCollections(username, subjectType: type),
    ]);
    final merged = [for (final page in pages) ...page];
    _sortCollections(merged);
    return merged;
  }

  void _sortCollections(List<UserCollection> items) {
    items.sort((a, b) {
      final aTime = a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime);
    });
  }

  Future<void> _persistTokens(OAuthTokenBundle tokens) async {
    await _tokenStore.writeTokens(tokens);
    _cachedRefreshToken = tokens.refreshToken.isNotEmpty
        ? tokens.refreshToken
        : _cachedRefreshToken;
    _cachedExpiresAt = tokens.expiresAt;
    _api.setAccessToken(tokens.accessToken);
    CommunityService.shared.setAccessToken(tokens.accessToken);
  }

  /// Proactively refresh OAuth access tokens that are near expiry.
  Future<void> _ensureFreshToken() async {
    final refreshToken = _cachedRefreshToken;
    if (refreshToken == null || refreshToken.isEmpty) return;
    final expiresAt = _cachedExpiresAt;
    if (expiresAt != null &&
        expiresAt.isAfter(DateTime.now().add(const Duration(minutes: 5)))) {
      return;
    }
    await tryRefreshAccessToken();
  }

  /// Single-flight OAuth refresh used for proactive and 401 recovery paths.
  Future<bool> tryRefreshAccessToken() {
    final inFlight = _refreshInFlight;
    if (inFlight != null) return inFlight;
    final future = _refreshAccessToken();
    _refreshInFlight = future;
    return future.whenComplete(() {
      if (identical(_refreshInFlight, future)) {
        _refreshInFlight = null;
      }
    });
  }

  Future<bool> _refreshAccessToken() async {
    final refreshToken =
        _cachedRefreshToken ?? await _tokenStore.readRefreshToken();
    final config = _cachedOAuthConfig ?? await _tokenStore.readOAuthConfig();
    if (refreshToken == null || refreshToken.isEmpty || config == null) {
      return false;
    }
    _cachedRefreshToken = refreshToken;
    _cachedOAuthConfig = config;
    try {
      final tokens = await _oauth.refresh(config, refreshToken);
      await _persistTokens(tokens);
      return true;
    } catch (error) {
      if (_invalidatesSession(error)) {
        await _forceSignOut(message: '登录已过期，请重新授权：${_messageFor(error)}');
      } else if (state.phase == SessionPhase.signedIn) {
        state = state.copyWith(message: '暂时无法刷新登录状态：${_messageFor(error)}');
      }
      return false;
    }
  }

  Future<void> refresh({bool showIndicator = true}) async {
    final user = state.user;
    if (user == null) return;
    final username = user.username;
    final generation = ++_collectionsGeneration;
    if (showIndicator) {
      state = state.copyWith(
        isRefreshing: true,
        isLoadingCollections: true,
        clearMessage: true,
      );
    }
    try {
      // Keep the shell responsive: refresh anime first, others in background.
      final anime = await _api.getUserCollections(
        username,
        subjectType: SubjectType.anime,
      );
      if (generation != _collectionsGeneration ||
          state.phase != SessionPhase.signedIn ||
          state.user?.username != username) {
        return;
      }
      final merged = _replaceType(state.collections, SubjectType.anime, anime);
      _sortCollections(merged);
      state = state.copyWith(
        collections: merged,
        isRefreshing: false,
        isLoadingCollections: true,
        clearMessage: true,
      );
      unawaited(_snapshotCache.writeCollections(username, merged));
      await _loadRemainingCollections(username);
    } catch (error) {
      if (generation != _collectionsGeneration ||
          state.phase != SessionPhase.signedIn ||
          state.user?.username != username) {
        return;
      }
      state = state.copyWith(
        isRefreshing: false,
        isLoadingCollections: false,
        message: state.collections.isNotEmpty
            ? '刷新失败，已保留本地数据：${_messageFor(error)}'
            : _messageFor(error),
      );
    }
  }

  Future<String?> setNetworkRoute(BangumiNetworkRoute route) async {
    if (route == _networkRoute) return null;
    _networkRoute = route;
    _api.setNetworkRoute(route);
    BangumiEndpoints.setRoute(route);
    _collectionsGeneration++;
    // Persist best-effort: the in-memory route stays active for this session
    // even when secure storage fails. Swallowing the error keeps the
    // busy-flag handover below running — an exception here would strand an
    // in-flight refresh whose generation guard exits without resetting the
    // spinners.
    String? persistError;
    try {
      await _tokenStore.writeNetworkRoute(route);
    } catch (error) {
      persistError = '线路设置未能保存到本机，重启后可能恢复原线路：${_messageFor(error)}';
    }
    final user = state.user;
    state = state.copyWith(
      networkRoute: route,
      // Keep busy flags untouched while signed out: an OAuth authorization
      // may still be waiting in an in-app browser and a route switch must
      // not hide its spinner/cancel UI. Signed-in reloads set their own.
      isRefreshing: user == null ? null : true,
      isLoadingCollections: user == null ? null : true,
      clearMessage: true,
    );
    if (user == null) return persistError;
    final username = user.username;
    final generation = ++_collectionsGeneration;
    try {
      final collections = await _loadAllCollections(username);
      if (generation != _collectionsGeneration ||
          state.phase != SessionPhase.signedIn ||
          state.user?.username != username) {
        return null;
      }
      state = state.copyWith(
        collections: collections,
        isRefreshing: false,
        isLoadingCollections: false,
        clearMessage: true,
      );
      return persistError;
    } catch (error) {
      if (generation != _collectionsGeneration ||
          state.phase != SessionPhase.signedIn ||
          state.user?.username != username) {
        return null;
      }
      final message = _messageFor(error);
      state = state.copyWith(
        isRefreshing: false,
        isLoadingCollections: false,
        message: message,
      );
      final syncFailure = '线路已切换，但同步失败：$message';
      return persistError == null ? syncFailure : '$syncFailure；$persistError';
    }
  }

  Future<String?> markNextEpisode(UserCollection collection) async {
    if (state.updatingSubjects.contains(collection.subjectId)) return null;
    _setUpdating(collection.subjectId, true);
    try {
      // Default episodeType=0: only 本篇 for progress tooling.
      final episodes = await _api.getEpisodeCollections(collection.subjectId);
      final target = BangumiSupport.nextUnwatchedMain(episodes);
      if (target == null) return '已经没有下一集了';
      await _api.updateEpisode(target.episode.id, type: 2);
      final watchedCount = BangumiSupport.watchedMainCountAfterMark(
        episodes,
        target.episode.id,
      );
      _replaceCollection(collection.copyWith(episodeStatus: watchedCount));
      return null;
    } catch (error) {
      return _messageFor(error);
    } finally {
      _setUpdating(collection.subjectId, false);
    }
  }

  Future<String?> setEpisode({
    required int subjectId,
    required int episodeId,
    required int type,
    bool refreshCollection = true,
    bool trackGlobalBusy = true,
  }) async {
    if (trackGlobalBusy) {
      _setUpdating(subjectId, true);
    }
    try {
      await _api.updateEpisode(episodeId, type: type);
      if (refreshCollection) {
        await refresh(showIndicator: false);
      }
      return null;
    } catch (error) {
      return _messageFor(error);
    } finally {
      if (trackGlobalBusy) {
        _setUpdating(subjectId, false);
      }
    }
  }

  Future<String?> changeCollection(
    Subject subject,
    CollectionType type, {
    bool completeEpisodesWhenDone = true,
    int? rate,
    String? comment,
    List<String>? tags,
    bool? private,
    int? episodeStatus,
    int? volumeStatus,
  }) async {
    _setUpdating(subject.id, true);
    try {
      final old = state.collectionFor(subject.id);
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
      await _api.updateCollection(
        subject.id,
        type,
        rate: nextRate,
        comment: nextComment,
        tags: nextTags,
        private: nextPrivate,
        episodeStatus: subject.type.hasVolumes ? nextEpisodeStatus : null,
        volumeStatus: subject.type.hasVolumes ? nextVolumeStatus : null,
      );
      var resolvedEpisodeStatus = nextEpisodeStatus;
      // Garage #461: marking as "done" auto-completes regular episode progress.
      if (completeEpisodesWhenDone &&
          type == CollectionType.done &&
          subject.type.hasEpisodes) {
        try {
          // Default episodeType=0: only auto-complete 本篇, never SP/OP/ED.
          final episodes = await _api.getEpisodeCollections(subject.id);
          final unfinished = BangumiSupport.unfinishedMainEpisodeIds(episodes);
          if (unfinished.isNotEmpty) {
            await _api.updateEpisodesBatch(
              subject.id,
              episodeIds: unfinished,
              type: 2,
            );
          }
          resolvedEpisodeStatus = BangumiSupport.mainEpisodeCollections(
            episodes,
          ).length;
        } catch (_) {
          // Collection type is already updated; progress fill is best-effort.
        }
      }
      if (old != null) {
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
      } else {
        state = state.copyWith(
          collections: [
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
            ...state.collections,
          ],
        );
      }
      return null;
    } catch (error) {
      return _messageFor(error);
    } finally {
      _setUpdating(subject.id, false);
    }
  }

  Future<void> signOut() => _forceSignOut();

  Future<void> _forceSignOut({String? message}) async {
    _collectionsGeneration++;
    _cachedRefreshToken = null;
    _cachedExpiresAt = null;
    _cachedOAuthConfig = null;
    await _tokenStore.clear();
    // Website cookie session is independent of OAuth, but clearing on sign-out
    // avoids leaving another account's web session on the device.
    try {
      await _websiteSessionStore.clear();
      await WebsiteCookieBridge.clearBgmCookies();
    } catch (_) {
      // Secure storage / platform jars may be unavailable in pure unit tests.
    }
    try {
      onWebsiteSessionCleared?.call();
    } catch (_) {}
    _api.setAccessToken(null);
    CommunityService.shared.setAccessToken(null);
    CommunityService.shared.setCurrentUsername(null);
    await _snapshotCache.clearLastUser();
    await CommunityService.shared.clearAccountCache();
    state = SessionState(
      phase: SessionPhase.signedOut,
      networkRoute: _networkRoute,
      message: message,
    );
  }

  void clearMessage() => state = state.copyWith(clearMessage: true);

  void _replaceCollection(UserCollection updated) {
    state = state.copyWith(
      collections: [
        for (final item in state.collections)
          if (item.subjectId == updated.subjectId) updated else item,
      ],
    );
  }

  void _setUpdating(int subjectId, bool updating) {
    final subjects = {...state.updatingSubjects};
    updating ? subjects.add(subjectId) : subjects.remove(subjectId);
    state = state.copyWith(updatingSubjects: subjects);
  }

  String _messageFor(Object error) => error is BangumiApiException
      ? error.message
      : error is BangumiOAuthException
      ? error.message
      : '发生了意外错误，请稍后重试';

  bool _invalidatesSession(Object error) =>
      (error is BangumiOAuthException && error.invalidatesSession) ||
      (error is BangumiApiException &&
          error.statusCode == 401 &&
          (_cachedRefreshToken == null || _cachedRefreshToken!.isEmpty));
}

final sessionProvider = StateNotifierProvider<SessionController, SessionState>((
  ref,
) {
  return SessionController(
    ref.watch(bangumiApiProvider),
    ref.watch(bangumiOAuthProvider),
    ref.watch(tokenStoreProvider),
    onWebsiteSessionCleared: () {
      // Keep in-memory website session UI state aligned with storage wipe.
      ref.read(websiteSessionProvider.notifier).markCleared();
    },
  );
});
