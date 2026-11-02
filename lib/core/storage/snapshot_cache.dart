import '../../models/bangumi_models.dart';
import '../../models/collection_coverage.dart';
import '../../models/snapshot_items.dart';
export '../../models/snapshot_items.dart';
import 'community_cache.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';

CollectionSnapshot? _decodeCollections(String payload) {
  final value = jsonDecode(payload);
  if (value is! Map || value['items'] is! List) return null;
  final savedAt = DateTime.tryParse(value['saved_at']?.toString() ?? '');
  if (savedAt == null) return null;
  final items = [
    for (final item in value['items'] as List)
      if (item is Map) UserCollection.fromJson(Map<String, dynamic>.from(item)),
  ];
  return CollectionSnapshot(
    items,
    coverage: CollectionCoverage.fromJson(
      value['coverage'],
      loadedCount: items.length,
      savedAt: savedAt,
    ),
  );
}

typedef _CollectionWrite = ({
  List<UserCollection> items,
  int total,
  CollectionCoverage? coverage,
  String? previous,
  DateTime at,
});

String _encodeCollections(_CollectionWrite request) {
  CollectionCoverage? coverage = request.coverage;
  if (coverage == null && request.previous != null) {
    try {
      final old = jsonDecode(request.previous!) as Map;
      coverage = CollectionCoverage.fromJson(
        old['coverage'],
        loadedCount: (old['items'] as List?)?.length ?? 0,
      );
    } catch (_) {
      /* A malformed disposable snapshot can be replaced. */
    }
  }
  coverage ??= CollectionCoverage(loadedCount: request.total);
  return jsonEncode({
    'saved_at': request.at.toIso8601String(),
    'coverage': coverage
        .withCount(request.total)
        .retained(request.items.length, request.at)
        .toJson(),
    'items': [for (final item in request.items) item.toJson()],
  });
}

String? _invalidateCollection(({String payload, int subjectId}) request) {
  final snapshot = _decodeCollections(request.payload);
  final removed = snapshot
      ?.where((item) => item.subjectId == request.subjectId)
      .firstOrNull;
  if (snapshot == null || removed == null) return request.payload;
  final retained = snapshot
      .where((item) => item.subjectId != request.subjectId)
      .toList();
  if (retained.isEmpty) return null;
  return _encodeCollections((
    items: retained,
    total: retained.length,
    previous: null,
    at: DateTime.now(),
    coverage: CollectionCoverage(
      loadedCount: retained.length,
      sourceTotal: snapshot.coverage.sourceTotal,
      completeness: CollectionCompleteness.partial,
      loadedTypes: {...snapshot.coverage.loadedTypes}
        ..remove(removed.subject.type),
    ),
  ));
}

/// Timestamp travels with the exact read, including through concurrent reads.

/// Local snapshots remain readable regardless of age within the cache budget.
/// Account-scoped keys are still wiped by logout; timestamps describe local
/// snapshot saves, not confirmation that every queued edit reached the server.
class SnapshotCache {
  SnapshotCache({CommunityCache? cache})
    : _cache = cache ?? CommunityCache.shared;

  static final shared = SnapshotCache();

  final CommunityCache _cache;

  /// Max age for discover browse snapshots (7 days, same spirit as Shaft feeds).
  static const discoverMaxAge = Duration(days: 7);

  static const lastUserKey = 'session_last_user';
  static const accessCheckKey = 'session_access_check_pending';

  static String collectionsKey(String username) =>
      'collections_snapshot:${username.trim().toLowerCase()}';

  static String episodeCollectionsKey(int subjectId, {String? username}) =>
      'episode_collections_snapshot:${username == null ? '' : '${Uri.encodeComponent(username.trim().toLowerCase())}:'}$subjectId';

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

  static String pmFriendsKey(int userId) => 'pm_friends_snapshot:$userId';

  Future<List<BangumiUser>?> readPmFriends(int userId) async {
    if (userId <= 0) return null;
    final json = await _cache.readJson(pmFriendsKey(userId));
    if (json?['user_id'] != userId || json?['items'] is! List) return null;
    try {
      return [
        for (final item in json!['items'] as List)
          BangumiUser.fromJson(Map<String, dynamic>.from(item as Map)),
      ];
    } catch (_) {
      return null;
    }
  }

