import 'dart:async';
import 'dart:isolate';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mubangumi/core/storage/community_cache.dart';
import 'package:mubangumi/core/storage/snapshot_cache.dart';
import 'package:mubangumi/models/bangumi_models.dart';

String? decoderIsolate(String _) => Isolate.current.debugName;
UserCollection item(int id) => UserCollection(
  subjectId: id,
  type: CollectionType.done,
  rate: 8,
  episodeStatus: 12,
  updatedAt: DateTime(2025),
  subject: Subject(
    id: id,
    name: 'fixture$id',
    nameCn: '',
    imageUrl: '',
    summary: '',
    episodeCount: 12,
    score: 8,
    rank: 1,
    date: '2025-01-01',
  ),
  comment: 'private note',
  private: true,
);

void main() {
  sqfliteFfiInit();
  late Database db;
  late CommunityCache cache;
  late SnapshotCache snapshots;
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute(
      'CREATE TABLE community_cache(cache_key TEXT PRIMARY KEY,payload TEXT,updated_at INTEGER,account_scoped INTEGER)',
    );
    cache = CommunityCache.test(connection: db);
    snapshots = SnapshotCache(cache: cache);
  });
  tearDown(() async {
    await cache.prune();
    await db.close();
  });

  test('large payload decoding runs in a worker isolate', () async {
    await cache.writeJson('large', {'body': List.filled(70000, 'x').join()});
    expect(await cache.readDecoded('large', decoderIsolate), 'cache.decode');
    await cache.writeJson('small', {'body': 'x'});
    expect(
      await cache.readDecoded('small', decoderIsolate),
      Isolate.current.debugName,
    );
  });
  test(
    'account clearing waits for in-flight encoding and preserves the next account',
    () async {
      final started = Completer<void>(), gate = Completer<String?>();
      await cache.writeJson('public', {'ok': true});
      final oldWrite = cache.updateEncoded('alice', (_) {
        started.complete();
        return gate.future;
      }, accountScoped: true);
      await started.future;
      final clearing = cache.clearAccountData();
      final nextWrite = cache.writeJson('bob', {
        'ok': true,
      }, accountScoped: true);
      gate.complete('{"old":true}');
      await Future.wait([oldWrite, clearing, nextWrite]);
      expect(await cache.readJson('alice'), isNull);
      expect(await cache.readJson('bob'), {'ok': true});
      expect(await cache.readJson('public'), {'ok': true});
    },
  );
  test(
    'parallel invalidations cannot restore a previously removed collection',
    () async {
      await snapshots.writeCollections('alice', [
        for (var i = 1; i <= 1200; i++) item(i),
      ]);
      await Future.wait([
        snapshots.invalidateCollection('alice', 1),
        snapshots.invalidateCollection('alice', 2),
      ]);
      final restored = (await snapshots.readCollections('alice'))!;
      expect(restored, hasLength(1198));
      expect(restored.any((row) => row.subjectId <= 2), isFalse);
      expect(restored.first.private, isTrue);
      expect(restored.first.comment, 'private note');
    },
  );
  test(
    'collection write captures its list and clears safely during background encoding',
    () async {
      final values = [for (var i = 1; i <= 1200; i++) item(i)];
      final pending = snapshots.writeCollections('alice', values);
      values.clear();
      await pending;
      expect(await snapshots.readCollections('alice'), hasLength(1200));
      final writing = snapshots.writeCollections('alice', [
        for (var i = 1; i <= 1200; i++) item(i),
      ]);
      final clearing = snapshots.clearCollections('alice');
      await Future.wait([writing, clearing]);
      expect(await snapshots.readCollections('alice'), isNull);
    },
  );
}
