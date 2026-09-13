import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/storage/community_draft_store.dart';
import 'package:mubangumi/state/short_review_draft.dart';
import 'support/memory_short_review_drafts.dart';

void main() {
  ShortReviewDraft editor(
    CommunityDraftRepository store, {
    int owner = 1,
    int subject = 2,
    String original = '',
  }) => ShortReviewDraft(
    store,
    ownerId: owner,
    subjectId: subject,
    original: original,
  );

  test(
    'draft survives closing the database and is isolated by owner and subject',
    () async {
      final dir = await Directory.systemTemp.createTemp('short-review-test-');
      final store = CommunityDraftStore(
        databasePath: '${dir.path}/draft.sqlite',
      );
      addTearDown(() async {
        await store.close();
        if (!dir.absolute.path.startsWith(Directory.systemTemp.absolute.path) ||
            !dir.path.contains('short-review-test-')) {
          throw StateError('Unexpected cleanup path');
        }
        await dir.delete(recursive: true);
      });
      final first = editor(store);
      // Community backup keys start with a JSON string username, never a numeric ID.
      expect(first.key.startsWith('[1,'), isTrue);
      await first.restore();
      first.edit('写到一半的短评');
      expect(await first.flush(), isTrue);
      first.dispose();
      await store.close();
      final second = editor(store);
      await second.restore();
      expect(second.text, '写到一半的短评');
      for (final other in [
        editor(store, owner: 2),
        editor(store, subject: 3),
      ]) {
        await other.restore();
        expect(other.text, isEmpty);
        other.dispose();
      }
      second.dispose();
    },
  );

  test('clearing an existing comment is a recoverable draft', () async {
    final store = MemoryShortReviewDrafts();
    final first = editor(store, original: '旧短评');
    await first.restore();
    first.edit('');
    await first.flush();
    first.dispose();
    final second = editor(store, original: '旧短评');
    await second.restore();
    expect(second.text, '');
    expect(second.saved, isTrue);
    second.dispose();
  });

  test(
    'failed save preserves text and successful submission prevents stale resurrection',
    () async {
      final store = MemoryShortReviewDrafts();
      final draft = editor(store);
      await draft.restore();
      draft.edit('新短评');
      store.fail = true;
      expect(await draft.flush(), isFalse);
      expect(draft.text, '新短评');
      expect(draft.dirty, isTrue);
      store.fail = false;
      expect(await draft.flush(), isTrue);
      expect(await draft.markSubmitted(), isTrue);
      draft.dispose();
      final reopened = editor(store);
      await reopened.restore();
      expect(reopened.text, '');
      reopened.dispose();
    },
  );

  test('concurrent editors do not overwrite a newer saved draft', () async {
    final store = MemoryShortReviewDrafts();
    final a = editor(store), b = editor(store);
    await a.restore();
    await b.restore();
    a.edit('较新草稿');
    await a.flush();
    b.edit('旧窗口文字');
    expect(await b.flush(), isFalse);
    expect((await store.load(a.key))!.content, '较新草稿');
    expect(b.text, '旧窗口文字');
    a.dispose();
    b.dispose();
  });

  test('changed server comment requires explicit draft recovery', () async {
    final store = MemoryShortReviewDrafts();
    final a = editor(store, original: '原文');
    await a.restore();
    a.edit('草稿');
    await a.flush();
    a.dispose();
    final b = editor(store, original: '其他设备的新短评');
    await b.restore();
    expect(b.text, '其他设备的新短评');
    expect(b.conflictingText, '草稿');
    b.recoverConflict();
    expect(b.text, '草稿');
    await b.flush();
    b.dispose();
  });
}
