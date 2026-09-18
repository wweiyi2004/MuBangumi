import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/bangumi_oauth.dart';
import '../core/network/bangumi_api.dart';
import '../core/network/bangumi_endpoints.dart';
import '../core/network/community_service.dart';
import '../core/auth/website_cookie_bridge.dart';
import '../core/auth/website_session.dart';
import '../core/storage/bangumi_sync_store.dart';
import '../core/storage/snapshot_cache.dart';
import '../core/storage/token_store.dart';
import '../models/bangumi_models.dart';
import '../models/episode_edit.dart';
import '../models/library_batch.dart';
import '../features/auth/application/session_credentials.dart';
import '../features/collection/application/collection_editor.dart';
import '../features/collection/application/collection_edit_view.dart';
import '../features/collection/application/collection_loader.dart';
import '../features/collection/application/episode_collection_reader.dart';
import '../features/sync/application/pending_sync_controller.dart';
import 'app_providers.dart';
import 'session_state.dart';
import 'website_session_controller.dart';
import 'network_status_controller.dart';

// Preserve the public entry point while consumers migrate by feature.
export 'app_providers.dart';
export 'session_state.dart';

/// Credentials from a completed browser authorization whose account check has
/// not succeeded yet. Deliberately in memory only: an unverified token must
/// never replace a saved login, but throwing it away forces the user through
/// the entire browser flow again for what is usually a transient failure.
class _PendingVerification {
  const _PendingVerification({
    required this.token,
    required this.tokens,
    this.config,
    this.websiteCookies,
  });

  final String token;
  final OAuthTokenBundle tokens;
  final OAuthConfig? config;
  final List<WebsiteCookie>? websiteCookies;
}

