import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/network/bangumi_api.dart';
import 'package:mubangumi/core/network/rss_fetcher.dart';
import 'package:mubangumi/core/storage/bangumi_sync_store.dart';
import 'package:mubangumi/core/storage/community_cache.dart';
import 'package:mubangumi/core/storage/rss_store.dart';
import 'package:mubangumi/core/storage/snapshot_cache.dart';
import 'package:mubangumi/features/collection/application/collection_edit_view.dart';
import 'package:mubangumi/features/collection/application/collection_editor.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/models/library_batch.dart';
import 'package:mubangumi/models/collection_coverage.dart';
import 'package:mubangumi/models/rss_models.dart';
import 'package:mubangumi/state/rss_controller.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/library_batch_fixtures.dart';

// Regressions for the three data-consistency findings from the 2026-09-22 audit.
void main() {
  test('audit F1: mark-next preserves cached special episodes', () async {
    final snapshots = await snapshotFixture();
    final api = FilteredEpisodesApi();
    final harness = EditorHarness(snapshots, api);
    addTearDown(harness.editor.dispose);
    final all = await harness.editor.loadEpisodeCollections(1);
    expect(all.map((e) => e.episode.id), [101, 102, 103]);
    expect(
      await harness.editor.markNextEpisode(harness.view.collections.first),
      isNull,
    );
    final offline = await snapshots.readEpisodeCollections(
      1,
      username: 'tester',
    );
    expect(
      offline!.map((e) => e.episode.id),
      containsAll([101, 102, 103]),
      reason:
          'An online main-episode progress edit must retain previously cached SP/OP data.',
    );
    expect(offline.where((e) => e.episode.type != 0).map((e) => e.type), [
      2,
      2,
    ]);
  });

  test(
    'audit F2: unbinding during RSS fetch rejects late matched items',
    () async {
      final store = RssStore.test(databasePath: ':memory:');
      addTearDown(store.close);
      final source = await store.upsertSource(
        const RssSource(id: 0, name: 'audit', url: 'https://example.test/rss'),
      );
      final binding = await store.upsertBinding(
        RssBinding(
          id: 0,
          sourceId: source.id,
          subjectId: 42,
          subjectName: 'Anime',
          matchKeywords: 'Anime',
        ),
      );
      final fetcher = DelayedFeed();
      final controller = RssController(store, fetcher);
      addTearDown(controller.dispose);
      await controller.reload();
      final refresh = controller.refreshAll();
      await fetcher.started.future;
      await controller.unbind(binding.id);
      expect(await store.listBindings(), isEmpty);
      fetcher.response.complete(
        const RssFetchResult(
          entries: [
            RssFeedEntry(
              guid: 'late',
              title: 'Anime 01',
              link: 'https://example.test/1',
            ),
          ],
        ),
      );
      await refresh;
      expect(
        await store.totalUnread(),
        0,
        reason:
            'A completed unbind must prevent new reminders from the old in-flight binding.',
      );
    },
  );

  test(
    'audit F3: discarding one failed edit preserves other offline collections',
    () async {
      final snapshots = await snapshotFixture();
      final queue = BangumiSyncStore(databasePath: ':memory:');
      addTearDown(queue.close);
      final harness = EditorHarness(
        snapshots,
        FilteredEpisodesApi(),
        queue: queue,
      );
      addTearDown(harness.editor.dispose);
      harness.view = CollectionEditView(
        collections: [
          batchFixtureCollection(1, type: SubjectType.anime),
          batchFixtureCollection(2, type: SubjectType.book),
        ],
      );
      await snapshots.writeCollections('tester', harness.view.collections);
      expect((await snapshots.readCollections('tester'))!.length, 2);
      await queue.enqueue(
        username: 'tester',
        kind: BangumiMutationKind.episode,
        mutationKey: 'episode:101',
        payload: {'subject_id': 1, 'episode_id': 101, 'type': 2},
      );
      final pending = (await queue.pendingFor('tester')).single;
      await queue.markFailure(pending, 'server rejected', blocked: true);
      final blocked = (await queue.blockedFor('tester')).single;
      expect(await harness.editor.discardBlockedMutation(blocked), isNull);
      expect(await queue.countFor('tester'), 0);
      final restored = await snapshots.readCollections('tester');
      expect(
        restored?.map((item) => item.subjectId),
        contains(2),
        reason:
            'Stopping one upload must not remove the unrelated book from cold-start offline storage.',
      );
      expect(restored, isA<CollectionSnapshot>());
      expect((restored as CollectionSnapshot).coverage.isComplete, false);
      expect(restored.map((item) => item.subjectId), isNot(contains(1)));
    },
  );
}

Future<SnapshotCache> snapshotFixture() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(singleInstance: false),
  );
  await db.execute(
    'CREATE TABLE community_cache (cache_key TEXT PRIMARY KEY, payload TEXT, updated_at INTEGER, account_scoped INTEGER)',
  );
  final cache = CommunityCache.test(connection: db);
  addTearDown(() async {
    await cache.prune();
    await db.close();
  });
  return SnapshotCache(cache: cache);
}

class EditorHarness {
  EditorHarness(
    SnapshotCache snapshots,
    BangumiApi api, {
    BangumiSyncStore? queue,
  }) {
    final store = queue ?? MemoryBatchQueue();
    editor = CollectionEditor(
      api: api,
      snapshotCache: snapshots,
      syncStore: store,
      readAccount: () => const LibraryBatchAccount(
        userId: 1,
        username: 'tester',
        generation: 1,
      ),
      readView: () => view,
      writeView: (next) => view = next,
      isAlive: () => true,
      syncPendingChanges: () async {},
      refreshPendingCount: (username) => store.countFor(username ?? ''),
      messageFor: (error) => error.toString(),
    );
  }
  CollectionEditView view = CollectionEditView(
    collections: [batchFixtureCollection(1, type: SubjectType.anime)],
  );
  late final CollectionEditor editor;
}

class FilteredEpisodesApi extends BangumiApi {
  @override
  Future<List<UserEpisodeCollection>> getEpisodeCollections(
    int subjectId, {
    int? episodeType = 0,
  }) async => [
    for (var index = 0; index < 3; index++)
      if (episodeType == null || episodeType == index)
        UserEpisodeCollection(
          episode: Episode(
            id: 101 + index,
            type: index,
            number: 1,
            sort: 1,
            name: 'episode-$index',
            nameCn: '',
            airDate: '',
            description: '',
          ),
          type: index == 0 ? 0 : 2,
          updatedAt: 0,
        ),
  ];
}

class DelayedFeed extends RssFetcher {
  final started = Completer<void>();
  final response = Completer<RssFetchResult>();
  @override
  Future<RssFetchResult> fetch(
    String url, {
    String etag = '',
    String lastModified = '',
  }) {
    started.complete();
    return response.future;
  }
}
