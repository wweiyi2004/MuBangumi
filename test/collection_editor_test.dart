import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/storage/bangumi_sync_store.dart';
import 'package:mubangumi/features/collection/application/collection_edit_view.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/models/library_batch.dart';

import 'support/collection_module_fixtures.dart';
import 'support/library_batch_fixtures.dart';

void main() {
  test(
    'an edit changes the visible collection only after its queue entry is durable',
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
      expect(fixture.view.collections.single.type, CollectionType.doing);
      expect(fixture.view.collections.single.rate, 8);
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
