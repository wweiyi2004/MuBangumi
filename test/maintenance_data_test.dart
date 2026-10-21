import 'dart:async';
import 'dart:io';
import 'package:banjian_server/banjian_server.dart';
import 'package:mubangumi/features/anime_appreciation/room_connection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/network/bangumi_api.dart';
import 'package:mubangumi/core/storage/bangumi_sync_store.dart';
import 'package:mubangumi/core/storage/pm_draft_store.dart';
import 'package:mubangumi/core/storage/sqlite_support.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/models/pm_send_command.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'support/collection_module_fixtures.dart';
import 'support/library_batch_fixtures.dart';
import 'support/progress_fixtures.dart';

Future<Directory> sandbox() async {
  final directory = await Directory.systemTemp.createTemp(
    'mubangumi-maintenance-',
  );
  addTearDown(() async {
    if (p.dirname(directory.absolute.path) !=
            Directory.systemTemp.absolute.path ||
        !p.basename(directory.path).startsWith('mubangumi-maintenance-')) {
      throw StateError('Unexpected cleanup path');
    }
    await directory.delete(recursive: true);
  });
  return directory;
}

void main() {
  test(
    'rotated invitation reuses the existing participant only at its verified server origin',
    () async {
      final store = RoomStore(':memory:');
      final server = RoomServer(
        store: store,
        adminPassword: 'synthetic-management-password',
        assets: {},
        autoCacheCovers: false,
      );
      final storage = _ParticipationMemory();
      final client = ParticipationController(storage: storage);
      await server.start(port: 0, address: InternetAddress.loopbackIPv4);
      addTearDown(() async {
        client.dispose();
        await server.close();
        store.close();
      });
      final id =
          store.create({'op': newSecret(), 'title': 'synthetic event'})['id']
              as String;
      final base = Uri.parse('http://127.0.0.1:${server.port}');
      final first = RoomInvite(base, id, store.event(id)['invite']);
      await client.join(first, 'synthetic participant');
      final token = storage.value!['token'];
      await client.leave();
      store.admin({
        'op': newSecret(),
        'event': id,
        'version': store.event(id)['version'],
        'action': 'rotateInvite',
      });
      final rotated = RoomInvite(base, id, store.event(id)['invite']);
      expect(rotated.sameRoom(first), false);
      expect(
        RoomInvite(
          Uri.parse('http://127.0.0.2:${server.port}'),
          id,
          rotated.secret,
        ).sameServiceEvent(first),
        false,
      );
      await client.join(rotated, 'synthetic participant');
      expect(storage.value!['token'], token);
      expect(store.view(id, admin: true)['memberCount'], 1);
      await client.leave();
    },
  );
  test(
    'an unknown old install requires a choice before empty stores are opened',
    () async {
      final dir = await sandbox();
      final support = Directory(p.join(dir.path, 'support'));
      final oldCache = File(
        p.join(support.path, 'cache-v2', 'mubangumi.sqlite'),
      );
      await oldCache.parent.create(recursive: true);
      await oldCache.writeAsString('synthetic presence marker');
      expect(
        await PersonalDatabasePaths.prepare(
          supportDirectory: support,
          legacyDirectories: [],
        ),
        false,
      );
      expect(
        await Directory(p.join(support.path, 'databases')).exists(),
        false,
      );
      final old = Directory(p.join(dir.path, 'old'));
      await old.create();
      final db = await sqliteFactory.openDatabase(
        p.join(old.path, 'mubangumi_schedule.sqlite'),
      );
      await db.execute('CREATE TABLE sample(value INTEGER)');
      await db.insert('sample', {'value': 7});
      await db.close();
      await PersonalDatabasePaths.migrateFrom(old, supportDirectory: support);
      expect(
        await PersonalDatabasePaths.prepare(
          supportDirectory: support,
          legacyDirectories: [],
        ),
        true,
      );
      final migrated = await sqliteFactory.openDatabase(
        p.join(support.path, 'databases', 'mubangumi_schedule.sqlite'),
      );
      expect((await migrated.query('sample')).single['value'], 7);
      await migrated.close();
      expect(await oldCache.exists(), true);
    },
  );
  test(
    'desktop migration includes WAL and preserves old and newer target data',
    () async {
      final dir = await sandbox();
      final legacyDir = Directory(p.join(dir.path, 'old'));
      await legacyDir.create();
      const name = 'mubangumi_schedule.sqlite';
      final old = await sqliteFactory.openDatabase(
        p.join(legacyDir.path, name),
      );
      addTearDown(old.close);
      await old.rawQuery('PRAGMA journal_mode=WAL');
      await old.execute('CREATE TABLE sample (value INTEGER)');
      await old.insert('sample', {'value': 7});
      final support = Directory(p.join(dir.path, 'support'));
      final target = await PersonalDatabasePaths.migrate(
        name,
        supportDirectory: support,
        legacyDirectories: [legacyDir],
      );
      expect(p.isWithin(support.path, target), true);
      final migrated = await sqliteFactory.openDatabase(target);
      addTearDown(migrated.close);
      expect((await migrated.query('sample')).single['value'], 7);
      await migrated.insert('sample', {'value': 8});
      await old.insert('sample', {'value': 9});
      expect(
        await PersonalDatabasePaths.migrate(
          name,
          supportDirectory: support,
          legacyDirectories: [legacyDir],
        ),
        target,
      );
      expect((await migrated.query('sample')).map((r) => r['value']), [7, 8]);
      expect((await old.query('sample')).map((r) => r['value']), [7, 9]);
    },
  );

  test(
    'invalid legacy database fails visibly without creating a blank replacement',
    () async {
      final dir = await sandbox();
      const name = 'mubangumi_schedule.sqlite';
      await File(
        p.join(dir.path, name),
      ).writeAsString('synthetic corrupt database');
      final support = Directory(p.join(dir.path, 'support'));
      await expectLater(
        PersonalDatabasePaths.migrate(
          name,
          supportDirectory: support,
          legacyDirectories: [dir],
        ),
        throwsA(isA<DatabaseException>()),
      );
      expect(
        await File(p.join(support.path, 'databases', name)).exists(),
        false,
      );
      expect(
        await File(p.join(dir.path, name)).readAsString(),
        'synthetic corrupt database',
      );
    },
  );

  test(
    'discarded completion cannot revive chapters from the fast memory cache',
    () async {
      final cache = _Cache();
      cache.episodes['tester/1'] = [
        for (var i = 1; i <= 12; i++)
          UserEpisodeCollection(
            episode: progressEpisode(i),
            type: 0,
            updatedAt: 0,
          ),
      ];
      final f = CollectionModuleFixture(cache: cache);
      addTearDown(f.dispose);
      final subject = f.view.collections.single.subject;
      expect(
        await f.editor.changeCollection(
          subject,
          CollectionType.doing,
          watchedThrough: 10,
          deferSync: true,
        ),
        isNull,
      );
      await f.queue.markFailure(
        f.queue.items.single,
        'synthetic rejection',
        blocked: true,
      );
      expect(
        await f.editor.discardBlockedMutation(
          (await f.queue.blockedFor('tester')).single,
        ),
        isNull,
      );
      // Reload the authoritative chapters after discarding, as the screen does.
      cache.episodes['tester/1'] = [
        for (var i = 1; i <= 12; i++)
          UserEpisodeCollection(
            episode: progressEpisode(i),
            type: 0,
            updatedAt: 0,
          ),
      ];
      expect(
        await f.editor.changeCollection(
          subject,
          CollectionType.doing,
          watchedThrough: 5,
          deferSync: true,
        ),
        isNull,
      );
      expect(
        cache.episodes['tester/1']!.where((e) => e.type == 2),
        hasLength(5),
      );
    },
  );

  test(
    'a GET begun during persistence cannot overwrite the completed uploaded edit',
    () async {
      final gate = Completer<void>();
      final queue = MemoryBatchQueue()..saveGate = gate.future;
      final api = _RaceApi();
      final f = CollectionModuleFixture(queue: queue, api: api);
      addTearDown(f.dispose);
      api.old = f.view.collections.single;
      final edit = f.editor.changeCollection(
        api.old.subject,
        CollectionType.done,
        completeEpisodesWhenDone: false,
      );
      while (queue.calls == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      final refresh = f.loader.refresh();
      await api.started.future;
      gate.complete();
      expect(await edit, isNull);
      queue.items
          .clear(); // Upload completed while the old GET is still pending.
      api.release.complete();
      await refresh;
      expect(f.view.collections.single.type, CollectionType.done);
    },
  );

  test(
    'bulk completion counts once, discard rolls back only its own day entries',
    () async {
      final store = BangumiSyncStore(
        databasePath: inMemoryDatabasePath,
        now: () => DateTime(2026, 10, 21),
      );
      addTearDown(store.close);
      await store.enqueue(
        username: 'alice',
        kind: BangumiMutationKind.collection,
        mutationKey: 'collection:1',
        payload: {
          'subject_id': 1,
          'watched_through': 2,
          'activity_episodes': [
            {'episode_id': 1, 'before': 0},
            {'episode_id': 2, 'before': 0},
          ],
        },
      );
      final bulk = (await store.pendingFor('alice')).single;
      expect(await store.episodeActivityDays('alice'), {'2026-10-21': 2});
      await store.enqueue(
        username: 'alice',
        kind: BangumiMutationKind.episode,
        mutationKey: 'episode:3',
        payload: {
          'subject_id': 1,
          'episode_id': 3,
          'type': 2,
          'activity_before': 0,
        },
      );
      await store.markFailure(bulk, 'synthetic rejection', blocked: true);
      expect(
        await store.discardIfUnchanged(
          (await store.blockedFor('alice')).single,
        ),
        true,
      );
      expect(await store.episodeActivityDays('alice'), {'2026-10-21': 1});
    },
  );

  test(
    'discarding an earlier activity rebases later undo instead of resurrecting it',
    () async {
      final store = BangumiSyncStore(databasePath: inMemoryDatabasePath);
      addTearDown(store.close);
      await store.enqueue(
        username: 'alice',
        kind: BangumiMutationKind.episode,
        mutationKey: 'episode:1',
        payload: {
          'subject_id': 1,
          'episode_id': 1,
          'type': 2,
          'activity_before': 0,
        },
      );
      final first = (await store.pendingFor('alice')).single;
      await store.enqueue(
        username: 'alice',
        kind: BangumiMutationKind.collection,
        mutationKey: 'collection:1',
        payload: {
          'subject_id': 1,
          'watched_through': 1,
          'activity_episodes': [
            {'episode_id': 1, 'before': 0},
          ],
        },
      );
      final second = (await store.pendingFor('alice')).last;
      await store.markFailure(first, 'synthetic rejection', blocked: true);
      expect(await store.discardIfUnchanged(first), true);
      expect((await store.episodeActivityDays('alice')).values.single, 1);
      await store.markFailure(second, 'synthetic rejection', blocked: true);
      expect(await store.discardIfUnchanged(second), true);
      expect(await store.episodeActivityDays('alice'), isEmpty);
    },
  );

  test(
    'legacy username binding makes an uncertain compose block UID replies',
    () async {
      final store = PmDraftStore(databasePath: inMemoryDatabasePath);
      addTearDown(store.close);
      final first = await store.enqueueDraft(
        const PmDraft(
          id: 'one',
          ownerId: 1,
          kind: PmDraftKind.compose,
          recipient: 'alice',
          title: 'synthetic',
          body: 'one',
        ),
        expectedRevision: 0,
        receiver: 'alice',
        related: '',
      );
      await store.claimNext(1);
      await store.changeCommand(
        1,
        first.command.id,
        from: {PmSendStatus.preparing},
        to: PmSendStatus.uncertain,
      );
      await store.bindRecipient(1, first.command.id, 42);
      await store.enqueueDraft(
        const PmDraft(
          id: 'two',
          ownerId: 1,
          kind: PmDraftKind.reply,
          recipient: '42',
          body: 'two',
          conversationId: 'chat',
          threadId: 'topic',
        ),
        expectedRevision: 0,
        receiver: '42',
        related: 'topic',
      );
      expect(await store.claimNext(1), isNull);
      expect((await store.outboxFor(1)).first.status, PmSendStatus.uncertain);
      expect((await store.outboxFor(1)).first.targetKey, '42');
    },
  );
}

class _ParticipationMemory extends ParticipationStorage {
  Json? value;
  @override
  Future<Json?> read() async => value == null ? null : clone(value!);
  @override
  Future<void> write(Json next) async {
    value = clone(next);
  }
}

class _Cache extends BatchTestCache {
  @override
  Future<void> invalidateCollection(String username, int subjectId) async {}
  @override
  Future<void> clearEpisodeCollections(
    int subjectId, {
    String? username,
  }) async {
    episodes.remove('$username/$subjectId');
  }
}

class _RaceApi extends BangumiApi {
  late UserCollection old;
  final started = Completer<void>(), release = Completer<void>();
  @override
  Future<List<UserCollection>> getUserCollections(
    String username, {
    SubjectType? subjectType,
    CollectionType? collectionType,
    int? maxItems,
    Future<bool> Function(List<UserCollection>)? onPage,
  }) async {
    if (subjectType != SubjectType.anime) return [];
    started.complete();
    await release.future;
    return [old];
  }
}
