import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/bangumi_oauth.dart';
import '../core/network/bangumi_api.dart';
import '../core/network/bangumi_endpoints.dart';
import '../core/network/community_service.dart';
import '../core/storage/token_store.dart';
import '../models/bangumi_models.dart';

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
  SessionController(this._api, this._oauth, this._tokenStore)
    : super(const SessionState()) {
    _api.ensureFreshToken = _ensureFreshToken;
    _api.onUnauthorizedRefresh = tryRefreshAccessToken;
    CommunityService.shared.onUnauthorizedRefresh = tryRefreshAccessToken;
    unawaited(_bootstrap());
  }

  final BangumiApi _api;
  final BangumiOAuth _oauth;
  final TokenStore _tokenStore;
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
        await _forceSignOut(
          message: '登录已过期，请重新授权：${_messageFor(error)}',
        );
        return;
      }
    }
    if (token == null || token.trim().isEmpty) {
      await _forceSignOut();
      return;
    }
    await _authenticate(token, persist: false);
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

  Future<bool> signInWithOAuth(OAuthConfig config) async {
    state = state.copyWith(
      phase: SessionPhase.booting,
      isRefreshing: true,
      clearMessage: true,
    );
    try {
      await _tokenStore.writeOAuthConfig(config);
      _cachedOAuthConfig = config;
      final tokens = await _oauth.authorize(config);
      await _persistTokens(tokens);
      return _authenticate(tokens.accessToken, persist: false);
    } catch (error) {
      state = SessionState(
        phase: SessionPhase.signedOut,
        networkRoute: _networkRoute,
        message: _messageFor(error),
      );
      return false;
    }
  }

  Future<bool> _authenticate(String token, {required bool persist}) async {
    state = state.copyWith(
      phase: SessionPhase.booting,
      isRefreshing: true,
      isLoadingCollections: true,
      clearMessage: true,
    );
    _api.setAccessToken(token);
    CommunityService.shared.setAccessToken(token);
    try {
      // Enter the shell after /me only — collections load in the background.
      final user = await _api.getMe();
      CommunityService.shared.setCurrentUsername(user.username);
      if (persist) {
        await _tokenStore.write(token);
        _cachedRefreshToken = null;
        _cachedExpiresAt = null;
      }
      state = SessionState(
        phase: SessionPhase.signedIn,
        user: user,
        collections: const [],
        networkRoute: _networkRoute,
        isLoadingCollections: true,
        isRefreshing: true,
      );
      unawaited(_loadCollectionsAfterSignIn(user.username));
      return true;
    } catch (error) {
      if (!persist) {
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
      state = state.copyWith(
        collections: anime,
        isRefreshing: false,
        isLoadingCollections: true,
      );
      await _loadRemainingCollections(username);
    } catch (error) {
      if (generation != _collectionsGeneration) return;
      state = state.copyWith(
        isRefreshing: false,
        isLoadingCollections: false,
        message: '收藏同步失败：${_messageFor(error)}',
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

  Future<void> _fetchAndMergeOtherTypes(
    String username,
    int generation,
  ) async {
    try {
      // Load other types one-by-one so the UI stays responsive and the
      // network stack is not flooded after login.
      final otherTypes = SubjectType.values
          .where((type) => type != SubjectType.anime)
          .toList();
      var merged = state.collections
          .where((item) => item.subject.type == SubjectType.anime)
          .toList();
      for (final type in otherTypes) {
        if (generation != _collectionsGeneration ||
            state.phase != SessionPhase.signedIn ||
            state.user?.username != username) {
          return;
        }
        final page = await _api.getUserCollections(
          username,
          subjectType: type,
        );
        merged = [
          ...merged.where((item) => item.subject.type != type),
          ...page,
        ];
        _sortCollections(merged);
        // Incremental UI update keeps library usable while sync continues.
        state = state.copyWith(
          collections: merged,
          isLoadingCollections: true,
          isRefreshing: false,
        );
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }
      if (generation != _collectionsGeneration) return;
      state = state.copyWith(
        collections: merged,
        isLoadingCollections: false,
        isRefreshing: false,
      );
    } catch (error) {
      if (generation != _collectionsGeneration) return;
      state = state.copyWith(
        isLoadingCollections: false,
        isRefreshing: false,
        message: '部分收藏同步失败：${_messageFor(error)}',
      );
    }
  }

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
      await _forceSignOut(
        message: '登录已过期，请重新授权：${_messageFor(error)}',
      );
      return false;
    }
  }

  Future<void> refresh({bool showIndicator = true}) async {
    final user = state.user;
    if (user == null) return;
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
        user.username,
        subjectType: SubjectType.anime,
      );
      final others = state.collections
          .where((item) => item.subject.type != SubjectType.anime)
          .toList();
      state = state.copyWith(
        collections: [...anime, ...others],
        isRefreshing: false,
        isLoadingCollections: true,
        clearMessage: true,
      );
      await _loadRemainingCollections(user.username);
    } catch (error) {
      state = state.copyWith(
        isRefreshing: false,
        isLoadingCollections: false,
        message: _messageFor(error),
      );
    }
  }

  Future<String?> setNetworkRoute(BangumiNetworkRoute route) async {
    if (route == _networkRoute) return null;
    _networkRoute = route;
    _api.setNetworkRoute(route);
    BangumiEndpoints.setRoute(route);
    await _tokenStore.writeNetworkRoute(route);
    final user = state.user;
    state = state.copyWith(
      networkRoute: route,
      isRefreshing: user != null,
      isLoadingCollections: user != null,
      clearMessage: true,
    );
    if (user == null) return null;
    try {
      final collections = await _loadAllCollections(user.username);
      state = state.copyWith(
        collections: collections,
        isRefreshing: false,
        isLoadingCollections: false,
        clearMessage: true,
      );
      return null;
    } catch (error) {
      final message = _messageFor(error);
      state = state.copyWith(
        isRefreshing: false,
        isLoadingCollections: false,
        message: message,
      );
      return message;
    }
  }

  Future<String?> markNextEpisode(UserCollection collection) async {
    if (state.updatingSubjects.contains(collection.subjectId)) return null;
    _setUpdating(collection.subjectId, true);
    try {
      final episodes = await _api.getEpisodeCollections(collection.subjectId);
      UserEpisodeCollection? target;
      for (final episode in episodes) {
        if (!episode.isWatched) {
          target = episode;
          break;
        }
      }
      if (target == null) return '已经没有下一集了';
      await _api.updateEpisode(target.episode.id, type: 2);
      final watchedCount = episodes.where((item) => item.isWatched).length + 1;
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
  }) async {
    _setUpdating(subject.id, true);
    try {
      final old = state.collectionFor(subject.id);
      final nextRate = rate ?? old?.rate ?? 0;
      final nextComment = comment ?? old?.comment ?? '';
      final nextTags = tags ?? old?.tags ?? const <String>[];
      final nextPrivate = private ?? old?.private ?? false;
      await _api.updateCollection(
        subject.id,
        type,
        rate: nextRate,
        comment: nextComment,
        tags: nextTags,
        private: nextPrivate,
      );
      var episodeStatus = old?.episodeStatus ?? 0;
      // Garage #461: marking as "done" auto-completes regular episode progress.
      if (completeEpisodesWhenDone &&
          type == CollectionType.done &&
          subject.type.hasEpisodes) {
        try {
          final episodes = await _api.getEpisodeCollections(subject.id);
          final unfinished = [
            for (final item in episodes)
              if (!item.isWatched) item.episode.id,
          ];
          if (unfinished.isNotEmpty) {
            await _api.updateEpisodesBatch(
              subject.id,
              episodeIds: unfinished,
              type: 2,
            );
          }
          episodeStatus = episodes.length;
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
            episodeStatus: episodeStatus,
          ),
        );
      } else {
        state = state.copyWith(
          collections: [
            UserCollection(
              subjectId: subject.id,
              type: type,
              rate: nextRate,
              episodeStatus: episodeStatus,
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
    _api.setAccessToken(null);
    CommunityService.shared.setAccessToken(null);
    CommunityService.shared.setCurrentUsername(null);
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
}

final sessionProvider = StateNotifierProvider<SessionController, SessionState>((
  ref,
) {
  return SessionController(
    ref.watch(bangumiApiProvider),
    ref.watch(bangumiOAuthProvider),
    ref.watch(tokenStoreProvider),
  );
});
