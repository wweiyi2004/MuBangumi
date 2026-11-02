import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/platform/window_close.dart';
import 'package:mubangumi/core/storage/pm_draft_store.dart';
import 'package:mubangumi/state/pm_draft_controller.dart';
import 'support/memory_pm_draft_repository.dart';

void main() {
  test(
    'close waits for the last debounced PM input to become durable',
    () async {
      final store = MemoryPmDraftRepository();
      final draft = PmDraftController(
        store,
        const PmDraft(id: 'close', ownerId: 1, kind: PmDraftKind.compose),
      );
      addTearDown(draft.dispose);
      await draft.restore();
      draft.edit(recipient: '42', title: 'synthetic', body: 'last keystroke');
      final gate = Completer<void>();
      store.saveGate = gate.future;
      var closed = false;
      final close = WindowCloseCoordinator.prepareToClose().then((result) {
        closed = result;
        return result;
      });
      await Future<void>.delayed(Duration.zero);
      expect(closed, false);
      gate.complete();
      expect(await close, true);
      expect((await store.read(1, 'close')).draft!.body, 'last keystroke');
    },
  );
  test(
    'failed local durability cancels close and can recover on the next attempt',
    () async {
      final store = MemoryPmDraftRepository()..failSave = true;
      final draft = PmDraftController(
        store,
        const PmDraft(id: 'close', ownerId: 1, kind: PmDraftKind.compose),
      );
      addTearDown(draft.dispose);
      await draft.restore();
      draft.edit(recipient: '42', title: 'synthetic', body: 'retained input');
      expect(await WindowCloseCoordinator.prepareToClose(), false);
      expect(draft.dirty, true);
      store.failSave = false;
      expect(await WindowCloseCoordinator.prepareToClose(), true);
      expect((await store.read(1, 'close')).draft!.body, 'retained input');
    },
  );
}
