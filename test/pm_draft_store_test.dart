import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/storage/pm_draft_store.dart';
import 'package:path/path.dart' as path;

void main() {
  late Directory dir;
  late PmDraftStore store;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mubangumi-pm-drafts-');
    store = PmDraftStore(databasePath: path.join(dir.path, 'drafts.sqlite'));
  });
  tearDown(() async {
    await store.close();
    if (dir.parent.resolveSymbolicLinksSync() !=
            Directory.systemTemp.resolveSymbolicLinksSync() ||
        !path.basename(dir.path).startsWith('mubangumi-pm-drafts-')) {
      throw StateError('Unexpected test directory');
    }
    await dir.delete(recursive: true);
  });

  test(
    'drafts survive reopen and isolate owner, recipient and reply thread',
    () async {
      const draft = PmDraft(
        id: 'one',
        ownerId: 1,
        kind: PmDraftKind.compose,
        recipient: ' Alice ',
        title: ' 标题 ',
        body: '未完成\n😀',
      );
      await store.save(draft, expectedRevision: 0);
      await store.save(
        const PmDraft(
          id: 'one',
          ownerId: 2,
          kind: PmDraftKind.compose,
          recipient: 'alice',
          body: 'other account',
        ),
        expectedRevision: 0,
      );
      final reply = PmDraft(
        id: PmDraft.replyId('42', '9'),
        ownerId: 1,
        kind: PmDraftKind.reply,
        conversationId: '42',
        threadId: '9',
        body: 'reply',
      );
      await store.save(reply, expectedRevision: 0);
      await store.close();
      expect(
        (await store.findCompose(1, recipient: 'alice'))!.draft!.body,
        '未完成\n😀',
      );
      expect((await store.findCompose(2))!.draft!.body, 'other account');
      expect(await store.findCompose(1, recipient: 'bob'), isNull);
      expect((await store.read(1, PmDraft.replyId('42', '10'))).draft, isNull);
      expect((await store.read(1, reply.id)).draft!.body, 'reply');
      expect(await store.listCompose(1), hasLength(1));
    },
  );

  test(
    'changing a recipient updates the same draft without overwriting another draft',
    () async {
      const a = PmDraft(
        id: 'a',
        ownerId: 1,
        kind: PmDraftKind.compose,
        recipient: 'alice',
        body: 'A',
      );
      const b = PmDraft(
        id: 'b',
        ownerId: 1,
        kind: PmDraftKind.compose,
        recipient: 'bob',
        body: 'B',
      );
      await store.save(a, expectedRevision: 0);
      await store.save(b, expectedRevision: 0);
      await store.save(
        a.edited(recipient: 'bob', title: 'new', body: 'changed recipient'),
        expectedRevision: 1,
      );
      expect(await store.findCompose(1, recipient: 'alice'), isNull);
      expect((await store.findCompose(1, recipient: 'bob'))!.draft!.id, 'a');
      expect((await store.read(1, 'b')).draft!.body, 'B');
      expect(await store.listCompose(1), hasLength(2));
    },
  );

  test(
    'tombstones reject delayed editors and permit a newly opened editor',
    () async {
      const draft = PmDraft(
        id: 'reply',
        ownerId: 1,
        kind: PmDraftKind.reply,
        body: 'sent',
      );
      await store.save(draft, expectedRevision: 0);
      final cleared = await store.clear(1, draft.id, expectedRevision: 1);
      for (final oldRevision in [0, 1]) {
        await expectLater(
          store.save(draft, expectedRevision: oldRevision),
          throwsA(isA<PmDraftConflict>()),
        );
      }
      await store.close();
      final fresh = await store.read(1, draft.id);
      expect(fresh.draft, isNull);
      expect(fresh.revision, cleared);
      await store.save(
        draft.edited(recipient: '', title: '', body: 'new reply'),
        expectedRevision: fresh.revision,
      );
      expect((await store.read(1, draft.id)).draft!.body, 'new reply');
    },
  );

  test(
    'stale deletion cannot erase a newer editor and empty text removes payload',
    () async {
      const draft = PmDraft(
        id: 'reply',
        ownerId: 1,
        kind: PmDraftKind.reply,
        body: 'old',
      );
      await store.save(draft, expectedRevision: 0);
      await store.save(
        draft.edited(recipient: '', title: '', body: 'newer'),
        expectedRevision: 1,
      );
      await expectLater(
        store.clear(1, draft.id, expectedRevision: 1),
        throwsA(isA<PmDraftConflict>()),
      );
      expect((await store.read(1, draft.id)).draft!.body, 'newer');
      await store.save(
        draft.edited(recipient: '', title: '', body: ''),
        expectedRevision: 2,
      );
      expect((await store.read(1, draft.id)).draft, isNull);
    },
  );
}
