import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/storage/community_draft_store.dart';
import 'package:path/path.dart' as path;

void main() {
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
