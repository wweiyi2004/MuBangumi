import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/storage/community_draft_store.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test(
    'v1 migration preserves text and CAS rejects stale save after tombstone',
    () async {
      sqfliteFfiInit();
      final dir = await Directory.systemTemp.createTemp(
        'mubangumi-draft-migrate-',
      );
      final file = path.join(dir.path, 'drafts.sqlite');
      final old = await databaseFactoryFfi.openDatabase(
        file,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) => db.execute(
            'CREATE TABLE draft (draft_key TEXT PRIMARY KEY NOT NULL, title TEXT NOT NULL, content TEXT NOT NULL, updated_at INTEGER NOT NULL)',
          ),
        ),
      );
      final key = communityDraftKey('alice', ['timeline', 'post'])!;
      await old.insert('draft', {
        'draft_key': key,
        'title': '标题',
        'content': ' 原文\n保留 ',
        'updated_at': 123,
      });
      await old.close();
      final store = CommunityDraftStore(databasePath: file);
      addTearDown(() async {
        await store.close();
        await dir.delete(recursive: true);
      });
      final loaded = await store.loadVersioned(key);
      expect(loaded.data!.content, ' 原文\n保留 ');
      expect(loaded.revision, 1);
      expect(
        await store.saveVersioned(key, (
          title: '',
          content: '',
        ), expectedRevision: loaded.revision),
        2,
      );
      await store.close();
      final tombstone = await store.loadVersioned(key);
      expect(tombstone.data, isNull);
      expect(tombstone.revision, 2);
      await expectLater(
        store.saveVersioned(
          key,
          loaded.data!,
          expectedRevision: loaded.revision,
        ),
        throwsA(isA<CommunityDraftConflict>()),
      );
      expect(await store.load(key), isNull);
      expect(
        await store.saveVersioned(key, (
          title: '',
          content: '新稿',
        ), expectedRevision: 2),
        3,
      );
    },
  );
  test(
    'drafts survive database reopen, isolate accounts/targets and clear in order',
    () async {
      final dir = await Directory.systemTemp.createTemp('mubangumi-drafts-');
      final databasePath = path.join(dir.path, 'drafts.sqlite');
      final store = CommunityDraftStore(databasePath: databasePath);
      final restarted = CommunityDraftStore(databasePath: databasePath);
      addTearDown(() async {
        await store.close();
        await restarted.close();
        await dir.delete(recursive: true);
      });
      final alice = communityDraftKey('Alice', ['topic', 1, 0])!;
      final bob = communityDraftKey('bob', ['topic', 1, 0])!;
      final another = communityDraftKey('alice', ['topic', 2, 0])!;
      await store.save(alice, (title: '标题', content: ' 未完成\n[b]内容[/b] '));
      await store.save(bob, (title: '', content: 'bob'));
      await store.save(another, (title: '', content: '另一个话题'));
      await store.close();
      expect((await restarted.load(alice))!.content, ' 未完成\n[b]内容[/b] ');
      expect((await restarted.load(bob))!.content, 'bob');
      final oldWrite = restarted.save(alice, (title: '', content: 'pending'));
      final clear = restarted.save(alice, (title: '', content: ''));
      await Future.wait([oldWrite, clear]);
      await restarted.close();
      expect(await store.load(alice), isNull);
      expect((await store.load(another))!.content, '另一个话题');
      expect((await store.load(bob))!.content, 'bob');
    },
  );

  test('keys require an account and cannot collide across target parts', () {
    expect(communityDraftKey(null, ['post']), isNull);
    expect(communityDraftKey('  ', ['post']), isNull);
    expect(
      communityDraftKey(' Alice ', ['post']),
      communityDraftKey('alice', ['post']),
    );
    expect(
      communityDraftKey('a:b', ['c']),
      isNot(communityDraftKey('a', ['b:c'])),
    );
  });
}
