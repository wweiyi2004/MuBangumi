import 'package:mubangumi/core/storage/pm_draft_store.dart';

class MemoryPmDraftRepository implements PmDraftRepository {
  final slots = <String, PmDraftSlot>{};
  bool failSave = false, failClear = false, failRead = false;
  Future<void>? saveGate;
  String key(int owner, String id) => '$owner/$id';
  @override
  Future<PmDraftSlot> read(int ownerId, String id) async {
    if (failRead) throw StateError('read');
    return slots[key(ownerId, id)] ?? const PmDraftSlot();
  }

  @override
  Future<PmDraftSlot?> findCompose(int ownerId, {String? recipient}) async {
    if (failRead) throw StateError('read');
    return slots.values
        .where(
          (slot) =>
              slot.draft?.ownerId == ownerId &&
              slot.draft?.kind == PmDraftKind.compose &&
              (recipient == null ||
                  recipient.isEmpty ||
                  slot.draft?.recipient.trim().toLowerCase() ==
                      recipient.trim().toLowerCase()),
        )
        .lastOrNull;
  }

  @override
  Future<List<PmDraft>> listCompose(int ownerId) async => [
    for (final slot in slots.values)
      if (slot.draft?.ownerId == ownerId &&
          slot.draft?.kind == PmDraftKind.compose)
        slot.draft!,
  ];
  @override
  Future<int> save(PmDraft draft, {required int expectedRevision}) async {
    await saveGate;
    if (failSave) throw StateError('write');
    final current = slots[key(draft.ownerId, draft.id)]?.revision ?? 0;
    if (current != expectedRevision) throw const PmDraftConflict();
    slots[key(draft.ownerId, draft.id)] = PmDraftSlot(
      draft: draft.isEmpty ? null : draft,
      revision: current + 1,
    );
    return current + 1;
  }

  @override
  Future<int> clear(
    int ownerId,
    String id, {
    required int expectedRevision,
  }) async {
    if (failClear) throw StateError('clear');
    final current = slots[key(ownerId, id)]?.revision ?? 0;
    if (current != expectedRevision) throw const PmDraftConflict();
    slots[key(ownerId, id)] = PmDraftSlot(revision: current + 1);
    return current + 1;
  }
}
