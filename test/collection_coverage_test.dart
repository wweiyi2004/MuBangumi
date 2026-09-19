import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mubangumi/core/storage/community_cache.dart';
import 'package:mubangumi/core/storage/snapshot_cache.dart';
import 'package:mubangumi/models/collection_coverage.dart';
import 'package:mubangumi/models/bangumi_models.dart';

void main() {
  sqfliteFfiInit();
  late Database db;
  late CommunityCache cache;
  late SnapshotCache snapshots;
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute(
      'CREATE TABLE community_cache(cache_key TEXT PRIMARY KEY,payload TEXT NOT NULL,updated_at INTEGER NOT NULL,account_scoped INTEGER NOT NULL)',
    );
    cache = CommunityCache.test(connection: db);
    snapshots = SnapshotCache(cache: cache);
  });
  tearDown(() async {
    await cache.prune();
    await db.close();
  });
  UserCollection item(int id) => UserCollection(
    subjectId: id,
    type: CollectionType.done,
    rate: 8,
    episodeStatus: 0,
    updatedAt: null,
    subject: Subject(
      id: id,
      name: '作品$id',
      nameCn: '',
      imageUrl: '',
      summary: '',
      episodeCount: 0,
      score: 0,
      rank: 0,
      date: '',
    ),
  );
  test('bounded cache retains source totals and marks partial data', () async {
    final items = [for (var i = 0; i < 4005; i++) item(i + 1)];
    await snapshots.writeCollections(
      'reader',
      CollectionSnapshot(
        items,
        coverage: CollectionCoverage(
          loadedCount: items.length,
          sourceTotal: items.length,
          completeness: CollectionCompleteness.complete,
          loadedTypes: SubjectType.values.toSet(),
        ),
      ),
    );
    final saved =
        (await snapshots.readCollections('reader'))! as CollectionSnapshot;
    expect(saved, hasLength(4000));
    expect(saved.coverage.sourceTotal, 4005);
    expect(saved.coverage.isComplete, false);
    expect(saved.coverage.notice, contains('4000 / 4005'));
    await snapshots.writeCollections('reader', saved.toList());
    expect(
      ((await snapshots.readCollections('reader'))! as CollectionSnapshot)
          .coverage
          .sourceTotal,
      4005,
    );
  });
  test(
    'legacy snapshots stay unknown and empty complete snapshots remain valid',
    () async {
      await cache.writeJson(SnapshotCache.collectionsKey('legacy'), {
        'saved_at': DateTime.now().toIso8601String(),
        'items': [item(1).toJson()],
      });
      expect(
        ((await snapshots.readCollections('legacy'))! as CollectionSnapshot)
            .coverage
            .completeness,
        CollectionCompleteness.unknown,
      );
      await snapshots.writeCollections(
        'empty',
        CollectionSnapshot(
          [],
          coverage: CollectionCoverage(
            loadedCount: 0,
            sourceTotal: 0,
            completeness: CollectionCompleteness.complete,
            loadedTypes: SubjectType.values.toSet(),
          ),
        ),
      );
      final empty =
          (await snapshots.readCollections('empty'))! as CollectionSnapshot;
      expect(empty, isEmpty);
      expect(empty.coverage.isComplete, true);
    },
  );
}
