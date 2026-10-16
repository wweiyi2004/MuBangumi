import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/storage/bangumi_sync_store.dart';
import 'package:mubangumi/features/collection/application/collection_edit_view.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/models/library_batch.dart';

import 'support/collection_module_fixtures.dart';
import 'support/library_batch_fixtures.dart';
import 'support/progress_fixtures.dart';

void main() {
  test(
    'episode and collection counts update immediately, then roll back only failed edits',
    () async {
      final gate = Completer<void>();
      final queue = _Queue()..saveGate = gate.future;
      final fixture = CollectionModuleFixture(queue: queue);
      addTearDown(fixture.dispose);
      final original = fixture.view.collections.single;
      final edit = fixture.editor.setEpisode(
        subjectId: 1,
        episodeId: 1,
        type: 2,
        previousType: 0,
        episode: progressEpisode(1),
      );
      await queue.started.future;
      expect(
        fixture.view.collections.single.episodeStatus,
        original.episodeStatus + 1,
      );
      expect(fixture.view.lastEpisodeEdit!.type, 2);
      expect(queue.items, isEmpty);
      expect(fixture.syncCalls, 0);
      queue.failingIds.add(1);
      gate.complete();
      expect(await edit, contains('save failed'));
      expect(
        fixture.view.collections.single.episodeStatus,
        original.episodeStatus,
      );
      expect(fixture.view.lastEpisodeEdit!.type, 0);
      expect(fixture.view.updatingSubjects, isEmpty);
      expect(fixture.syncCalls, 0);
    },
  );

  test(
    'an optimistic edit survives refreshes started both before and during persistence',
    () async {
      final queue = _Queue()..saveGate = Completer<void>().future;
      final gate = Completer<void>();
      queue.saveGate = gate.future;
      final fixture = CollectionModuleFixture(queue: queue);
      addTearDown(fixture.dispose);
      final original = fixture.view.collections.single;
      final edit = fixture.editor.changeCollection(
        original.subject,
        CollectionType.done,
        completeEpisodesWhenDone: false,
      );
      await queue.started.future;
      for (final revision in [0, fixture.editor.episodeRevision]) {
        final merged = fixture.editor.preserveCollectionsChangedAfter([
          original,
        ], revision);
        expect(merged.single.type, CollectionType.done);
      }
      gate.complete();
      expect(await edit, isNull);
      expect(fixture.view.collections, hasLength(1));
    },
  );

  test(
    'a failed earlier subject cannot remove another subject or its newer undo',
    () async {
      final gate = Completer<void>();
      final queue = _Queue()..saveGate = gate.future;
      final fixture = CollectionModuleFixture(queue: queue);
      addTearDown(fixture.dispose);
      fixture.view = fixture.view.copyWith(
        collections: [
          ...fixture.view.collections,
          batchFixtureCollection(2, type: SubjectType.anime),
        ],
      );
      final first = fixture.editor.setEpisode(
        subjectId: 1,
        episodeId: 1,
        type: 2,
        previousType: 0,
        episode: progressEpisode(1),
      );
      await queue.started.future;
      queue.saveGate = null;
      final second = fixture.editor.setEpisode(
        subjectId: 2,
        episodeId: 20,
        type: 2,
        previousType: 0,
        episode: progressEpisode(20),
      );
      expect(await second, isNull);
      final newerUndo = fixture.view.episodeUndo;
      queue.failingIds.add(1);
      gate.complete();
      expect(await first, contains('save failed'));
      expect(fixture.view.collectionFor(1)!.episodeStatus, 3);
      expect(fixture.view.collectionFor(2)!.episodeStatus, 4);
      expect(fixture.view.episodeUndo, same(newerUndo));
    },
  );

  test(
    'slow snapshot writes do not keep controls busy after a durable save',
    () async {
      final cache = _SlowWriteCache();
      final fixture = CollectionModuleFixture(cache: cache);
      addTearDown(fixture.dispose);
      final edit = fixture.editor.changeCollection(
        fixture.view.collections.single.subject,
        CollectionType.onHold,
      );
      await cache.started.future;
      expect(fixture.view.collections.single.type, CollectionType.onHold);
      expect(await edit.timeout(const Duration(milliseconds: 500)), isNull);
      expect(fixture.view.updatingSubjects, isEmpty);
      expect(fixture.queue.items, hasLength(1));
      cache.release.complete();
      await pumpEventQueue();
    },
  );

  test(
    'recently loaded chapters support consecutive next clicks without another network read',
    () async {
      final api = _ChapterApi();
      final fixture = CollectionModuleFixture(api: api);
      addTearDown(fixture.dispose);
      await fixture.editor.loadEpisodeCollections(1);
      expect(api.calls, 1);
      api.blockReads = true;
      for (var i = 0; i < 2; i++) {
        expect(
          await fixture.editor
              .markNextEpisode(fixture.view.collections.single)
              .timeout(const Duration(milliseconds: 500)),
          isNull,
        );
      }
      expect(api.calls, 1);
      expect(fixture.queue.items.map((item) => item.payload['episode_id']), [
        1,
        2,
      ]);
      expect(fixture.view.collections.single.episodeStatus, 2);
    },
  );
  test(
    'a complete reload removes deleted chapters from the fast next-episode snapshot',
    () async {
      final api = _ChapterApi();
      final fixture = CollectionModuleFixture(api: api);
      addTearDown(fixture.dispose);
      await fixture.editor.loadEpisodeCollections(1);
      api.removedFirst = true;
      await fixture.editor.loadEpisodeCollections(1);
      expect(
        await fixture.editor.markNextEpisode(fixture.view.collections.single),
        isNull,
      );
      expect(fixture.queue.items.single.payload['episode_id'], 2);
    },
  );

  test(
    'an SP-only read cannot be mistaken for a complete main-episode snapshot',
    () async {
      final api = _ChapterApi();
      final fixture = CollectionModuleFixture(api: api);
      addTearDown(fixture.dispose);
      await fixture.editor.loadEpisodeCollections(1, episodeType: 1);
      expect(
        await fixture.editor.markNextEpisode(fixture.view.collections.single),
        isNull,
      );
      expect(api.calls, 2);
      expect(fixture.queue.items.single.payload['episode_id'], 1);
    },
  );

  test(
    'new optimistic collections are not duplicated, and failed additions are removed',
    () async {
      final fixture = CollectionModuleFixture();
      addTearDown(fixture.dispose);
      final added = batchFixtureCollection(20, type: SubjectType.anime).subject;
      expect(
        await fixture.editor.changeCollection(added, CollectionType.wish),
        isNull,
      );
      expect(
        fixture.view.collections.where((item) => item.subjectId == 20),
        hasLength(1),
      );
      fixture.queue.failingIds.add(21);
      final rejected = batchFixtureCollection(
        21,
        type: SubjectType.anime,
      ).subject;
      expect(
        await fixture.editor.changeCollection(rejected, CollectionType.wish),
        contains('save failed'),
      );
      expect(
        fixture.view.collections.where((item) => item.subjectId == 21),
        isEmpty,
      );
      expect(
        fixture.view.collections.where((item) => item.subjectId == 20),
        hasLength(1),
      );
    },
  );

  test(
    'an edit updates the visible collection before durability and sync waits for the queue',
    () async {
      final gate = Completer<void>();
      final queue = _Queue()..saveGate = gate.future;
      final fixture = CollectionModuleFixture(queue: queue);
      addTearDown(fixture.dispose);
      final edit = fixture.editor.changeCollection(
        fixture.view.collections.single.subject,
        CollectionType.onHold,
        rate: 9,
      );
      await queue.started.future;
      expect(fixture.view.collections.single.type, CollectionType.onHold);
      expect(fixture.view.collections.single.rate, 9);
      expect(fixture.view.updatingSubjects, contains(1));
      expect(fixture.syncCalls, 0);
      gate.complete();
      expect(await edit, isNull);
      expect(queue.items.single.username, 'tester');
      expect(fixture.view.collections.single.type, CollectionType.onHold);
      expect(fixture.view.collections.single.rate, 9);
      expect(fixture.view.updatingSubjects, isEmpty);
      expect(fixture.syncCalls, 1);
    },
  );

  test(
    'old active and queued edits cannot change a replacement login',
    () async {
      final gate = Completer<void>();
      final queue = _Queue()..saveGate = gate.future;
      final fixture = CollectionModuleFixture(queue: queue);
      addTearDown(fixture.dispose);
      final subject = fixture.view.collections.single.subject;
      final first = fixture.editor.changeCollection(
        subject,
        CollectionType.onHold,
      );
      await queue.started.future;
      final second = fixture.editor.changeCollection(
        subject,
        CollectionType.wish,
      );
      fixture.account = const LibraryBatchAccount(
        userId: 2,
        username: 'replacement',
        generation: 2,
      );
      fixture.editor.reset();
      fixture.view = CollectionEditView(
        collections: [batchFixtureCollection(7, type: SubjectType.anime)],
      );
      gate.complete();
      expect(await first, contains('登录状态已变化'));
      expect(await second, contains('登录状态已变化'));
      expect(queue.calls, 1);
      expect(queue.items.single.username, 'tester');
      expect(fixture.view.collections.single.subjectId, 7);
      expect(fixture.editor.episodeRevision, 0);
      expect(fixture.syncCalls, 0);
    },
  );

  test(
    'failed persistence does not advance revisions or leave a busy indicator',
    () async {
      final fixture = CollectionModuleFixture(
        queue: MemoryBatchQueue()..failingIds.add(1),
      );
      addTearDown(fixture.dispose);
      final result = await fixture.editor.changeCollection(
        fixture.view.collections.single.subject,
        CollectionType.onHold,
      );
      expect(result, contains('save failed'));
      expect(fixture.view.collections.single.type, CollectionType.doing);
      expect(fixture.editor.collectionMutationRevision(1), 0);
      expect(fixture.view.updatingSubjects, isEmpty);
      expect(fixture.syncCalls, 0);
    },
  );

  test(
    'a blocked-queue result is discarded after the same account logs in again',
    () async {
      final queue = _Queue()
        ..blockedRead = Completer<List<PendingBangumiMutation>>();
      final fixture = CollectionModuleFixture(queue: queue);
      addTearDown(fixture.dispose);
      await queue.enqueue(
        username: 'tester',
        kind: BangumiMutationKind.collection,
        mutationKey: 'collection:1',
        payload: {'subject_id': 1},
      );
      final read = fixture.editor.blockedSyncMutations();
      fixture.account = const LibraryBatchAccount(
        userId: 1,
        username: 'tester',
        generation: 2,
      );
      queue.blockedRead!.complete(queue.items);
      expect(await read, isEmpty);
    },
  );
}