class SessionController extends StateNotifier<SessionState>
    implements EpisodeCollectionReader {
  SessionController(
    this._api,
    this._oauth,
    this._tokenStore, {
    SnapshotCache? snapshotCache,
    BangumiSyncStore? syncStore,
    WebsiteSessionStore? websiteSessionStore,
    this.onWebsiteSessionCleared,
    this.onWebsiteSessionSaved,
    bool Function()? isOffline,
  }) : _snapshotCache = snapshotCache ?? SnapshotCache.shared,
       _syncStore = syncStore ?? BangumiSyncStore.shared,
       _websiteSessionStore = websiteSessionStore ?? WebsiteSessionStore(),
       super(const SessionState()) {
    _credentials = SessionCredentials(
      oauth: _oauth,
      store: _tokenStore,
      currentGeneration: () => _authGeneration,
      isCurrent: _isCurrentAuth,
      canRefresh: () =>
          mounted &&
          !state.isAuthenticating &&
          state.authActivity != AuthActivity.signingOut,
      onAccessTokenChanged: (token) {
        _api.setAccessToken(token);
        CommunityService.shared.setAccessToken(token);
      },
      onRefreshError: _onTokenRefreshError,
    );
    _pendingSync = PendingSyncController(
      api: _api,
      store: _syncStore,
      readAccount: _readSyncAccount,
      onProgress: (account, progress) {
        if (_readSyncAccount() != account) return;
        state = state.copyWith(
          pendingSyncCount: progress.pendingCount,
          blockedSyncCount: progress.blockedCount,
          isSyncing: progress.isSyncing,
        );
      },
      messageFor: _messageFor,
    );
    _collectionEditor = CollectionEditor(
      api: _api,
      snapshotCache: _snapshotCache,
      syncStore: _syncStore,
      readAccount: () => batchAccount,
      readView: () => CollectionEditView(
        collections: state.collections,
        updatingSubjects: state.updatingSubjects,
        episodeUndo: state.episodeUndo,
        lastEpisodeEdit: state.lastEpisodeEdit,
      ),
      writeView: (view) {
        state = state.copyWith(
          collections: view.collections,
          updatingSubjects: view.updatingSubjects,
          episodeUndo: view.episodeUndo,
          clearEpisodeUndo: view.episodeUndo == null,
          lastEpisodeEdit: view.lastEpisodeEdit,
        );
      },
      isAlive: () => mounted,
      syncPendingChanges: syncPendingChanges,
      refreshPendingCount: _refreshPendingCount,
      messageFor: _messageFor,
      preferCachedReads: () =>
          isOffline?.call() == true ||
          (state.isUsingCachedCollections && !state.isLoadingCollections),
    );
    _collectionLoader = CollectionLoader(
      api: _api,
      snapshotCache: _snapshotCache,
      editor: _collectionEditor,
      syncPendingChanges: syncPendingChanges,
      onProgress: (progress) {
        state = state.copyWith(
          collections: progress.collections,
          isRefreshing: progress.isRefreshing,
          isLoadingCollections: progress.isLoadingCollections,
          isUsingCachedCollections: progress.isUsingCachedCollections,
          clearCollectionsSavedAt: progress.collections != null,
          isPreparingHome: progress.releaseInitialWait ? false : null,
          message: progress.message,
          clearMessage: progress.clearMessage,
        );
      },
      messageFor: _messageFor,
    );
    _api.ensureFreshToken = _credentials.ensureFreshToken;
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
  final FutureOr<void> Function()? onWebsiteSessionCleared;
  final FutureOr<void> Function()? onWebsiteSessionSaved;
  BangumiNetworkRoute _networkRoute = BangumiNetworkRoute.official;
  int _authGeneration = 0;
  _PendingVerification? _pendingVerification;
  late final SessionCredentials _credentials;
  late final PendingSyncController _pendingSync;
  late final CollectionEditor _collectionEditor;
  late final CollectionLoader _collectionLoader;

  SyncAccount? _readSyncAccount() {
    if (!mounted ||
        state.phase != SessionPhase.signedIn ||
        state.isAuthenticating) {
      return null;
    }
    final username = state.user?.username;
    if (username == null || username.isEmpty) return null;
    return (generation: _authGeneration, username: username);
  }

  EpisodeUndo? get pendingEpisodeUndo => _collectionEditor.pendingEpisodeUndo;
  @override
  int get episodeRevision => _collectionEditor.episodeRevision;
  @override
  LibraryBatchAccount? get batchAccount =>
      mounted &&
          state.user != null &&
          state.phase == SessionPhase.signedIn &&
          !state.isAuthenticating
      ? LibraryBatchAccount(
          userId: state.user!.id,
          username: state.user!.username,
          generation: _authGeneration,
        )
      : null;
  bool isCurrentBatchAccount(LibraryBatchAccount account) =>
      _collectionEditor.isCurrentBatchAccount(account);
  int collectionMutationRevision(int subjectId) =>
      _collectionEditor.collectionMutationRevision(subjectId);
  @override
  UserCollection? batchCollection(int subjectId) =>
      _collectionEditor.batchCollection(subjectId);

  bool _isCurrentAuth(int generation) =>
      mounted && generation == _authGeneration;

  Timer? _homePreparationTimer;

  Future<void> _bootstrap() async {
    final generation = ++_authGeneration;
    state = SessionState(
      phase: SessionPhase.booting,
      networkRoute: _networkRoute,
    );
    try {
      final saved = await _credentials.readStored(generation);
      if (saved == null || !_isCurrentAuth(generation)) return;
      _networkRoute = saved.route;
      var token = saved.accessToken;
      _api.setNetworkRoute(_networkRoute);
      BangumiEndpoints.setRoute(_networkRoute);
      state = state.copyWith(networkRoute: _networkRoute);
      final shouldRefresh = saved.shouldRefresh;
      final hasStoredToken = token != null && token.trim().isNotEmpty;
      if (shouldRefresh && !hasStoredToken) {
        // Without a token there is nothing to restore, so the refresh has to
        // finish before the session can be rebuilt.
        try {
          token = await _credentials.refreshAndPersist(generation);
          if (!_isCurrentAuth(generation)) return;
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
        _credentials.setAccessToken(null);
        CommunityService.shared.setCurrentUsername(null);
        state = SessionState(
          phase: SessionPhase.signedOut,
          networkRoute: _networkRoute,
        );
        return;
      }
      final restored = await _restoreSignedInSnapshot(token, generation);
      if (!_isCurrentAuth(generation)) return;
      // Refresh after restoring trusted identity and installing the saved
      // token. Starting it earlier can let a late restore overwrite a newly
      // rotated token. /me shares this refresh through ensureFreshToken.
      if (shouldRefresh && hasStoredToken) {
        unawaited(tryRefreshAccessToken());
      }
      await _authenticate(
        token,
        generation: generation,
        persist: false,
        alreadyRestored: restored,
      );
    } catch (error) {
      if (!_isCurrentAuth(generation)) return;
      _credentials.setAccessToken(null);
      state = SessionState(
        phase: SessionPhase.signedOut,
        networkRoute: _networkRoute,
        canRetrySignIn: true,
        message: '暂时无法恢复登录，可重试连接：${_messageFor(error)}',
      );
    }
  }

  /// Retry existing credentials without asking the user to authorize again.
  ///
  /// When a browser authorization already succeeded but its account check
  /// failed, this resumes that verification rather than restarting OAuth.
  Future<void> retrySavedSignIn() async {
    if (state.phase != SessionPhase.signedOut ||
        state.authActivity != AuthActivity.idle) {
      return;
    }
    final pending = _pendingVerification;
    if (pending == null) {
      await _bootstrap();
      return;
    }
    // _beginLogin clears the stored pending entry; should this attempt fail
    // transiently, the handler in _authenticate installs it again.
    final generation = _beginLogin(AuthActivity.verifying);
    await _authenticate(
      pending.token,
      generation: generation,
      persist: true,
      tokens: pending.tokens,
      config: pending.config,
      websiteCookies: pending.websiteCookies,
    );
  }

  Future<bool> _restoreSignedInSnapshot(String token, int generation) async {
    try {
      final lastUser = await _tokenStore.readVerifiedUser(token);
      if (lastUser == null || !_isCurrentAuth(generation)) return false;
      final snapshot = await _snapshotCache.readCollections(lastUser.username);
      final cached = await _collectionEditor.overlayPendingCollections(
        lastUser.username,
        snapshot ?? const [],
      );
      if (!_isCurrentAuth(generation)) return false;
      _credentials.setAccessToken(token);
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
        isUsingCachedCollections: cached.isNotEmpty,
        collectionsSavedAt: snapshot is SnapshotItems<UserCollection>
            ? snapshot.savedAt
            : null,
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
    _pendingVerification = null;
    _credentials.reset();
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
    List<WebsiteCookie> Function()? websiteCookies,
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
        websiteCookies: websiteCookies?.call(),
      );
    } catch (error) {
      if (!_isCurrentAuth(generation)) return false;
      state = SessionState(
        phase: SessionPhase.signedOut,
        networkRoute: _networkRoute,
        canRetrySignIn: _credentials.hasStoredCredentials,
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
          canRetrySignIn: _credentials.hasStoredCredentials,
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
    List<WebsiteCookie>? websiteCookies,
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
    _credentials.setAccessToken(token);
    try {
      final user = await _api.getMe();
      if (!_isCurrentAuth(generation)) return false;
      if (user.id <= 0 || user.username.trim().isEmpty) {
        throw const BangumiApiException('账号信息不完整，请重试验证');
      }
      BangumiUser? previousUser;
      try {
        final previousToken = await _tokenStore.read();
        if (previousToken != null) {
          previousUser = await _tokenStore.readVerifiedUser(previousToken);
        }
      } catch (_) {
        // A newly verified login can repair a damaged old credential record;
        // unreadable old identity is never used to restore an offline account.
      }
      if (!_isCurrentAuth(generation)) return false;
      if (persist) {
        if (tokens != null) {
          if (!await _credentials.persistTokens(
            tokens,
            generation,
            config: config,
          )) {
            return false;
          }
        } else {
          if (!await _credentials.persistAccessToken(token, generation)) {
            return false;
          }
        }
      }
      if (!await _credentials.writeCurrent(
        generation,
        () => _tokenStore.bindVerifiedUser(
          _credentials.accessToken ?? token,
          user,
        ),
      )) {
        return false;
      }

      List<UserCollection>? snapshot;
      try {
        if (!_isCurrentAuth(generation)) return false;
        if (previousUser != null && previousUser.id != user.id) {
          if (!await _credentials.writeCurrent(generation, () async {
            await _websiteSessionStore.clear();
            await onWebsiteSessionCleared?.call();
            await CommunityService.shared.clearAccountCache();
          })) {
            return false;
          }
          _collectionEditor.reset();
        }
        snapshot = alreadyRestored && state.user?.username == user.username
            ? state.collections
            : await _snapshotCache.readCollections(user.username);
        await _credentials.writeCurrent(
          generation,
          () => _snapshotCache.writeLastUser(user),
        );
      } catch (_) {
        // Authentication succeeded; optional list caches cannot turn it into
        // a failed login. Collections are fetched independently below.
      }
      if (websiteCookies != null && websiteCookies.isNotEmpty) {
        final website = WebsiteSessionSnapshot(
          cookies: websiteCookies,
          syncedAt: DateTime.now(),
        );
        if (website.hasSessionCookies) {
          try {
            if (!await _credentials.writeCurrent(generation, () async {
              await _websiteSessionStore.write(website);
              await onWebsiteSessionSaved?.call();
            })) {
              return false;
            }
          } catch (_) {
            // A supplemental session must not invalidate a verified OAuth login.
          }
        }
      }
      final cached = await _collectionEditor.overlayPendingCollections(
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
        isUsingCachedCollections: cached.isNotEmpty,
        collectionsSavedAt: alreadyRestored
            ? state.collectionsSavedAt
            : snapshot is SnapshotItems<UserCollection>
            ? snapshot.savedAt
            : null,
      );
      _homePreparationTimer?.cancel();
      if (state.isPreparingHome) {
        _homePreparationTimer = Timer(const Duration(seconds: 8), () {
          if (_isCurrentAuth(generation)) enterHomeNow();
        });
      }
      unawaited(_refreshPendingCount(user.username));
      unawaited(_collectionLoader.loadInitial());
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
        _credentials.setAccessToken(null);
        CommunityService.shared.setCurrentUsername(null);
        // A browser authorization that succeeded but whose account check was
        // interrupted must not be thrown away. Hold it in memory so the user
        // can retry verification; it is never persisted while unverified, so
        // it can never replace an existing saved login.
        final retained = tokens != null && !_invalidatesSession(error);
        if (retained) {
          _pendingVerification = _PendingVerification(
            token: token,
            tokens: tokens,
            config: config,
            websiteCookies: websiteCookies,
          );
        }
        state = SessionState(
          phase: SessionPhase.signedOut,
          networkRoute: _networkRoute,
          canRetrySignIn: retained || _credentials.hasStoredCredentials,
          hasPendingVerification: retained,
          message: retained
              ? '已授权成功，但暂时无法验证账号，可重试验证：${_messageFor(error)}'
              : _messageFor(error),
        );
      }
      return false;
    }
  }

  /// Leave the bounded first-screen wait; collection loading continues.
  void enterHomeNow() {
    _homePreparationTimer?.cancel();
    _homePreparationTimer = null;
    if (!mounted || !state.isPreparingHome) return;
    state = state.copyWith(isPreparingHome: false);
  }

  Future<bool> tryRefreshAccessToken() => _credentials.tryRefreshAccessToken();

  Future<void> _onTokenRefreshError(Object error) async {
    if (_invalidatesSession(error)) {
      await _forceSignOut(message: '登录已过期，请重新授权：${_messageFor(error)}');
    } else if (state.phase == SessionPhase.signedIn) {
      state = state.copyWith(message: '暂时无法刷新登录状态：${_messageFor(error)}');
    }
  }

  Future<void> syncPendingChanges({bool retryBlocked = false}) =>
      _pendingSync.sync(retryBlocked: retryBlocked);

  Future<int> _refreshPendingCount([String? expectedUsername]) {
    final account = _readSyncAccount();
    if (account == null ||
        (expectedUsername != null && account.username != expectedUsername)) {
      return Future.value(0);
    }
    return _pendingSync.refreshCount(account: account);
  }

  Future<void> refresh({bool showIndicator = true}) =>
      _collectionLoader.refresh(showIndicator: showIndicator);

  Future<String?> setNetworkRoute(BangumiNetworkRoute route) async {
    if (route == _networkRoute) return null;
    _networkRoute = route;
    _api.setNetworkRoute(route);
    BangumiEndpoints.setRoute(route);
    _collectionLoader.invalidate();
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
    final message = await _collectionLoader.reloadAll();
    if (message == null) return persistError;
    final syncFailure = '线路已切换，但同步失败：$message';
    return persistError == null ? syncFailure : '$syncFailure；$persistError';
  }

  @override
  Future<List<UserEpisodeCollection>?> readEpisodeSnapshot(int subjectId) =>
      _collectionEditor.readEpisodeSnapshot(subjectId);
  @override
  Future<List<UserEpisodeCollection>> loadEpisodeCollections(
    int subjectId, {
    int? episodeType,
  }) => _collectionEditor.loadEpisodeCollections(
    subjectId,
    episodeType: episodeType,
  );
  @override
  Future<List<UserEpisodeCollection>> applyPendingEpisodeChanges(
    int subjectId,
    List<UserEpisodeCollection> source, {
    int? afterRevision,
  }) => _collectionEditor.applyPendingEpisodeChanges(
    subjectId,
    source,
    afterRevision: afterRevision,
  );
  Future<List<PendingBangumiMutation>> blockedSyncMutations() =>
      _collectionEditor.blockedSyncMutations();
  Future<String?> retryBlockedMutation(PendingBangumiMutation mutation) =>
      _collectionEditor.retryBlockedMutation(mutation);
  Future<String?> discardBlockedMutation(PendingBangumiMutation mutation) =>
      _collectionEditor.discardBlockedMutation(mutation);
  Future<String?> markNextEpisode(
    UserCollection collection, {
    void Function(EpisodeUndo)? onUndoReady,
  }) => _collectionEditor.markNextEpisode(collection, onUndoReady: onUndoReady);
  Future<String?> setEpisode({
    required int subjectId,
    required int episodeId,
    required int type,
    int? previousType,
    Episode? episode,
    bool trackGlobalBusy = true,
    void Function(EpisodeUndo)? onUndoReady,
  }) => _collectionEditor.setEpisode(
    subjectId: subjectId,
    episodeId: episodeId,
    type: type,
    previousType: previousType,
    episode: episode,
    trackGlobalBusy: trackGlobalBusy,
    onUndoReady: onUndoReady,
  );
  Future<String?> undoEpisode(EpisodeUndo undo) =>
      _collectionEditor.undoEpisode(undo);
  void dismissEpisodeUndo(EpisodeUndo undo) =>
      _collectionEditor.dismissEpisodeUndo(undo);
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
    LibraryBatchAccount? expectedAccount,
    int? expectedRevision,
    bool requireExisting = false,
    void Function()? onQueued,
    bool statusOnly = false,
    String? queueKey,
    bool deferSync = false,
  }) => _collectionEditor.changeCollection(
    subject,
    type,
    completeEpisodesWhenDone: completeEpisodesWhenDone,
    rate: rate,
    comment: comment,
    tags: tags,
    private: private,
    episodeStatus: episodeStatus,
    volumeStatus: volumeStatus,
    expectedAccount: expectedAccount,
    expectedRevision: expectedRevision,
    requireExisting: requireExisting,
    onQueued: onQueued,
    statusOnly: statusOnly,
    queueKey: queueKey,
    deferSync: deferSync,
  );

  Future<void> signOut() => _forceSignOut();

  Future<void> _forceSignOut({String? message}) async {
    _homePreparationTimer?.cancel();
    final generation = ++_authGeneration;
    _collectionLoader.invalidate();
    _collectionEditor.reset();
    _pendingSync.cancelRetry();
    _credentials.reset(forgetStoredCredentials: true);
    _pendingVerification = null;
    _credentials.setAccessToken(null);
    CommunityService.shared.setCurrentUsername(null);
    state = SessionState(
      phase: SessionPhase.signedOut,
      authActivity: AuthActivity.signingOut,
      networkRoute: _networkRoute,
      message: message,
    );
    try {
      await onWebsiteSessionCleared?.call();
    } catch (_) {}
    String? cleanupError;
    try {
      await _oauth.cancelAuthorization();
    } catch (_) {}
    await _credentials.writeCurrent(generation, () async {
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

  String _messageFor(Object error) => error is BangumiApiException
      ? error.message
      : error is BangumiOAuthException
      ? error.message
      : '发生了意外错误，请稍后重试';

  bool _invalidatesSession(Object error) =>
      _credentials.invalidatesSession(error);

  @override
  void dispose() {
    _homePreparationTimer?.cancel();
    _authGeneration++;
    _pendingSync.dispose();
    _collectionLoader.dispose();
    _collectionEditor.dispose();
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
    isOffline: () =>
        ref.read(networkStatusProvider) == NetworkAvailability.unavailable,
    onWebsiteSessionCleared: () async {
      // Keep in-memory website session UI state aligned with storage wipe.
      await ref.read(websiteSessionProvider.notifier).markCleared();
    },
    onWebsiteSessionSaved: () =>
        ref.read(websiteSessionProvider.notifier).reload(),
  );
});
