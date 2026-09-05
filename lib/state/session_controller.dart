import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/bangumi_oauth.dart';
import '../core/network/bangumi_api.dart';
import '../core/network/bangumi_endpoints.dart';
import '../core/network/bangumi_support.dart';
import '../core/network/community_service.dart';
import '../core/auth/website_cookie_bridge.dart';
import '../core/auth/website_session.dart';
import '../core/storage/bangumi_sync_store.dart';
import '../core/storage/snapshot_cache.dart';
import '../core/storage/token_store.dart';
import '../models/bangumi_models.dart';
import 'website_session_controller.dart';

final bangumiApiProvider = Provider<BangumiApi>((ref) => BangumiApi());
final bangumiOAuthProvider = Provider<BangumiOAuth>((ref) => BangumiOAuth());
final tokenStoreProvider = Provider<TokenStore>((ref) => TokenStore());
final snapshotCacheProvider = Provider<SnapshotCache>(
  (ref) => SnapshotCache.shared,
);

enum SessionPhase { booting, signedOut, signedIn }

/// Login work is independent of collection refreshes and background uploads.
enum AuthActivity { idle, authorizing, verifying, signingOut }

class SessionState {
  const SessionState({
    this.phase = SessionPhase.booting,
    this.authActivity = AuthActivity.idle,
    this.canRetrySignIn = false,
    this.canRetrySignOut = false,
    this.isPreparingHome = false,
    this.user,
    this.collections = const [],
    this.isRefreshing = false,
    this.isLoadingCollections = false,
    this.updatingSubjects = const {},
    this.networkRoute = BangumiNetworkRoute.official,
    this.pendingSyncCount = 0,
    this.blockedSyncCount = 0,
    this.isSyncing = false,
    this.message,
  });

  final SessionPhase phase;
  final AuthActivity authActivity;
  final bool canRetrySignIn;
  final bool canRetrySignOut;
  final bool isPreparingHome;
  bool get isAuthenticating =>
      authActivity == AuthActivity.authorizing ||
      authActivity == AuthActivity.verifying;
  final BangumiUser? user;
  final List<UserCollection> collections;
  final bool isRefreshing;

  /// True while remaining subject types are still loading in the background.
  final bool isLoadingCollections;
  final Set<int> updatingSubjects;
  final BangumiNetworkRoute networkRoute;
  final int pendingSyncCount;
  final int blockedSyncCount;
  final bool isSyncing;
  final String? message;

  UserCollection? collectionFor(int subjectId) {
    for (final collection in collections) {
      if (collection.subjectId == subjectId) return collection;
    }
    return null;
  }

  SessionState copyWith({
    SessionPhase? phase,
    AuthActivity? authActivity,
    bool? canRetrySignIn,
    bool? canRetrySignOut,
    bool? isPreparingHome,
    BangumiUser? user,
    List<UserCollection>? collections,
    bool? isRefreshing,
    bool? isLoadingCollections,
    Set<int>? updatingSubjects,
    BangumiNetworkRoute? networkRoute,
    int? pendingSyncCount,
    int? blockedSyncCount,
    bool? isSyncing,
    String? message,
    bool clearMessage = false,
    bool clearUser = false,
  }) => SessionState(
    phase: phase ?? this.phase,
    authActivity: authActivity ?? this.authActivity,
    canRetrySignIn: canRetrySignIn ?? this.canRetrySignIn,
    canRetrySignOut: canRetrySignOut ?? this.canRetrySignOut,
    isPreparingHome: isPreparingHome ?? this.isPreparingHome,
    user: clearUser ? null : user ?? this.user,
    collections: collections ?? this.collections,
    isRefreshing: isRefreshing ?? this.isRefreshing,
    isLoadingCollections: isLoadingCollections ?? this.isLoadingCollections,
    updatingSubjects: updatingSubjects ?? this.updatingSubjects,
    networkRoute: networkRoute ?? this.networkRoute,
    pendingSyncCount: pendingSyncCount ?? this.pendingSyncCount,
    blockedSyncCount: blockedSyncCount ?? this.blockedSyncCount,
    isSyncing: isSyncing ?? this.isSyncing,
    message: clearMessage ? null : message ?? this.message,
  );
}

class SessionController extends StateNotifier<SessionState> {
  SessionController(
    this._api,
    this._oauth,
    this._tokenStore, {
    SnapshotCache? snapshotCache,
    BangumiSyncStore? syncStore,
    WebsiteSessionStore? websiteSessionStore,
    this.onWebsiteSessionCleared,
  }) : _snapshotCache = snapshotCache ?? SnapshotCache.shared,
       _syncStore = syncStore ?? BangumiSyncStore.shared,
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
  final BangumiSyncStore _syncStore;
  final WebsiteSessionStore _websiteSessionStore;

  /// Optional UI hook so Riverpod website-session state stays in sync.
  final void Function()? onWebsiteSessionCleared;
  BangumiNetworkRoute _networkRoute = BangumiNetworkRoute.official;
  Future<bool>? _refreshInFlight;
  int _authGeneration = 0;
  bool _hasStoredCredentials = false;
  Future<void> _authWrites = Future<void>.value();

  bool _isCurrentAuth(int generation) =>
      mounted && generation == _authGeneration;

  /// Serialize credential writes and logout cleanup. A write already running
  /// at logout must finish before deletion, never after it.
  Future<bool> _writeAuth(int generation, Future<void> Function() write) {
    final future = _authWrites.then((_) async {
      if (!_isCurrentAuth(generation)) return false;
      await write();
      return _isCurrentAuth(generation);
    });
    _authWrites = future.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return future;
  }

