import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;
import 'package:mubangumi/core/storage/pm_draft_store.dart';
import 'package:mubangumi/models/pm_send_command.dart';

void main() {
  late Directory directory;
  late PmDraftStore store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('mubangumi-outbox-');
    store = PmDraftStore(
      databasePath: path.join(directory.path, 'drafts.sqlite'),
    );
  });
  tearDown(() async {
    await store.close();
    if (directory.parent.resolveSymbolicLinksSync() !=
            Directory.systemTemp.resolveSymbolicLinksSync() ||
        !path.basename(directory.path).startsWith('mubangumi-outbox-')) {
      throw StateError('Unexpected test path');
    }
    await directory.delete(recursive: true);
  });
  PmDraft draft(String id, {String body = '内容', int owner = 1}) => PmDraft(
    id: id,
    ownerId: owner,
    kind: PmDraftKind.reply,
    recipient: 'alice',
    body: body,
    conversationId: 'chat',
    threadId: 'topic',
  );

  test(
    'enqueue and draft clearing are atomic, durable and idempotent',
    () async {
      final original = draft('one');
      await store.save(original, expectedRevision: 0);
      final result = await store.enqueueDraft(
        original,
        expectedRevision: 1,
        receiver: '42',
        related: 'topic',
      );
      expect((await store.read(1, 'one')).draft, isNull);
      expect((await store.read(1, 'one')).revision, 2);
      await store.close();
      expect((await store.outboxFor(1)).single.body, '内容');
      final replay = await store.enqueueDraft(
        original,
        expectedRevision: 1,
        receiver: '42',
        related: 'topic',
      );
      expect(replay.command.id, result.command.id);
      expect(await store.outboxFor(1), hasLength(1));
      await expectLater(
        store.enqueueDraft(
          original,
          expectedRevision: 1,
          receiver: '99',
          related: 'topic',
        ),
        throwsA(isA<PmDraftConflict>()),
      );
    },
  );

  test(
    'stale draft revisions cannot enqueue or clear another editor',
    () async {
      await store.save(draft('one', body: '最新输入'), expectedRevision: 0);
      await expectLater(
        store.enqueueDraft(
          draft('one'),
          expectedRevision: 0,
          receiver: '42',
          related: 'topic',
        ),
        throwsA(isA<PmDraftConflict>()),
      );
      expect(await store.outboxFor(1), isEmpty);
      expect((await store.read(1, 'one')).draft!.body, '最新输入');
    },
  );

  test(
    'claims preserve order per recipient while other recipients can proceed',
    () async {
      final first = await store.enqueueDraft(
        draft('a'),
        expectedRevision: 0,
        receiver: '42',
        related: 'topic',
      );
      final second = await store.enqueueDraft(
        draft('b'),
        expectedRevision: 0,
        receiver: '42',
        related: 'topic',
      );
      final other = await store.enqueueDraft(
        draft('c'),
        expectedRevision: 0,
        receiver: '99',
        related: 'topic',
      );
      expect((await store.claimNext(1))!.id, first.command.id);
      await store.changeCommand(
        1,
        first.command.id,
        from: {PmSendStatus.preparing},
        to: PmSendStatus.uncertain,
      );
      expect((await store.claimNext(1))!.id, other.command.id);
      expect(await store.claimNext(1), isNull);
      await store.changeCommand(
        1,
        first.command.id,
        from: {PmSendStatus.uncertain},
        to: PmSendStatus.cancelled,
      );
      expect((await store.claimNext(1))!.id, second.command.id);
    },
  );

  test(
    'crash recovery retries only preflight; possible sends become uncertain',
    () async {
      final first = await store.enqueueDraft(
        draft('a'),
        expectedRevision: 0,
        receiver: '42',
        related: 'topic',
      );
      final second = await store.enqueueDraft(
        draft('b'),
        expectedRevision: 0,
        receiver: '99',
        related: 'topic',
      );
      await store.claimNext(1);
      await store.changeCommand(
        1,
        first.command.id,
        from: {PmSendStatus.preparing},
        to: PmSendStatus.sending,
        baseline: 3,
      );
      await store.claimNext(1);
      await store.close();
      await store.recoverOutbox(1);
      final rows = await store.outboxFor(1);
      expect(rows.first.status, PmSendStatus.uncertain);
      expect(rows.first.baseline, 3);
      expect(rows.last.status, PmSendStatus.queued);
      expect((await store.claimNext(1))!.id, second.command.id);
    },
  );

  test('queue reads and state changes are isolated by owner', () async {
    final first = await store.enqueueDraft(
      draft('a'),
      expectedRevision: 0,
      receiver: '42',
      related: 'topic',
    );
    await store.enqueueDraft(
      draft('b', owner: 2),
      expectedRevision: 0,
      receiver: '42',
      related: 'topic',
    );
    expect(await store.outboxFor(1), hasLength(1));
    expect((await store.claimNext(2))!.ownerId, 2);
    expect(
      await store.changeCommand(
        2,
        first.command.id,
        from: {PmSendStatus.queued},
        to: PmSendStatus.cancelled,
      ),
      isFalse,
    );
    expect((await store.outboxFor(1)).single.status, PmSendStatus.queued);
  });

  test('a stale worker cannot change a newly claimed attempt', () async {
    await store.enqueueDraft(
      draft('one'),
      expectedRevision: 0,
      receiver: '42',
      related: 'topic',
    );
    final old = (await store.claimNext(1))!;
    await store.recoverOutbox(1);
    final next = (await store.claimNext(1))!;
    expect(next.attempt, greaterThan(old.attempt));
    expect(
      await store.changeCommand(
        1,
        old.id,
        attempt: old.attempt,
        from: {PmSendStatus.preparing},
        to: PmSendStatus.sending,
      ),
      isFalse,
    );
    expect(
      await store.changeCommand(
        1,
        next.id,
        attempt: next.attempt,
        from: {PmSendStatus.preparing},
        to: PmSendStatus.sending,
      ),
      isTrue,
    );
    expect(
      await store.changeCommand(
        1,
        old.id,
        attempt: old.attempt,
        from: {PmSendStatus.sending},
        to: PmSendStatus.queued,
      ),
      isFalse,
    );
  });

  test(
    'upgrading the installed draft database preserves existing private text',
    () async {
      await store.save(draft('existing', body: '升级前的草稿'), expectedRevision: 0);
      await store.close();
      ffi.sqfliteFfiInit();
      final legacy = await ffi.databaseFactoryFfi.openDatabase(
        path.join(directory.path, 'drafts.sqlite'),
      );
      await legacy.execute('DROP TABLE pm_send_queue');
      await legacy.setVersion(1);
      await legacy.close();
      final restored = (await store.read(1, 'existing')).draft!;
      expect(restored.body, '升级前的草稿');
      await store.enqueueDraft(
        restored,
        expectedRevision: 1,
        receiver: '42',
        related: 'topic',
      );
      expect((await store.outboxFor(1)).single.body, '升级前的草稿');
    },
  );
}
