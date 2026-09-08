import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:mubangumi/core/storage/bangumi_sync_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test(
    'upgrading the queue preserves payloads and orders old coalesced edits by last update',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'mubangumi-sync-migration-',
      );
      final filename = path.join(directory.path, 'sync.sqlite');
      final store = BangumiSyncStore(databasePath: filename);
      addTearDown(() async {
        await store.close();
        if (directory.parent.resolveSymbolicLinksSync() !=
                Directory.systemTemp.resolveSymbolicLinksSync() ||
            !path
                .basename(directory.path)
                .startsWith('mubangumi-sync-migration-')) {
          throw StateError('Unexpected test directory');
        }
        await directory.delete(recursive: true);
      });
      sqfliteFfiInit();
      final old = await databaseFactoryFfi.openDatabase(
        filename,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) async {
            await db.execute(
              'CREATE TABLE bangumi_sync_queue (id INTEGER PRIMARY KEY AUTOINCREMENT, username TEXT NOT NULL, mutation_key TEXT NOT NULL, kind TEXT NOT NULL, payload TEXT NOT NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, attempts INTEGER NOT NULL DEFAULT 0, revision INTEGER NOT NULL DEFAULT 1, blocked INTEGER NOT NULL DEFAULT 0, last_error TEXT)',
            );
            await db.execute(
              'CREATE UNIQUE INDEX bangumi_sync_queue_account_key ON bangumi_sync_queue(username, mutation_key)',
            );
            for (final (id, updatedAt) in [(7, 30), (8, 20)]) {
              await db.insert('bangumi_sync_queue', {
                'username': 'tester',
                'mutation_key': 'episode:$id',
                'kind': 'episode',
                'payload': '{"episode_id":$id,"type":0}',
                'created_at': 10,
                'updated_at': updatedAt,
                'revision': 2,
              });
            }
          },
        ),
      );
      await old.close();
      final migrated = await store.pendingFor('tester');
      expect(migrated.map((item) => item.payload['episode_id']), [8, 7]);
      expect(migrated.map((item) => item.revision), [2, 2]);
      await store.enqueue(
        username: 'tester',
        kind: BangumiMutationKind.episode,
        mutationKey: 'episode:8',
        payload: {'episode_id': 8, 'type': 2},
      );
      final updated = await store.pendingFor('tester');
      expect(updated.map((item) => item.payload['episode_id']), [7, 8]);
      expect(updated.last.revision, 3);
      expect(await store.removeIfUnchanged(migrated.first), isFalse);
    },
  );
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
    expect(latest.single.id, greaterThan(firstRevision.id));

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

  test(
    'coalesced episode compensation reopens after other earlier intents',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'mubangumi-sync-order-',
      );
      final store = BangumiSyncStore(
        databasePath: path.join(directory.path, 'sync.sqlite'),
      );
      addTearDown(() async {
        await store.close();
        if (directory.parent.resolveSymbolicLinksSync() !=
                Directory.systemTemp.resolveSymbolicLinksSync() ||
            !path
                .basename(directory.path)
                .startsWith('mubangumi-sync-order-')) {
          throw StateError('Unexpected test directory');
        }
        await directory.delete(recursive: true);
      });
      for (final (id, count) in [(7, 1), (8, 2), (7, 1)]) {
        await store.enqueue(
          username: 'tester',
          kind: BangumiMutationKind.episode,
          mutationKey: 'episode:$id',
          payload: {
            'subject_id': 99,
            'episode_id': id,
            'local_episode_status': count,
          },
        );
      }
      await store.close();
      final pending = await store.pendingFor('tester');
      expect(pending.map((item) => item.payload['episode_id']), [8, 7]);
      expect(pending.last.payload['local_episode_status'], 1);
    },
  );

  test('blocked issue actions are account and revision safe', () async {
    final directory = await Directory.systemTemp.createTemp(
      'mubangumi-sync-issues-test-',
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
      kind: BangumiMutationKind.episode,
      mutationKey: 'episode:42',
      payload: const {'subject_id': 8, 'episode_id': 42, 'type': 2},
    );
    final first = (await store.pendingFor('tester')).single;
    expect(await store.markFailure(first, '章节状态无效', blocked: true), isTrue);

    await store.enqueue(
      username: 'another',
      kind: BangumiMutationKind.collection,
      mutationKey: 'collection:9',
      payload: const {'subject_id': 9, 'collection_type': 3},
    );
    final other = (await store.pendingFor('another')).single;
    expect(await store.markFailure(other, '另一个账号的错误', blocked: true), isTrue);

    final staleIssue = (await store.blockedFor('tester')).single;
    expect(staleIssue.lastError, '章节状态无效');
    expect(staleIssue.attempts, 1);

    // A new edit of the same key supersedes the issue currently shown in UI.
    await store.enqueue(
      username: 'tester',
      kind: BangumiMutationKind.episode,
      mutationKey: 'episode:42',
      payload: const {'subject_id': 8, 'episode_id': 42, 'type': 3},
    );
    expect(await store.retryIfUnchanged(staleIssue), isFalse);
    expect(await store.discardIfUnchanged(staleIssue), isFalse);

    final latest = (await store.pendingFor('tester')).single;
    expect(latest.revision, staleIssue.revision + 1);
    expect(await store.markFailure(latest, '仍然无效', blocked: true), isTrue);
    final currentIssue = (await store.blockedFor('tester')).single;

    expect(await store.retryIfUnchanged(currentIssue), isTrue);
    final retried = (await store.pendingFor('tester')).single;
    expect(retried.blocked, isFalse);
    expect(retried.attempts, 0);
    expect(retried.lastError, isNull);

    expect(await store.markFailure(retried, '最后一次失败', blocked: true), isTrue);
    final discardable = (await store.blockedFor('tester')).single;
    expect(await store.discardIfUnchanged(discardable), isTrue);
    expect(await store.countFor('tester'), 0);
    expect(await store.blockedCountFor('another'), 1);
    expect((await store.blockedFor('another')).single.lastError, '另一个账号的错误');
  });
}