  /// In-memory OAuth cache so each API call does not hit secure storage.
  String? _cachedRefreshToken;
  DateTime? _cachedExpiresAt;
  OAuthConfig? _cachedOAuthConfig;
  int _collectionsGeneration = 0;
  int _localMutationRevision = 0;
  final Map<int, int> _subjectMutationRevisions = {};
  Future<void>? _syncInFlight;
  Timer? _syncRetryTimer;
  Timer? _homePreparationTimer;
  var _syncRetryStep = 0;

  Future<void> _bootstrap() async {
    final generation = ++_authGeneration;
    state = SessionState(
      phase: SessionPhase.booting,
      networkRoute: _networkRoute,
    );
    try {
      final bootstrap = await Future.wait<Object?>([
        _tokenStore.readNetworkRoute(),
        _tokenStore.read(),
        _tokenStore.readRefreshToken(),
        _tokenStore.readExpiresAt(),
        _tokenStore.readOAuthConfig(),
      ]);
      if (!_isCurrentAuth(generation)) return;
      _networkRoute = bootstrap[0]! as BangumiNetworkRoute;
      var token = bootstrap[1] as String?;
      _cachedRefreshToken = bootstrap[2] as String?;
      _cachedExpiresAt = bootstrap[3] as DateTime?;
      _cachedOAuthConfig = bootstrap[4] as OAuthConfig?;
      _hasStoredCredentials =
          token?.isNotEmpty == true || _cachedRefreshToken?.isNotEmpty == true;
      _api.setNetworkRoute(_networkRoute);
      BangumiEndpoints.setRoute(_networkRoute);
      state = state.copyWith(networkRoute: _networkRoute);

      final refreshToken = _cachedRefreshToken;
      final config = _cachedOAuthConfig;
      final shouldRefresh =
          refreshToken != null &&
          refreshToken.isNotEmpty &&
          config != null &&
          config.isValid &&
          (token == null ||
              _cachedExpiresAt == null ||
              _cachedExpiresAt!.isBefore(
                DateTime.now().add(const Duration(minutes: 5)),
              ));
      if (shouldRefresh) {
        try {
          final tokens = await _oauth.refresh(config, refreshToken);
          if (!await _persistTokens(tokens, generation)) return;
          token = tokens.accessToken;
        } catch (error) {
          if (!_isCurrentAuth(generation)) return;
          if (_invalidatesSession(error)) {
            await _forceSignOut(message: '登录已过期，请重新授权：${_messageFor(error)}');
            return;
          }
          // A transient refresh failure does not delete a usable saved login.
          if (token == null || token.trim().isEmpty) rethrow;
        }
      }
      if (!_isCurrentAuth(generation)) return;
      if (token == null || token.trim().isEmpty) {
        _api.setAccessToken(null);
        CommunityService.shared.setAccessToken(null);
        CommunityService.shared.setCurrentUsername(null);
        state = SessionState(
          phase: SessionPhase.signedOut,
          networkRoute: _networkRoute,
        );
        return;
      }
      final restored = await _restoreSignedInSnapshot(token, generation);
      if (!_isCurrentAuth(generation)) return;
      await _authenticate(
        token,
        generation: generation,
        persist: false,
        alreadyRestored: restored,
      );
    } catch (error) {
      if (!_isCurrentAuth(generation)) return;
      _api.setAccessToken(null);
      CommunityService.shared.setAccessToken(null);
      state = SessionState(
        phase: SessionPhase.signedOut,
        networkRoute: _networkRoute,
        canRetrySignIn: true,
        message: '暂时无法恢复登录，可重试连接：${_messageFor(error)}',
      );
    }
  }

  /// Retry existing credentials without asking the user to authorize again.
  Future<void> retrySavedSignIn() async {
    if (state.phase != SessionPhase.signedOut ||
        state.authActivity != AuthActivity.idle) {
      return;
    }
    await _bootstrap();
  }

