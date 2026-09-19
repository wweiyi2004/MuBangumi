import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mubangumi/core/storage/community_cache.dart';
import 'package:mubangumi/core/network/community_service.dart';
import 'package:mubangumi/models/community_models.dart';

void main() {
  test('namespace migration discards only unowned community snapshots', () async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    try {
      await db.execute(
        'CREATE TABLE community_cache(cache_key TEXT PRIMARY KEY,payload TEXT)',
      );
      for (final key in [
        'timeline:me',
        'topics:friends',
        'groups:joined',
        'group:private',
        'collections_snapshot:alice',
        'community-v2:bob:timeline:me',
      ]) {
        await db.insert('community_cache', {'cache_key': key, 'payload': '{}'});
      }
      await discardUnscopedCommunitySnapshots(db);
      expect(
        (await db.query('community_cache')).map((r) => r['cache_key']).toSet(),
        {'collections_snapshot:alice', 'community-v2:bob:timeline:me'},
      );
    } finally {
      await db.close();
    }
  });
  test(
    'community snapshot namespaces cannot overwrite or clear another account',
    () async {
      sqfliteFfiInit();
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await db.execute(
        'CREATE TABLE community_cache(cache_key TEXT PRIMARY KEY,payload TEXT NOT NULL,updated_at INTEGER NOT NULL,account_scoped INTEGER NOT NULL)',
      );
      final cache = CommunityCache.test(connection: db);
      CommunityService service(String name, int total) {
        final dio = Dio()
          ..interceptors.add(
            InterceptorsWrapper(
              onRequest: (r, h) => h.resolve(
                Response(
                  requestOptions: r,
                  data: {'data': [], 'total': total},
                  statusCode: 200,
                ),
              ),
            ),
          );
        return CommunityService.test(p1Dio: dio, cache: cache)
          ..setAccessToken('token-$name')
          ..setCurrentUsername(name);
      }

      final alice = service('alice', 11), bob = service('bob', 22);
      try {
        await alice.loadGroupPage();
        await bob.loadGroupPage();
        expect(
          (await alice.readCachedGroups(
            CommunityGroupMode.all,
            CommunityGroupSort.members,
          ))!.total,
          11,
        );
        expect(
          (await bob.readCachedGroups(
            CommunityGroupMode.all,
            CommunityGroupSort.members,
          ))!.total,
          22,
        );
        await alice.clearAccountCache();
        expect(
          await alice.readCachedGroups(
            CommunityGroupMode.all,
            CommunityGroupSort.members,
          ),
          null,
        );
        expect(
          (await bob.readCachedGroups(
            CommunityGroupMode.all,
            CommunityGroupSort.members,
          ))!.total,
          22,
        );
      } finally {
        alice.dispose();
        bob.dispose();
        await cache.prune();
        await db.close();
      }
    },
  );
}
