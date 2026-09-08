import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/storage/snapshot_cache.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/core/storage/community_cache.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test(
    'chapter snapshots isolate accounts and never restore the old unscoped cache',
    () async {
      sqfliteFfiInit();
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await db.execute(
        'CREATE TABLE community_cache (cache_key TEXT PRIMARY KEY, payload TEXT, updated_at INTEGER, account_scoped INTEGER)',
      );
      final cache = CommunityCache.test(connection: db);
      final snapshots = SnapshotCache(cache: cache);
      addTearDown(() async {
        await cache.prune();
        await db.close();
      });
      const episode = UserEpisodeCollection(
        episode: Episode(
          id: 7,
          type: 0,
          number: 1,
          sort: 1,
          name: 'One',
          nameCn: '',
          airDate: '',
          description: '',
        ),
        type: 2,
        updatedAt: 0,
      );
      await snapshots.writeEpisodeCollections(99, [episode]);
      expect(
        await snapshots.readEpisodeCollections(99, username: 'alice'),
        isNull,
      );
      await snapshots.writeEpisodeCollections(99, [episode], username: 'alice');
      await snapshots.writeEpisodeCollections(99, [
        episode.copyWith(type: 0),
      ], username: 'bob');
      expect(
        (await snapshots.readEpisodeCollections(
          99,
          username: 'ALICE',
        ))!.single.type,
        2,
      );
      expect(
        (await snapshots.readEpisodeCollections(
          99,
          username: 'bob',
        ))!.single.type,
        0,
      );
      await snapshots.clearEpisodeCollections(99, username: 'alice');
      expect(
        await snapshots.readEpisodeCollections(99, username: 'alice'),
        isNull,
      );
      expect(
        (await snapshots.readEpisodeCollections(
          99,
          username: 'bob',
        ))!.single.type,
        0,
      );
    },
  );
  test('Subject/UserCollection snapshot round-trips through JSON', () {
    const subject = Subject(
      id: 12,
      name: 'Test',
      nameCn: '测试',
      imageUrl: 'https://example.com/a.jpg',
      summary: '简介',
      episodeCount: 12,
      score: 8.5,
      rank: 10,
      date: '2024-01-01',
      type: SubjectType.anime,
      tags: ['科幻'],
    );
    final collection = UserCollection(
      subjectId: 12,
      type: CollectionType.doing,
      rate: 8,
      episodeStatus: 3,
      updatedAt: DateTime.parse('2024-06-01T12:00:00Z'),
      subject: subject,
      comment: '好看',
      tags: ['追番'],
    );

    final restoredSubject = Subject.fromJson(subject.toJson());
    expect(restoredSubject.id, 12);
    expect(restoredSubject.displayName, '测试');
    expect(restoredSubject.episodeCount, 12);
    expect(restoredSubject.score, 8.5);
    expect(restoredSubject.tags, contains('科幻'));

    final restored = UserCollection.fromJson(collection.toJson());
    expect(restored.subjectId, 12);
    expect(restored.type, CollectionType.doing);
    expect(restored.rate, 8);
    expect(restored.episodeStatus, 3);
    expect(restored.comment, '好看');
    expect(restored.subject.displayName, '测试');
  });

  test('BangumiUser snapshot round-trips through JSON', () {
    const user = BangumiUser(
      id: 7,
      username: 'wweiyi',
      nickname: '维依',
      avatarUrl: 'https://lain.bgm.tv/pic/user/l/000/00/00/1.jpg',
      sign: 'hello',
    );

    final restored = BangumiUser.fromJson(user.toJson());
    expect(restored.id, 7);
    expect(restored.username, 'wweiyi');
    expect(restored.nickname, '维依');
    expect(restored.avatarUrl, contains('lain.bgm.tv'));
    expect(restored.sign, 'hello');
  });

  test('episode collection snapshot round-trips through JSON', () {
    const episode = UserEpisodeCollection(
      episode: Episode(
        id: 42,
        type: 0,
        number: 3,
        sort: 3,
        name: 'Episode 3',
        nameCn: '第三话',
        airDate: '2026-08-18',
        description: '简介',
      ),
      type: 2,
      updatedAt: 1770000000,
    );

    final restored = UserEpisodeCollection.fromJson(episode.toJson());
    expect(restored.episode.id, 42);
    expect(restored.episode.displayName, '第三话');
    expect(restored.type, 2);
    expect(restored.updatedAt, 1770000000);
  });

  test('discover browse cache keys are stable per filter', () {
    final a = SnapshotCache.discoverBrowseKey(
      type: SubjectType.anime,
      year: 2026,
      quarter: 2,
      sort: 'rank',
      supportsSeason: true,
    );
    final b = SnapshotCache.discoverBrowseKey(
      type: SubjectType.anime,
      year: 2026,
      quarter: 2,
      sort: 'rank',
      supportsSeason: true,
    );
    final c = SnapshotCache.discoverBrowseKey(
      type: SubjectType.anime,
      year: 2026,
      quarter: 1,
      sort: 'rank',
      supportsSeason: true,
    );
    expect(a, b);
    expect(a, isNot(c));
    expect(a, contains('discover_browse:'));
  });
}
