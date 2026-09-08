import 'support/memory_pm_draft_repository.dart';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/storage/pm_draft_store.dart';
import 'package:mubangumi/state/pm_draft_controller.dart';

const initial = PmDraft(id: 'draft', ownerId: 1, kind: PmDraftKind.compose);

void main() {
  test('debounced snapshots preserve text and retry failed writes', () async {
    final repo = MemoryPmDraftRepository()..failSave = true;
    final controller = PmDraftController(repo, initial);
    addTearDown(controller.dispose);
    await controller.restore(fresh: true);
    controller.edit(recipient: 'alice', title: '标题', body: 'draft');
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(controller.dirty, isTrue);
    expect(controller.error, contains('保存失败'));
    expect(controller.data.body, 'draft');
    repo.failSave = false;
    expect(await controller.flush(), isTrue);
    expect(controller.saved, isTrue);
    expect((await repo.read(1, 'draft')).draft!.recipient, 'alice');
  });

  test(
    'queued edits use the latest acknowledged version instead of self-conflicting',
    () async {
      final gate = Completer<void>();
      final repo = MemoryPmDraftRepository()..saveGate = gate.future;
      final controller = PmDraftController(repo, initial);
      addTearDown(controller.dispose);
      await controller.restore(fresh: true);
      controller.edit(recipient: 'alice', title: '', body: 'old');
      final first = controller.flush();
      await pumpEventQueue();
      controller.edit(recipient: 'bob', title: 'new', body: 'latest');
      final second = controller.flush();
      gate.complete();
      expect(await first, isTrue);
      expect(await second, isTrue);
      expect(controller.error, isNull);
      expect((await repo.read(1, 'draft')).draft!.body, 'latest');
    },
  );

  test(
    'successful send clears after in-flight saves and never saves sent text again',
    () async {
      final gate = Completer<void>();
      final repo = MemoryPmDraftRepository()..saveGate = gate.future;
      final controller = PmDraftController(repo, initial);
      addTearDown(controller.dispose);
      await controller.restore(fresh: true);
      controller.edit(recipient: 'alice', title: '', body: 'message');
      final save = controller.flush();
      await pumpEventQueue();
      final sent = controller.markSent();
      gate.complete();
      await save;
      expect(await sent, isTrue);
      controller.edit(recipient: 'bob', title: '', body: 'late');
      await controller.flush();
      expect((await repo.read(1, 'draft')).draft, isNull);
    },
  );

  test(
    'send confirmation after route disposal can still clear the saved draft',
    () async {
      final repo = MemoryPmDraftRepository();
      final controller = PmDraftController(repo, initial);
      await controller.restore(fresh: true);
      controller.edit(recipient: 'alice', title: '', body: 'pending send');
      controller.dispose();
      expect(await controller.markSent(), isTrue);
      expect((await repo.read(1, 'draft')).draft, isNull);
    },
  );

  test(
    'failed cleanup locks sending and retry only clears the draft',
    () async {
      final repo = MemoryPmDraftRepository();
      final controller = PmDraftController(repo, initial);
      addTearDown(controller.dispose);
      await controller.restore(fresh: true);
      controller.edit(recipient: 'alice', title: '', body: 'message');
      await controller.flush();
      repo.failClear = true;
      expect(await controller.markSent(), isFalse);
      expect(controller.sent, isTrue);
      expect(controller.error, contains('勿重复发送'));
      repo.failClear = false;
      expect(await controller.markSent(), isTrue);
      expect((await repo.read(1, 'draft')).draft, isNull);
    },
  );

  test('failed restoration cannot overwrite the existing draft', () async {
    final repo = MemoryPmDraftRepository();
    await repo.save(
      initial.edited(recipient: 'alice', title: '', body: 'saved'),
      expectedRevision: 0,
    );
    repo.failRead = true;
    final controller = PmDraftController(repo, initial);
    addTearDown(controller.dispose);
    await controller.restore();
    controller.edit(recipient: '', title: '', body: '');
    await controller.flush();
    expect(controller.ready, isFalse);
    repo.failRead = false;
    await controller.restore();
    expect(controller.data.body, 'saved');
    expect(controller.ready, isTrue);
  });

  test(
    'late send cleanup preserves a draft updated by another editor',
    () async {
      final repo = MemoryPmDraftRepository();
      final first = PmDraftController(repo, initial);
      addTearDown(first.dispose);
      await first.restore();
      first.edit(recipient: 'alice', title: 'title', body: 'sent content');
      await first.flush();
      final second = PmDraftController(repo, initial);
      addTearDown(second.dispose);
      await second.restore();
      second.edit(
        recipient: 'alice',
        title: 'title',
        body: 'new unsent content',
      );
      await second.flush();
      expect(await first.markSent(), isTrue);
      expect((await repo.read(1, 'draft')).draft!.body, 'new unsent content');
      expect(first.error, contains('另一处更新'));
    },
  );
}
