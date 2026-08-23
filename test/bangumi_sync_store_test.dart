import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:mubangumi/core/storage/bangumi_sync_store.dart';

void main() {
  test('queue coalesces edits and protects newer revisions', () async {
    final directory = await Directory.systemTemp.createTemp(
      'mubangumi-sync-test-',
    );
    final store = BangumiSyncStore(
      databasePath: path.join(directory.path, 'sync.sqlite'),
    );
    addTearDown(() async {
      await store.close();
      await directory.delete(recursive: true);
    });

    await store.enqueue(
      username: 'tester',
      kind: BangumiMutationKind.collection,
      mutationKey: 'collection:8',
      payload: const {'subject_id': 8, 'rate': 1},
    );
    final firstRevision = (await store.pendingFor('tester')).single;

    await store.enqueue(
      username: 'tester',
      kind: BangumiMutationKind.collection,
      mutationKey: 'collection:8',
      payload: const {'subject_id': 8, 'rate': 9},
    );

    expect(await store.removeIfUnchanged(firstRevision), isFalse);
    final latest = await store.pendingFor('tester');
    expect(latest, hasLength(1));
    expect(latest.single.payload['rate'], 9);
    expect(latest.single.revision, firstRevision.revision + 1);

    expect(await store.removeIfUnchanged(latest.single), isTrue);
    expect(await store.countFor('tester'), 0);

    await store.enqueue(
      username: 'tester',
      kind: BangumiMutationKind.episode,
      mutationKey: 'episode:42',
      payload: const {'subject_id': 8, 'episode_id': 42, 'type': 2},
    );
    final rejected = (await store.pendingFor('tester')).single;
    expect(
      await store.markFailure(rejected, 'HTTP 400', blocked: true),
      isTrue,
    );
    expect(await store.pendingFor('tester'), isEmpty);
    expect(await store.blockedCountFor('tester'), 1);

    await store.retryBlocked('tester');
    expect(await store.pendingFor('tester'), hasLength(1));
  });
}
