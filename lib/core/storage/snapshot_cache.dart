import '../../models/bangumi_models.dart';
import 'community_cache.dart';

/// Local-first snapshots for list UIs (inspired by Pixiv-Shaft feed first page).
///
/// Only stores small JSON payloads via [CommunityCache]. Network refresh stays
/// authoritative; cache is best-effort for cold-start / tab reopen smoothness.
/// Account-scoped keys are wiped by [CommunityCache.clearAccountData] on logout.
class SnapshotCache {
  SnapshotCache({CommunityCache? cache})
    : _cache = cache ?? CommunityCache.shared;

  static final shared = SnapshotCache();

  final CommunityCache _cache;

  /// Max age for discover browse snapshots (7 days, same spirit as Shaft feeds).
  static const discoverMaxAge = Duration(days: 7);

  /// Collections can be older; still better than an empty library on cold start.
  static const collectionsMaxAge = Duration(days: 30);

  static const episodeCollectionsMaxAge = Duration(days: 30);

  static const lastUserKey = 'session_last_user';

  static String collectionsKey(String username) =>
      'collections_snapshot:${username.trim().toLowerCase()}';

  static String episodeCollectionsKey(int subjectId) =>
      'episode_collections_snapshot:$subjectId';

  static String discoverBrowseKey({
    required SubjectType type,
    required int year,
    required int quarter,
    required String sort,
    required bool supportsSeason,
  }) {
    final seasonPart = supportsSeason ? 'q$quarter' : 'y';
    return 'discover_browse:${type.value}:$year:$seasonPart:$sort';
  }

  Future<BangumiUser?> readLastUser() async {
    final json = await _cache.readJson(lastUserKey);
    final user = json?['user'];
    if (user is! Map) return null;
    try {
      final parsed = BangumiUser.fromJson(Map<String, dynamic>.from(user));
      if (parsed.username.trim().isEmpty) return null;
      return parsed;
    } catch (_) {
      return null;
    }
  }

  Future<void> writeLastUser(BangumiUser user) async {
    if (user.username.trim().isEmpty) return;
    await _cache.writeJson(lastUserKey, {
      'user': user.toJson(),
    }, accountScoped: true);
  }

  Future<void> clearLastUser() async {
    await _cache.remove(lastUserKey);
  }

  Future<List<UserCollection>?> readCollections(String username) async {
    final json = await _cache.readJson(collectionsKey(username));
    if (json == null) return null;
    final savedAt = DateTime.tryParse(json['saved_at']?.toString() ?? '');
    if (savedAt == null ||
        DateTime.now().difference(savedAt) > collectionsMaxAge) {
      return null;
    }
    final items = json['items'];
    if (items is! List || items.isEmpty) return null;
    try {
      return [
        for (final item in items)
          if (item is Map)
            UserCollection.fromJson(Map<String, dynamic>.from(item)),
      ];
    } catch (_) {
      return null;
    }
  }

  Future<void> writeCollections(
    String username,
    List<UserCollection> collections,
  ) async {
    if (username.trim().isEmpty) return;
    // Cap payload size roughly like Shaft's MAX_PAYLOAD guard.
    final items = collections.length > 4000
        ? collections.take(4000).toList()
        : collections;
    await _cache.writeJson(collectionsKey(username), {
      'saved_at': DateTime.now().toIso8601String(),
      'items': [for (final item in items) item.toJson()],
    }, accountScoped: true);
  }

  Future<List<UserEpisodeCollection>?> readEpisodeCollections(
    int subjectId,
  ) async {
    final json = await _cache.readJson(episodeCollectionsKey(subjectId));
    if (json == null) return null;
    final savedAt = DateTime.tryParse(json['saved_at']?.toString() ?? '');
    if (savedAt == null ||
        DateTime.now().difference(savedAt) > episodeCollectionsMaxAge) {
      return null;
    }
    final items = json['items'];
    if (items is! List || items.isEmpty) return null;
    try {
      return [
        for (final item in items)
          if (item is Map)
            UserEpisodeCollection.fromJson(Map<String, dynamic>.from(item)),
      ];
    } catch (_) {
      return null;
    }
  }

  Future<void> writeEpisodeCollections(
    int subjectId,
    List<UserEpisodeCollection> episodes,
  ) async {
    if (subjectId <= 0 || episodes.isEmpty) return;
    await _cache.writeJson(episodeCollectionsKey(subjectId), {
      'saved_at': DateTime.now().toIso8601String(),
      'items': [for (final item in episodes) item.toJson()],
    }, accountScoped: true);
  }

  Future<List<Subject>?> readDiscoverBrowse(String key) async {
    final json = await _cache.readJson(key);
    if (json == null) return null;
    final savedAt = DateTime.tryParse(json['saved_at']?.toString() ?? '');
    if (savedAt == null ||
        DateTime.now().difference(savedAt) > discoverMaxAge) {
      return null;
    }
    final items = json['items'];
    if (items is! List || items.isEmpty) return null;
    try {
      return [
        for (final item in items)
          if (item is Map) Subject.fromJson(Map<String, dynamic>.from(item)),
      ];
    } catch (_) {
      return null;
    }
  }

  Future<void> writeDiscoverBrowse(String key, List<Subject> subjects) async {
    if (subjects.isEmpty) return;
    await _cache.writeJson(key, {
      'saved_at': DateTime.now().toIso8601String(),
      'items': [for (final item in subjects.take(48)) item.toJson()],
    });
  }
}