  Future<bool> _restoreSignedInSnapshot(String token, int generation) async {
    try {
      final lastUser = await _snapshotCache.readLastUser();
      if (lastUser == null || !_isCurrentAuth(generation)) return false;
      final snapshot = await _snapshotCache.readCollections(lastUser.username);
      final cached = await _overlayPendingCollections(
        lastUser.username,
        snapshot ?? const [],
      );
      if (!_isCurrentAuth(generation)) return false;
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
      );
      unawaited(_refreshPendingCount(lastUser.username));
      return true;
    } catch (_) {
      // A broken cache must not prevent validation of the saved token.
      return false;
    }
  }

  int _beginLogin(AuthActivity activity) {
    final generation = ++_authGeneration;
    _refreshInFlight = null;
    _cachedRefreshToken = null;
    _cachedExpiresAt = null;
    _cachedOAuthConfig = null;
    state = SessionState(
      phase: SessionPhase.signedOut,
      authActivity: activity,
      networkRoute: _networkRoute,
    );
    return generation;
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
    if (state.phase != SessionPhase.signedOut ||
        state.authActivity == AuthActivity.verifying ||
        state.authActivity == AuthActivity.signingOut) {
      return false;
    }
    if (state.authActivity == AuthActivity.authorizing) {
      await cancelOAuthAuthorization();
      if (!mounted || state.authActivity != AuthActivity.idle) return false;
    }
    final generation = _beginLogin(AuthActivity.verifying);
    return _authenticate(token, generation: generation, persist: true);
  }

  Future<bool> signInWithOAuth(
    OAuthConfig config, {
    OAuthAuthorizationLauncher? launchAuthorization,
  }) async {
    if (state.phase != SessionPhase.signedOut ||
        state.authActivity != AuthActivity.idle) {
      return false;
    }
    if (!config.isValid) {
      state = state.copyWith(message: 'OAuth 配置不完整');
      return false;
    }
    final generation = _beginLogin(AuthActivity.authorizing);
    try {
      final tokens = await _oauth.authorize(
        config,
        launchAuthorization: launchAuthorization,
      );
      if (!_isCurrentAuth(generation)) return false;
      // Validate identity before replacing saved credentials or configuration.
      return await _authenticate(
        tokens.accessToken,
        generation: generation,
        persist: true,
        tokens: tokens,
        config: config,
      );
    } catch (error) {
      if (!_isCurrentAuth(generation)) return false;
      state = SessionState(
        phase: SessionPhase.signedOut,
        networkRoute: _networkRoute,
        canRetrySignIn: _hasStoredCredentials,
        message: error is BangumiOAuthException && error.isCancelled
            ? null
            : _messageFor(error),
      );
      return false;
    }
  }

  Future<void> cancelOAuthAuthorization() async {
    if (state.authActivity != AuthActivity.authorizing) return;
    final generation = ++_authGeneration;
    String? message;
    // Keep new flows disabled until the old local callback port is released.
    try {
      await _oauth.cancelAuthorization();
    } catch (error) {
      message = '取消授权时清理失败，可重试登录：${_messageFor(error)}';
    } finally {
      if (_isCurrentAuth(generation)) {
        state = SessionState(
          phase: SessionPhase.signedOut,
          networkRoute: _networkRoute,
          canRetrySignIn: _hasStoredCredentials,
          message: message,
        );
      }
    }
  }

  Future<bool> _authenticate(
    String token, {
    required int generation,
    required bool persist,
    bool alreadyRestored = false,
    OAuthTokenBundle? tokens,
    OAuthConfig? config,
  }) async {
    if (!_isCurrentAuth(generation)) return false;
    if (persist) {
      // Keep AuthScreen mounted while checking /me so inline errors and the
      // token sheet remain attached to the same navigator.
      state = state.copyWith(
        authActivity: AuthActivity.verifying,
        clearMessage: true,
      );
    }
    _api.setAccessToken(token);
    CommunityService.shared.setAccessToken(token);
    try {
      final user = await _api.getMe();
      if (!_isCurrentAuth(generation)) return false;
      if (persist) {
        if (tokens != null) {
          if (!await _persistTokens(tokens, generation, config: config)) {
            return false;
          }
        } else {
          if (!await _writeAuth(generation, () => _tokenStore.write(token))) {
            return false;
          }
          _hasStoredCredentials = true;
        }
      }

      List<UserCollection>? snapshot;
      try {
        final previousUser = await _snapshotCache.readLastUser();
        if (!_isCurrentAuth(generation)) return false;
        if (previousUser != null && previousUser.username != user.username) {
          if (!await _writeAuth(generation, () async {
            await _websiteSessionStore.clear();
            onWebsiteSessionCleared?.call();
            await CommunityService.shared.clearAccountCache();
          })) {
            return false;
          }
          _subjectMutationRevisions.clear();
          _localMutationRevision = 0;
        }
        snapshot = alreadyRestored && state.user?.username == user.username
            ? state.collections
            : await _snapshotCache.readCollections(user.username);
        await _writeAuth(generation, () => _snapshotCache.writeLastUser(user));
      } catch (_) {
        // Authentication succeeded; optional list caches cannot turn it into
        // a failed login. Collections are fetched independently below.
      }
      final cached = await _overlayPendingCollections(
        user.username,
        snapshot ?? const [],
      );
      if (!_isCurrentAuth(generation)) return false;
      CommunityService.shared.setCurrentUsername(
        user.username,
        nickname: user.nickname,
        avatarUrl: user.avatarUrl,
      );
      state = SessionState(
        phase: SessionPhase.signedIn,
        user: user,
        collections: cached,
        networkRoute: _networkRoute,
        isLoadingCollections: true,
        isRefreshing: cached.isEmpty,
        isPreparingHome: !alreadyRestored && cached.isEmpty,
      );
      _homePreparationTimer?.cancel();
      if (state.isPreparingHome) {
        _homePreparationTimer = Timer(const Duration(seconds: 8), () {
          if (_isCurrentAuth(generation)) enterHomeNow();
        });
      }
      unawaited(_refreshPendingCount(user.username));
      unawaited(_loadInitialCollections(user.username));
      return true;
    } catch (error) {
      if (!_isCurrentAuth(generation)) return false;
      if (alreadyRestored && !_invalidatesSession(error)) {
        state = state.copyWith(
          isRefreshing: false,
          isLoadingCollections: false,
          message: '暂时无法连接 Bangumi，已保留登录和本地缓存：${_messageFor(error)}',
        );
        unawaited(_refreshPendingCount(state.user?.username));
        return true;
      }
      if (!persist && _invalidatesSession(error)) {
        await _forceSignOut(message: '登录已失效，请重新登录：${_messageFor(error)}');
      } else {
        _api.setAccessToken(null);
        CommunityService.shared.setAccessToken(null);
        CommunityService.shared.setCurrentUsername(null);
        state = SessionState(
          phase: SessionPhase.signedOut,
          networkRoute: _networkRoute,
          canRetrySignIn: _hasStoredCredentials,
          message: _messageFor(error),
        );
      }
      return false;
    }
  }

  Future<void> _loadCollectionsAfterSignIn(String username) async {
    final generation = ++_collectionsGeneration;
    final requestMutationRevision = _localMutationRevision;
    try {
      final anime = await _api.getUserCollections(
        username,
        subjectType: SubjectType.anime,
        onPage: (items) => _publishCollectionPage(
          username,
          generation,
          requestMutationRevision,
          items,
        ),
      );
      if (generation != _collectionsGeneration ||
          state.phase != SessionPhase.signedIn ||
          state.user?.username != username) {
        return;
      }
      // Replace only anime bucket; keep other types from snapshot until refreshed.
      var merged = _replaceType(state.collections, SubjectType.anime, anime);
      merged = await _overlayPendingCollections(username, merged);
      if (!mounted || generation != _collectionsGeneration) return;
      merged = _preserveCollectionsChangedAfter(
        merged,
        requestMutationRevision,
      );
      _sortCollections(merged);
      state = state.copyWith(
        collections: merged,
        isPreparingHome: false,
        isRefreshing: false,
        isLoadingCollections: true,
      );
      unawaited(_snapshotCache.writeCollections(username, merged));
      await _loadRemainingCollections(username);
    } catch (error) {
      if (generation != _collectionsGeneration) return;
      final keepStale = state.collections.isNotEmpty;
      state = state.copyWith(
        isPreparingHome: false,
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
    return _fetchAndMergeOtherTypes(username, generation);
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
        final requestMutationRevision = _localMutationRevision;
        final page = await _api.getUserCollections(
          username,
          subjectType: type,
          onPage: (items) => _publishCollectionPage(
            username,
            generation,
            requestMutationRevision,
            items,
          ),
        );
        // The loop-head guard can be invalidated while this request is in
        // flight (e.g. sign-out). Re-check before merging so a late response
        // never repopulates a session that was reset meanwhile.
        if (generation != _collectionsGeneration ||
            state.phase != SessionPhase.signedIn ||
            state.user?.username != username) {
          return;
        }
        merged = _replaceType(merged, type, page);
        merged = await _overlayPendingCollections(username, merged);
        if (!mounted || generation != _collectionsGeneration) return;
        merged = _preserveCollectionsChangedAfter(
          merged,
          requestMutationRevision,
        );
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

  Future<bool> _publishCollectionPage(
    String username,
    int generation,
    int requestMutationRevision,
    List<UserCollection> items,
  ) async {
    bool current() =>
        mounted &&
        generation == _collectionsGeneration &&
        state.phase == SessionPhase.signedIn &&
        state.user?.username == username;
    if (!current()) return false;
    if (items.isEmpty) return true;
    final byId = {
      for (final item in state.collections) item.subjectId: item,
      for (final item in items) item.subjectId: item,
    };
    var merged = await _overlayPendingCollections(
      username,
      byId.values.toList(),
    );
    if (!current()) return false;
    merged = _preserveCollectionsChangedAfter(merged, requestMutationRevision);
    _sortCollections(merged);
    state = state.copyWith(
      collections: merged,
      isPreparingHome: false,
      isRefreshing: false,
      isLoadingCollections: true,
    );
    return true;
  }

  List<UserCollection> _replaceType(
    List<UserCollection> current,
    SubjectType type,
    List<UserCollection> page,
  ) => [...current.where((item) => item.subject.type != type), ...page];

  /// A collection response may have started before a local edit and finish
  /// after the corresponding queue entry has already uploaded and been
  /// removed. Preserve the newer in-memory value for exactly those subjects;
  /// requests started after the edit remain server-authoritative.
  List<UserCollection> _preserveCollectionsChangedAfter(
    List<UserCollection> source,
    int requestMutationRevision,
  ) {
    final merged = List<UserCollection>.from(source);
    for (final entry in _subjectMutationRevisions.entries) {
      if (entry.value <= requestMutationRevision) continue;
      final local = state.collectionFor(entry.key);
      if (local == null) continue;
      final index = merged.indexWhere(
        (item) => item.subjectId == local.subjectId,
      );
      if (index < 0) {
        merged.add(local);
      } else {
        merged[index] = local;
      }
    }
    return merged;
  }

  Future<List<UserCollection>> _overlayPendingCollections(
    String username,
    List<UserCollection> source,
  ) async {
    final merged = List<UserCollection>.from(source);
    try {
      final pending = await _syncStore.pendingFor(
        username,
        includeBlocked: true,
      );
      for (final mutation in pending) {
        final payload = mutation.payload;
        final subjectId = (payload['subject_id'] as num?)?.toInt();
        if (subjectId == null || subjectId <= 0) continue;
        final index = merged.indexWhere((item) => item.subjectId == subjectId);
        final previous = index < 0 ? null : merged[index];
        final localEpisodeStatus = (payload['local_episode_status'] as num?)
            ?.toInt();
        if (mutation.kind != BangumiMutationKind.collection) {
          if (previous != null && localEpisodeStatus != null) {
            merged[index] = previous.copyWith(
              episodeStatus: localEpisodeStatus,
            );
          }
          continue;
        }
        Subject? subject = previous?.subject;
        final subjectJson = payload['subject'];
        if (subject == null && subjectJson is Map) {
          subject = Subject.fromJson(Map<String, dynamic>.from(subjectJson));
        }
        if (subject == null || subject.id <= 0) continue;
        final collection = UserCollection(
          subjectId: subjectId,
          type: CollectionType.fromValue(
            (payload['collection_type'] as num).toInt(),
          ),
          rate: (payload['rate'] as num?)?.toInt() ?? previous?.rate ?? 0,
          episodeStatus:
              localEpisodeStatus ??
              (payload['episode_status'] as num?)?.toInt() ??
              previous?.episodeStatus ??
              0,
          volumeStatus:
              (payload['volume_status'] as num?)?.toInt() ??
              previous?.volumeStatus ??
              0,
          updatedAt:
              DateTime.tryParse(
                payload['local_updated_at']?.toString() ?? '',
              ) ??
              mutation.updatedAt,
          subject: subject,
          comment: payload['comment']?.toString() ?? previous?.comment ?? '',
          tags: [
            for (final value
                in payload['tags'] as List? ?? previous?.tags ?? const [])
              value.toString(),
          ],
          private: payload['private'] == true,
        );
        if (index < 0) {
          merged.add(collection);
        } else {
          merged[index] = collection;
        }
      }
    } catch (_) {}
    _sortCollections(merged);
    return merged;
  }

  Future<void> _loadInitialCollections(String username) async {
    // Pending edits are overlaid on fetched data. Uploading the queue must
    // not block the first screen, particularly when a mutation is slow.
    unawaited(syncPendingChanges());
    await _loadCollectionsAfterSignIn(username);
  }

  /// Leave the bounded first-screen wait; collection loading continues.
  void enterHomeNow() {
    _homePreparationTimer?.cancel();
    _homePreparationTimer = null;
    if (!mounted || !state.isPreparingHome) return;
    state = state.copyWith(isPreparingHome: false);
  }

  Future<List<UserEpisodeCollection>> applyPendingEpisodeChanges(
    int subjectId,
    List<UserEpisodeCollection> source,
  ) async {
    final username = state.user?.username;
    if (username == null || username.isEmpty) return source;
    final merged = List<UserEpisodeCollection>.from(source);
    try {
      final pending = await _syncStore.pendingFor(
        username,
        includeBlocked: true,
      );
      for (final mutation in pending) {
        final payload = mutation.payload;
        if ((payload['subject_id'] as num?)?.toInt() != subjectId) continue;
        if (mutation.kind == BangumiMutationKind.episode) {
          final episodeId = (payload['episode_id'] as num).toInt();
          final type = (payload['type'] as num).toInt();
          final index = merged.indexWhere(
            (item) => item.episode.id == episodeId,
          );
          if (index >= 0) merged[index] = merged[index].copyWith(type: type);
        } else if (mutation.kind == BangumiMutationKind.episodesBatch) {
          final episodeIds = {
            for (final value in payload['episode_ids'] as List? ?? const [])
              (value as num).toInt(),
          };
          final type = (payload['type'] as num).toInt();
          for (var index = 0; index < merged.length; index++) {
            if (episodeIds.contains(merged[index].episode.id)) {
              merged[index] = merged[index].copyWith(type: type);
            }
          }
        } else if (mutation.kind == BangumiMutationKind.collection &&
            payload['complete_episodes'] == true) {
          for (var index = 0; index < merged.length; index++) {
            if (merged[index].episode.type == 0) {
              merged[index] = merged[index].copyWith(type: 2);
            }
          }
        }
      }
    } catch (_) {}
    return merged;
  }

  Future<List<UserCollection>> _loadAllCollections(String username) async {
    final requestMutationRevision = _localMutationRevision;
    final pages = await Future.wait([
      for (final type in SubjectType.values)
        _api.getUserCollections(username, subjectType: type),
    ]);
    final merged = [for (final page in pages) ...page];
    final overlaid = await _overlayPendingCollections(username, merged);
    return _preserveCollectionsChangedAfter(overlaid, requestMutationRevision);
  }

  void _sortCollections(List<UserCollection> items) {
    items.sort((a, b) {
      final aTime = a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime);
    });
  }

  Future<bool> _persistTokens(
    OAuthTokenBundle tokens,
    int generation, {
    OAuthConfig? config,
  }) async {
    if (!await _writeAuth(generation, () async {
      if (config != null) {
        await _tokenStore.writeOAuthSession(config, tokens);
      } else {
        await _tokenStore.writeTokens(tokens);
      }
    })) {
      return false;
    }
    _cachedOAuthConfig = config ?? _cachedOAuthConfig;
    _cachedRefreshToken = tokens.refreshToken.isEmpty
        ? null
        : tokens.refreshToken;
    _cachedExpiresAt = tokens.expiresAt;
    _hasStoredCredentials = true;
    _api.setAccessToken(tokens.accessToken);
    CommunityService.shared.setAccessToken(tokens.accessToken);
    return true;
  }

  Future<void> _ensureFreshToken() async {
    if (!mounted || state.isAuthenticating) return;
    final expiresAt = _cachedExpiresAt;
    if (expiresAt != null &&
        expiresAt.isAfter(DateTime.now().add(const Duration(minutes: 5)))) {
      return;
    }
    await tryRefreshAccessToken();
  }

  /// Only refresh the active credential generation. A late success or failure
  /// from an account that was signed out must never modify its replacement.
  Future<bool> tryRefreshAccessToken() {
    if (!mounted ||
        state.isAuthenticating ||
        state.authActivity == AuthActivity.signingOut ||
        _cachedRefreshToken?.isNotEmpty != true ||
        _cachedOAuthConfig == null) {
      return Future.value(false);
    }
    final active = _refreshInFlight;
    if (active != null) return active;
    final future = _refreshAccessToken(_authGeneration);
    _refreshInFlight = future;
    return future.whenComplete(() {
      if (identical(_refreshInFlight, future)) _refreshInFlight = null;
    });
  }

  Future<bool> _refreshAccessToken(int generation) async {
    final refreshToken = _cachedRefreshToken;
    final config = _cachedOAuthConfig;
    if (refreshToken == null || config == null) return false;
    try {
      final tokens = await _oauth.refresh(config, refreshToken);
      return await _persistTokens(tokens, generation);
    } catch (error) {
      if (!_isCurrentAuth(generation)) return false;
      if (_invalidatesSession(error)) {
        await _forceSignOut(message: '登录已过期，请重新授权：${_messageFor(error)}');
      } else if (state.phase == SessionPhase.signedIn) {
        state = state.copyWith(message: '暂时无法刷新登录状态：${_messageFor(error)}');
      }
      return false;
    }
  }

  Future<void> syncPendingChanges({bool retryBlocked = false}) {
    final active = _syncInFlight;
    if (active == null) return _startDrain(retryBlocked: retryBlocked);
    if (!retryBlocked) return active;
    // A manual retry must not be swallowed by a drain that is already
    // running: chain one more pass so blocked entries actually retry. The
    // chained future stays registered so concurrent callers join it instead
    // of starting a parallel drain.
    final future = () async {
      try {
        await active;
      } catch (_) {}
      await _startDrain(retryBlocked: true);
    }();
    _syncInFlight = future;
    return future;
  }

  Future<void> _startDrain({required bool retryBlocked}) {
    final future = _drainPendingChanges(retryBlocked: retryBlocked);
    _syncInFlight = future;
    return future.whenComplete(() {
      if (identical(_syncInFlight, future)) _syncInFlight = null;
    });
  }

  Future<void> _drainPendingChanges({required bool retryBlocked}) async {
    if (!mounted) return;
    final generation = _authGeneration;
    final username = state.user?.username;
    if (username == null || username.isEmpty) return;
    _syncRetryTimer?.cancel();
    _syncRetryTimer = null;
    if (retryBlocked) {
      try {
        await _syncStore.retryBlocked(username);
      } catch (_) {
        return;
      }
    }
    if (!_isCurrentAuth(generation) || state.user?.username != username) return;
    state = state.copyWith(isSyncing: true);
    var retryLater = false;
    var changedWhileSyncing = false;
    try {
      final pending = await _syncStore.pendingFor(username);
      for (final mutation in pending) {
        if (!_isCurrentAuth(generation) || state.user?.username != username) {
          return;
        }
        try {
          await _replayMutation(mutation);
          final removed = await _syncStore.removeIfUnchanged(mutation);
          if (!removed) {
            changedWhileSyncing = true;
            break;
          }
          _syncRetryStep = 0;
        } catch (error) {
          retryLater = _isRetryableSyncError(error);
          final marked = await _syncStore.markFailure(
            mutation,
            _messageFor(error),
            blocked: !retryLater,
          );
          if (!marked) changedWhileSyncing = true;
          break;
        }
      }
    } catch (_) {
      retryLater = true;
    } finally {
      final remaining = await _refreshPendingCount(username);
      if (_isCurrentAuth(generation) && state.user?.username == username) {
        state = state.copyWith(isSyncing: false);
      }
      // Entries enqueued while this drain was running are outside the
      // snapshot it processed; follow up immediately instead of waiting
      // for the next external trigger. Blocked entries never count here:
      // they only leave through a manual retry, so looping on them would
      // spin the timer forever.
      if (!retryLater && remaining > 0) changedWhileSyncing = true;
      if (_isCurrentAuth(generation) && state.user?.username == username) {
        if (changedWhileSyncing) {
          _scheduleSyncRetry(immediate: true);
        } else if (retryLater) {
          _scheduleSyncRetry();
        }
      }
    }
  }

  Future<void> _replayMutation(PendingBangumiMutation mutation) async {
    await _api.replayPendingMutation(mutation.kind, mutation.payload);
    if (mutation.kind != BangumiMutationKind.collection ||
        mutation.payload['complete_episodes'] != true ||
        mutation.payload['collection_type'] != CollectionType.done.value) {
      return;
    }
    final subjectId = (mutation.payload['subject_id'] as num).toInt();
    final episodes = await _api.getEpisodeCollections(subjectId);
    final unfinished = BangumiSupport.unfinishedMainEpisodeIds(episodes);
    if (unfinished.isNotEmpty) {
      await _api.updateEpisodesBatch(
        subjectId,
        episodeIds: unfinished,
        type: 2,
      );
    }
  }

  /// Keeps the episode snapshot in step with a just-enqueued edit, so a
  /// later offline read still shows it after the queue entry that carried
  /// it has been uploaded and removed. The direct edit covers the entry
  /// that may already be gone; the queue fold overlays any newer local
  /// state for the same subject.
  Future<void> _persistEpisodeSnapshot(
    int subjectId, {
    int? episodeId,
    int? type,
  }) async {
    try {
      final cached = await _snapshotCache.readEpisodeCollections(subjectId);
      if (cached == null || cached.isEmpty) return;
      final edited = [
        for (final item in cached)
          if (episodeId != null && item.episode.id == episodeId)
            item.copyWith(type: type ?? item.type)
          else
            item,
      ];
      final merged = await applyPendingEpisodeChanges(subjectId, edited);
      await _snapshotCache.writeEpisodeCollections(subjectId, merged);
    } catch (_) {
      // The queue entry is durable on its own; a snapshot hiccup must not
      // surface as a failed edit.
    }
  }

  bool _isRetryableSyncError(Object error) =>
      (error is BangumiApiException && error.retryable) ||
      (error is BangumiOAuthException && !error.invalidatesSession);

  void _scheduleSyncRetry({bool immediate = false}) {
    if (_syncRetryTimer != null || state.user == null) return;
    const delays = [
      Duration(seconds: 20),
      Duration(minutes: 1),
      Duration(minutes: 2),
      Duration(minutes: 5),
    ];
    final index = _syncRetryStep.clamp(0, delays.length - 1);
    if (!immediate) _syncRetryStep++;
    _syncRetryTimer = Timer(immediate ? Duration.zero : delays[index], () {
      _syncRetryTimer = null;
      unawaited(syncPendingChanges());
    });
  }

  /// Refreshes the queue counters in state and returns how many unblocked
  /// entries are still waiting to upload.
  Future<int> _refreshPendingCount([String? expectedUsername]) async {
    if (!mounted) return 0;
    final generation = _authGeneration;
    final username = expectedUsername ?? state.user?.username;
    if (username == null || username.isEmpty) return 0;
    try {
      final counts = await Future.wait([
        _syncStore.countFor(username),
        _syncStore.blockedCountFor(username),
      ]);
      final pending = counts[0] - counts[1];
      if (_isCurrentAuth(generation) && state.user?.username == username) {
        state = state.copyWith(
          pendingSyncCount: counts[0],
          blockedSyncCount: counts[1],
        );
      }
      return pending;
    } catch (_) {
      return 0;
    }
  }

  Future<List<PendingBangumiMutation>> blockedSyncMutations() async {
    final username = state.user?.username;
    if (username == null || username.isEmpty) return const [];
    final mutations = await _syncStore.blockedFor(username);
    if (state.user?.username != username) return const [];
    return mutations;
  }

  Future<String?> retryBlockedMutation(PendingBangumiMutation mutation) async {
    final username = state.user?.username;
    if (username == null || username.isEmpty) return '请先登录后再重试';
    if (mutation.username != username) return '该同步记录不属于当前账号';
    try {
      final retried = await _syncStore.retryIfUnchanged(mutation);
      await _refreshPendingCount(username);
      if (!retried) return '同步记录已变化，请刷新列表后重试';
      if (state.user?.username != username) return '登录状态已变化';
      await syncPendingChanges();
      return null;
    } catch (error) {
      return _messageFor(error);
    }
  }

  Future<String?> discardBlockedMutation(
    PendingBangumiMutation mutation,
  ) async {
    final username = state.user?.username;
    if (username == null || username.isEmpty) return '请先登录后再处理';
    if (mutation.username != username) return '该同步记录不属于当前账号';
    try {
      final discarded = await _syncStore.discardIfUnchanged(mutation);
      await _refreshPendingCount(username);
      if (!discarded) return '同步记录已变化，请刷新列表后重试';
      try {
        await _snapshotCache.clearCollections(username);
        final subjectId = (mutation.payload['subject_id'] as num?)?.toInt();
        if (subjectId != null &&
            (mutation.kind != BangumiMutationKind.collection ||
                mutation.payload['complete_episodes'] == true)) {
          await _snapshotCache.clearEpisodeCollections(subjectId);
        }
      } catch (_) {
        // The rejected queue entry is already gone. Snapshot cleanup is
        // best-effort; the UI also triggers a server refresh immediately.
      }
      return null;
    } catch (error) {
      return _messageFor(error);
    }
  }

  Future<String> _enqueueMutation({
    required BangumiMutationKind kind,
    required String mutationKey,
    required Map<String, dynamic> payload,
  }) async {
    final username = state.user?.username;
    if (username == null || username.isEmpty) {
      throw const BangumiApiException('请先登录后再修改');
    }
    await _syncStore.enqueue(
      username: username,
      kind: kind,
      mutationKey: mutationKey,
      payload: payload,
    );
    if (state.user?.username != username) {
      throw const BangumiApiException('登录状态已变化，修改已保存在原账号的本地队列中');
    }
    final subjectId = (payload['subject_id'] as num?)?.toInt();
    if (subjectId != null && subjectId > 0) {
      _localMutationRevision++;
      _subjectMutationRevisions[subjectId] = _localMutationRevision;
    }
    await _refreshPendingCount(username);
    if (state.user?.username != username) {
      throw const BangumiApiException('登录状态已变化，修改已保存在原账号的本地队列中');
    }
    unawaited(syncPendingChanges());
    return username;
  }

  Future<void> refresh({bool showIndicator = true}) async {
    final user = state.user;
    if (user == null) return;
    final username = user.username;
    await syncPendingChanges();
    if (state.user?.username != username) return;
    final generation = ++_collectionsGeneration;
    final requestMutationRevision = _localMutationRevision;
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
      var merged = _replaceType(state.collections, SubjectType.anime, anime);
      merged = await _overlayPendingCollections(username, merged);
      merged = _preserveCollectionsChangedAfter(
        merged,
        requestMutationRevision,
      );
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
    await syncPendingChanges();
    if (state.user?.username != username) return persistError;
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
      List<UserEpisodeCollection> episodes;
      try {
        episodes = await _api.getEpisodeCollections(collection.subjectId);
      } catch (_) {
        episodes =
            await _snapshotCache.readEpisodeCollections(collection.subjectId) ??
            const [];
        if (episodes.isEmpty) rethrow;
      }
      episodes = await applyPendingEpisodeChanges(
        collection.subjectId,
        episodes,
      );
      await _snapshotCache.writeEpisodeCollections(
        collection.subjectId,
        episodes,
      );
      final target = BangumiSupport.nextUnwatchedMain(episodes);
      if (target == null) return '已经没有下一集了';
      final watchedCount = BangumiSupport.watchedMainCountAfterMark(
        episodes,
        target.episode.id,
      );
      final username = await _enqueueMutation(
        kind: BangumiMutationKind.episode,
        mutationKey: 'episode:${target.episode.id}',
        payload: {
          'subject_id': collection.subjectId,
          'episode_id': target.episode.id,
          'type': 2,
          'local_episode_status': watchedCount,
        },
      );
      await _persistEpisodeSnapshot(
        collection.subjectId,
        episodeId: target.episode.id,
        type: 2,
      );
      if (state.user?.username != username) {
        return '登录状态已变化，修改已保存在原账号的本地队列中';
      }
      _replaceCollection(collection.copyWith(episodeStatus: watchedCount));
      await _snapshotCache.writeCollections(username, state.collections);
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
    int? previousType,
    bool trackGlobalBusy = true,
  }) async {
    if (trackGlobalBusy) {
      _setUpdating(subjectId, true);
    }
    try {
      final collection = state.collectionFor(subjectId);
      int? nextCount;
      if (collection != null && previousType != null && previousType != type) {
        final delta = (type == 2 ? 1 : 0) - (previousType == 2 ? 1 : 0);
        nextCount = (collection.episodeStatus + delta).clamp(0, 1 << 30);
      }
      final username = await _enqueueMutation(
        kind: BangumiMutationKind.episode,
        mutationKey: 'episode:$episodeId',
        payload: {
          'subject_id': subjectId,
          'episode_id': episodeId,
          'type': type,
          'local_episode_status': ?nextCount,
        },
      );
      await _persistEpisodeSnapshot(
        subjectId,
        episodeId: episodeId,
        type: type,
      );
      if (collection != null && nextCount != null) {
        _replaceCollection(collection.copyWith(episodeStatus: nextCount));
        await _snapshotCache.writeCollections(username, state.collections);
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
      final shouldCompleteEpisodes =
          completeEpisodesWhenDone &&
          type == CollectionType.done &&
          subject.type.hasEpisodes;
      var resolvedEpisodeStatus = nextEpisodeStatus;
      List<UserEpisodeCollection>? cachedEpisodes;
      if (shouldCompleteEpisodes) {
        cachedEpisodes = await _snapshotCache.readEpisodeCollections(
          subject.id,
        );
        if (cachedEpisodes != null && cachedEpisodes.isNotEmpty) {
          resolvedEpisodeStatus = BangumiSupport.mainEpisodeCollections(
            cachedEpisodes,
          ).length;
        } else if (subject.episodeCount > 0) {
          resolvedEpisodeStatus = subject.episodeCount;
        }
      }
      final username = await _enqueueMutation(
        kind: BangumiMutationKind.collection,
        mutationKey: 'collection:${subject.id}',
        payload: {
          'subject_id': subject.id,
          'subject': subject.toJson(),
          'collection_type': type.value,
          'rate': nextRate,
          'comment': nextComment,
          'tags': nextTags,
          'private': nextPrivate,
          'episode_status': subject.type.hasVolumes ? nextEpisodeStatus : null,
          'local_episode_status': resolvedEpisodeStatus,
          'volume_status': subject.type.hasVolumes ? nextVolumeStatus : null,
          'complete_episodes': shouldCompleteEpisodes,
          'local_updated_at': DateTime.now().toIso8601String(),
        },
      );
      if (shouldCompleteEpisodes && cachedEpisodes != null) {
        await _snapshotCache.writeEpisodeCollections(subject.id, [
          for (final item in cachedEpisodes)
            if (item.episode.type == 0) item.copyWith(type: 2) else item,
        ]);
      }
      if (state.user?.username != username) {
        return '登录状态已变化，修改已保存在原账号的本地队列中';
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
      await _snapshotCache.writeCollections(username, state.collections);
      return null;
    } catch (error) {
      return _messageFor(error);
    } finally {
      _setUpdating(subject.id, false);
    }
  }

  Future<void> signOut() => _forceSignOut();

  Future<void> _forceSignOut({String? message}) async {
    _homePreparationTimer?.cancel();
    final generation = ++_authGeneration;
    _collectionsGeneration++;
    _subjectMutationRevisions.clear();
    _localMutationRevision = 0;
    _syncRetryTimer?.cancel();
    _syncRetryTimer = null;
    _refreshInFlight = null;
    _cachedRefreshToken = null;
    _cachedExpiresAt = null;
    _cachedOAuthConfig = null;
    _hasStoredCredentials = false;
    _api.setAccessToken(null);
    CommunityService.shared.setAccessToken(null);
    CommunityService.shared.setCurrentUsername(null);
    state = SessionState(
      phase: SessionPhase.signedOut,
      authActivity: AuthActivity.signingOut,
      networkRoute: _networkRoute,
      message: message,
    );
    try {
      onWebsiteSessionCleared?.call();
    } catch (_) {}
    String? cleanupError;
    try {
      await _oauth.cancelAuthorization();
    } catch (_) {}
    await _writeAuth(generation, () async {
      // Each cleanup runs even if another backend is unavailable.
      for (final cleanup in <Future<void> Function()>[
        _tokenStore.clear,
        _websiteSessionStore.clear,
        _snapshotCache.clearLastUser,
        CommunityService.shared.clearAccountCache,
      ]) {
        try {
          await cleanup();
        } catch (error) {
          cleanupError ??= '清理本地登录数据失败，请重试退出：${_messageFor(error)}';
        }
      }
    });
    if (!_isCurrentAuth(generation)) return;
    await WebsiteCookieBridge.clearBgmCookies();
    if (!_isCurrentAuth(generation)) return;
    state = SessionState(
      phase: SessionPhase.signedOut,
      networkRoute: _networkRoute,
      message: cleanupError ?? message,
      canRetrySignOut: cleanupError != null,
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

  @override
  void dispose() {
    _homePreparationTimer?.cancel();
    _collectionsGeneration++;
    _authGeneration++;
    _syncRetryTimer?.cancel();
    super.dispose();
  }
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
