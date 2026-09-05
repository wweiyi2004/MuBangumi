import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mubangumi/core/storage/community_cache.dart';

void main() {
  late Database db;
  late CommunityCache cache;
  final now = DateTime(2026, 9, 5);
  setUp(() async {
    sqfliteFfiInit();
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute(
      'CREATE TABLE community_cache (cache_key TEXT PRIMARY KEY, payload TEXT, updated_at INTEGER, account_scoped INTEGER)',
    );
    cache = CommunityCache.test(connection: db, now: () => now);
  });
  tearDown(() async {
    await cache.prune();
    await db.close();
  });

  Future<void> seed(String key, {int daysOld = 0}) => db
      .insert('community_cache', {
        'cache_key': key,
        'payload': '{"ok":true}',
        'updated_at': now
            .subtract(Duration(days: daysOld))
            .millisecondsSinceEpoch,
        'account_scoped': key == 'session_last_user' ? 1 : 0,
      })
      .then((_) {});

  test(
    'prunes expired snapshots but preserves session identity and other tables',
    () async {
      await seed('old', daysOld: 31);
      await seed('fresh');
      await seed('session_last_user', daysOld: 90);
      await db.execute('CREATE TABLE pending_changes (id INTEGER)');
      await db.insert('pending_changes', {'id': 1});
      await cache.prune();
      expect(await cache.readJson('old'), isNull);
      expect(await cache.readJson('fresh'), isNotNull);
      expect(await cache.readJson('session_last_user'), isNotNull);
      expect(await db.query('pending_changes'), hasLength(1));
      await cache.clearAccountData();
      expect(await cache.readJson('session_last_user'), isNull);
    },
  );

  test('caps retained entries and payload size', () async {
    final batch = db.batch();
    for (var i = 0; i < CommunityCache.maxEntries + 3; i++) {
      batch.insert('community_cache', {
        'cache_key': 'item:$i',
        'payload': '{}',
        'updated_at': now.millisecondsSinceEpoch + i,
        'account_scoped': 0,
      });
    }
    await batch.commit(noResult: true);
    await cache.prune();
    expect(
      await db.query('community_cache', columns: ['cache_key']),
      hasLength(CommunityCache.maxEntries),
    );
    expect(await cache.readJson('item:0'), isNull);
    // Generate an oversized BLOB in SQLite without materializing it in Dart.
    await db.rawInsert(
      'INSERT INTO community_cache VALUES (?, zeroblob(?), ?, 0)',
      [
        'oversized',
        CommunityCache.maxPayloadBytes + 1,
        now.millisecondsSinceEpoch + 9999,
      ],
    );
    await cache.prune();
    expect(
      await db.query(
        'community_cache',
        where: 'cache_key = ?',
        whereArgs: ['oversized'],
      ),
      isEmpty,
    );
    expect(await cache.readJson('item:2002'), isNotNull);
  });
}
