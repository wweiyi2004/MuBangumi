import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/network/community_service.dart';
import 'package:mubangumi/core/storage/community_cache.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('persisted friend statuses belong to their account and expire', () async {
    sqfliteFfiInit();
    final database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
    );
    addTearDown(database.close);
    await database.execute(
      'CREATE TABLE community_cache(cache_key TEXT PRIMARY KEY,payload TEXT NOT NULL,updated_at INTEGER NOT NULL,account_scoped INTEGER NOT NULL)',
    );
    final cache = CommunityCache.test(connection: database);
    final service = CommunityService(cache: cache)
      ..setAccessToken('synthetic')
      ..setCurrentUsername('alice');
    addTearDown(service.dispose);
    await service.cacheFriendStatus('bob', true);
    expect(await service.readCachedFriendStatus('bob'), isTrue);
    service.setCurrentUsername('charlie');
    expect(await service.readCachedFriendStatus('bob'), isNull);
    await cache.writeJson('community-v2:charlie:friend-status:bob', {
      'accepted': true,
      'checked_at': DateTime.now()
          .subtract(const Duration(minutes: 11))
          .toIso8601String(),
    }, accountScoped: true);
    expect(await service.readCachedFriendStatus('bob'), isNull);
  });
}
