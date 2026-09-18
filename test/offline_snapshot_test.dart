import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/storage/community_cache.dart';
import 'package:mubangumi/core/storage/snapshot_cache.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/progress_fixtures.dart';

void main() {
  late Database db;
  late CommunityCache cache;
  late SnapshotCache snapshots;
  final old = DateTime.now().subtract(const Duration(days: 120));
  setUp(() async {
    sqfliteFfiInit();
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute(
      'CREATE TABLE community_cache (cache_key TEXT PRIMARY KEY, payload TEXT, updated_at INTEGER, account_scoped INTEGER)',
    );
    cache = CommunityCache.test(connection: db);
    snapshots = SnapshotCache(cache: cache);
  });
  tearDown(() async {
    await cache.prune();
    await db.close();
  });

  Future<void> seed(
    String key,
    List<Object> items, {
    bool personal = true,
  }) async {
    await db.insert('community_cache', {
      'cache_key': key,
      'payload': jsonEncode({
        'saved_at': old.toIso8601String(),
        'items': items,
      }),
      'updated_at': old.millisecondsSinceEpoch,
      'account_scoped': personal ? 1 : 0,
    });
  }

  test(
    'old personal snapshots survive pruning with their original timestamp',
    () async {
      await seed(SnapshotCache.collectionsKey('alice'), [
        progressCollection(1).toJson(),
      ]);
      await seed(SnapshotCache.episodeCollectionsKey(1, username: 'alice'), [
        UserEpisodeCollection(
          episode: progressEpisode(1),
          type: 2,
          updatedAt: 0,
        ).toJson(),
      ]);
      await seed('discover_browse:old', [], personal: false);
      await cache.prune();
      final collections = await snapshots.readCollections('alice');
      final episodes = await snapshots.readEpisodeCollections(
        1,
        username: 'alice',
      );
      expect(collections!.single.subjectId, 1);
      expect((collections as SnapshotItems<UserCollection>).savedAt, old);
      expect(episodes!.single.type, 2);
      expect((episodes as SnapshotItems<UserEpisodeCollection>).savedAt, old);
      expect(await cache.readJson('discover_browse:old'), isNull);
      expect(await snapshots.readCollections('bob'), isNull);
      await cache.clearAccountData();
      expect(await snapshots.readCollections('alice'), isNull);
      expect(
        await snapshots.readEpisodeCollections(1, username: 'alice'),
        isNull,
      );
    },
  );

  test(
    'capacity remains bounded while personal snapshots get priority',
    () async {
      final key = SnapshotCache.collectionsKey('alice');
      await seed(key, [progressCollection(1).toJson()]);
      final batch = db.batch();
      for (var i = 0; i < CommunityCache.maxEntries + 2; i++) {
        batch.insert('community_cache', {
          'cache_key': 'public:$i',
          'payload': '{}',
          'updated_at': DateTime.now().millisecondsSinceEpoch,
          'account_scoped': 0,
        });
      }
      await batch.commit(noResult: true);
      await cache.prune();
      expect(await snapshots.readCollections('alice'), isNotNull);
      expect(
        await db.query('community_cache'),
        hasLength(CommunityCache.maxEntries),
      );
    },
  );
}