  Future<void> writePmFriends(int userId, List<BangumiUser> friends) async {
    if (userId <= 0) return;
    await _cache.writeJson(pmFriendsKey(userId), {
      'user_id': userId,
      'items': [for (final friend in friends) friend.toJson()],
    }, accountScoped: true);
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

  /// The first-login access check must survive an app restart until passed.
  Future<bool> readAccessCheckPending(int userId) async {
    final json = await _cache.readJson(accessCheckKey);
    return json?['userId'] == userId;
  }

  Future<void> writeAccessCheckPending(int? userId) async {
    if (userId == null) {
      await _cache.remove(accessCheckKey);
      return;
    }
    await _cache.writeJson(accessCheckKey, {
      'userId': userId,
    }, accountScoped: true);
  }

  Future<List<UserCollection>?> readCollections(String username) =>
      _cache.readDecoded(collectionsKey(username), _decodeCollections);

  Future<void> writeCollections(
    String username,
    List<UserCollection> collections,
  ) {
    if (username.trim().isEmpty) return Future.value();
    // Cap payload size roughly like Shaft's MAX_PAYLOAD guard.
    final items = collections.take(4000).toList(growable: false);
    final total = collections.length;
    final coverage = collections is CollectionSnapshot
        ? collections.coverage
        : null;
    final savedAt = DateTime.now();
    final large =
        items.length >= 100 ||
        items.fold<int>(
              0,
              (size, item) =>
                  size +
                  item.subject.summary.length +
                  item.comment.length +
                  item.subject.name.length +
                  item.subject.nameCn.length,
            ) >=
            64 * 1024;
    return _cache.updateEncoded(
      collectionsKey(username),
      (previous) async {
        final request = (
          items: items,
          total: total,
          coverage: coverage,
          previous: previous,
          at: savedAt,
        );
        return large || (previous?.length ?? 0) >= 64 * 1024
            ? compute(
                _encodeCollections,
                request,
                debugLabel: 'cache.collections.encode',
              )
            : _encodeCollections(request);
      },
      readExisting: coverage == null,
      accountScoped: true,
    );
  }

  Future<void> clearCollections(String username) async {
    if (username.trim().isEmpty) return;
    await _cache.remove(collectionsKey(username));
  }

  /// Invalidate only the subject whose optimistic edit was discarded. Other
  /// collections must remain available if the following refresh is offline.
  Future<void> invalidateCollection(String username, int subjectId) =>
      _cache.updateEncoded(
        collectionsKey(username),
        (payload) async {
          if (payload == null) return null;
          final request = (payload: payload, subjectId: subjectId);
          return payload.length >= 64 * 1024
              ? compute(_invalidateCollection, request)
              : _invalidateCollection(request);
        },
        readExisting: true,
        accountScoped: true,
      );

  Future<void> clearUserScope(String username) async {
    await clearCollections(username);
    await _cache.removePrefix(
      'episode_collections_snapshot:${Uri.encodeComponent(username.trim().toLowerCase())}:',
    );
  }

  Future<List<UserEpisodeCollection>?> readEpisodeCollections(
    int subjectId, {
    String? username,
  }) async {
    final json = await _cache.readJson(
      episodeCollectionsKey(subjectId, username: username),
    );
    if (json == null) return null;
    final savedAt = DateTime.tryParse(json['saved_at']?.toString() ?? '');
    if (savedAt == null) return null;
    final items = json['items'];
    if (items is! List || items.isEmpty) return null;
    try {
      return SnapshotItems([
        for (final item in items)
          if (item is Map)
            UserEpisodeCollection.fromJson(Map<String, dynamic>.from(item)),
      ], savedAt: savedAt);
    } catch (_) {
      return null;
    }
  }

  Future<void> writeEpisodeCollections(
    int subjectId,
    List<UserEpisodeCollection> episodes, {
    String? username,
  }) async {
    if (subjectId <= 0 || episodes.isEmpty) return;
    await _cache.writeJson(
      episodeCollectionsKey(subjectId, username: username),
      {
        'saved_at': DateTime.now().toIso8601String(),
        'items': [for (final item in episodes) item.toJson()],
      },
      accountScoped: true,
    );
  }

  Future<void> clearEpisodeCollections(
    int subjectId, {
    String? username,
  }) async {
    if (subjectId <= 0) return;
    await _cache.remove(episodeCollectionsKey(subjectId, username: username));
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
    await _cache.writeJson(key, {
      'saved_at': DateTime.now().toIso8601String(),
      'items': [for (final item in subjects.take(48)) item.toJson()],
    });
  }
}