class _SlowWriteCache extends BatchTestCache {
  final started = Completer<void>();
  final release = Completer<void>();
  @override
  Future<void> writeCollections(
    String username,
    List<UserCollection> items,
  ) async {
    if (!started.isCompleted) started.complete();
    await release.future;
  }
}

class _ChapterApi extends BatchTestApi {
  _ChapterApi() : super([]);
  int calls = 0;
  bool blockReads = false;
  bool removedFirst = false;
  @override
  Future<List<UserEpisodeCollection>> getEpisodeCollections(
    int subjectId, {
    int? episodeType = 0,
  }) async {
    calls++;
    if (blockReads) return Completer<List<UserEpisodeCollection>>().future;
    if (episodeType == 1) {
      return [
        UserEpisodeCollection(
          episode: Episode.fromJson({'id': 99, 'type': 1, 'sort': 1}),
          type: 0,
          updatedAt: 0,
        ),
      ];
    }
    return [
      for (var i = removedFirst ? 2 : 1; i <= 4; i++)
        UserEpisodeCollection(
          episode: progressEpisode(i),
          type: 0,
          updatedAt: 0,
        ),
    ];
  }
}

class _Queue extends MemoryBatchQueue {
  final started = Completer<void>();
  Completer<List<PendingBangumiMutation>>? blockedRead;
  @override
  Future<void> enqueue({
    required String username,
    required BangumiMutationKind kind,
    required String mutationKey,
    required Map<String, dynamic> payload,
  }) {
    if (!started.isCompleted) started.complete();
    return super.enqueue(
      username: username,
      kind: kind,
      mutationKey: mutationKey,
      payload: payload,
    );
  }

  @override
  Future<List<PendingBangumiMutation>> blockedFor(String username) =>
      blockedRead?.future ?? super.blockedFor(username);
}
