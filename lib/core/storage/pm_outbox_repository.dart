import '../../models/pm_send_command.dart';
import 'pm_draft_store.dart';

class PmEnqueuedDraft {
  const PmEnqueuedDraft(this.command, this.revision);
  final PmSendCommand command;
  final int revision;
}

/// Implemented with the draft store so enqueue + clearing the exact draft
/// revision commit together. No credentials or CSRF forms are persisted here.
abstract interface class PmOutboxRepository {
  Future<PmEnqueuedDraft> enqueueDraft(
    PmDraft draft, {
    required int expectedRevision,
    required String receiver,
    required String related,
  });
  Future<List<PmSendCommand>> outboxFor(int ownerId);
  Future<PmSendCommand?> claimNext(int ownerId);
  Future<bool> changeCommand(
    int ownerId,
    String id, {
    required Set<PmSendStatus> from,
    required PmSendStatus to,
    int? baseline,
    int? attempt,
    String? error,
  });
  Future<void> recoverOutbox(int ownerId);
}
