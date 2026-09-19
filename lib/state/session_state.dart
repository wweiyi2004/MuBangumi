import '../core/network/bangumi_endpoints.dart';
import '../models/bangumi_models.dart';
import '../models/episode_edit.dart';
import '../models/collection_coverage.dart';

enum SessionPhase { booting, signedOut, signedIn }

/// Login work is independent of collection refreshes and background uploads.
enum AuthActivity { idle, authorizing, verifying, signingOut }

class SessionState {
  const SessionState({
    this.phase = SessionPhase.booting,
    this.authActivity = AuthActivity.idle,
    this.canRetrySignIn = false,
    this.hasPendingVerification = false,
    this.canRetrySignOut = false,
    this.isPreparingHome = false,
    this.user,
    this.collections = const [],
    this.isRefreshing = false,
    this.isLoadingCollections = false,
    this.isUsingCachedCollections = false,
    this.collectionsSavedAt,
    this.collectionCoverage,
    this.updatingSubjects = const {},
    this.networkRoute = BangumiNetworkRoute.official,
    this.pendingSyncCount = 0,
    this.blockedSyncCount = 0,
    this.isSyncing = false,
    this.message,
    this.episodeUndo,
    this.lastEpisodeEdit,
  });

  final SessionPhase phase;
  final AuthActivity authActivity;
  final bool canRetrySignIn;

  /// A browser authorization finished but its account check did not; retrying
  /// resumes verification instead of restarting the OAuth flow.
  final bool hasPendingVerification;
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
  final bool isUsingCachedCollections;
  final DateTime? collectionsSavedAt;
  final CollectionCoverage? collectionCoverage;
  final Set<int> updatingSubjects;
  final BangumiNetworkRoute networkRoute;
  final int pendingSyncCount;
  final int blockedSyncCount;
  final bool isSyncing;
  final String? message;
  final EpisodeUndo? episodeUndo;
  final EpisodeEdit? lastEpisodeEdit;

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
    bool? hasPendingVerification,
    bool? canRetrySignOut,
    bool? isPreparingHome,
    BangumiUser? user,
    List<UserCollection>? collections,
    bool? isRefreshing,
    bool? isLoadingCollections,
    bool? isUsingCachedCollections,
    DateTime? collectionsSavedAt,
    CollectionCoverage? collectionCoverage,
    bool clearCollectionsSavedAt = false,
    Set<int>? updatingSubjects,
    BangumiNetworkRoute? networkRoute,
    int? pendingSyncCount,
    int? blockedSyncCount,
    bool? isSyncing,
    String? message,
    bool clearMessage = false,
    bool clearUser = false,
    EpisodeUndo? episodeUndo,
    bool clearEpisodeUndo = false,
    EpisodeEdit? lastEpisodeEdit,
  }) => SessionState(
    phase: phase ?? this.phase,
    authActivity: authActivity ?? this.authActivity,
    canRetrySignIn: canRetrySignIn ?? this.canRetrySignIn,
    hasPendingVerification:
        hasPendingVerification ?? this.hasPendingVerification,
    canRetrySignOut: canRetrySignOut ?? this.canRetrySignOut,
    isPreparingHome: isPreparingHome ?? this.isPreparingHome,
    user: clearUser ? null : user ?? this.user,
    episodeUndo: clearEpisodeUndo ? null : episodeUndo ?? this.episodeUndo,
    lastEpisodeEdit: lastEpisodeEdit ?? this.lastEpisodeEdit,
    collections: collections ?? this.collections,
    collectionCoverage:
        collectionCoverage ??
        (collections == null
            ? this.collectionCoverage
            : this.collectionCoverage?.withCount(collections.length)),
    isRefreshing: isRefreshing ?? this.isRefreshing,
    isLoadingCollections: isLoadingCollections ?? this.isLoadingCollections,
    isUsingCachedCollections:
        isUsingCachedCollections ?? this.isUsingCachedCollections,
    collectionsSavedAt: clearCollectionsSavedAt
        ? null
        : collectionsSavedAt ?? this.collectionsSavedAt,
    updatingSubjects: updatingSubjects ?? this.updatingSubjects,
    networkRoute: networkRoute ?? this.networkRoute,
    pendingSyncCount: pendingSyncCount ?? this.pendingSyncCount,
    blockedSyncCount: blockedSyncCount ?? this.blockedSyncCount,
    isSyncing: isSyncing ?? this.isSyncing,
    message: clearMessage ? null : message ?? this.message,
  );
}
