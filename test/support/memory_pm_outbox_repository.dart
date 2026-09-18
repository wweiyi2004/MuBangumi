import 'package:mubangumi/core/storage/pm_draft_store.dart';
import 'package:mubangumi/core/storage/pm_outbox_repository.dart';
import 'package:mubangumi/models/pm_send_command.dart';
import 'memory_pm_draft_repository.dart';

class MemoryPmOutboxRepository extends MemoryPmDraftRepository
    implements PmOutboxRepository {
  final commands = <String, PmSendCommand>{};
  final _sources = <String, PmEnqueuedDraft>{};
  Future<void>? enqueueGate;
  int _sequence = 0;
  @override
  Future<PmEnqueuedDraft> enqueueDraft(
    PmDraft draft, {
    required int expectedRevision,
    required String receiver,
    required String related,
  }) async {
    await enqueueGate;
    if (failSave) throw StateError('queue write');
    final source = '${draft.ownerId}/${draft.id}/$expectedRevision';
    if (_sources[source] case final result?) return result;
    final current = slots[key(draft.ownerId, draft.id)]?.revision ?? 0;
    if (current != expectedRevision) throw const PmDraftConflict();
    final command = PmSendCommand(
      id: 'command-${++_sequence}',
      sequence: _sequence,
      ownerId: draft.ownerId,
      compose: draft.kind == PmDraftKind.compose,
      receiver: receiver,
      title: draft.title.trim(),
      body: draft.body.trim(),
      conversationId: draft.conversationId,
      threadId: draft.threadId,
      related: related,
      createdAt: DateTime.now(),
    );
    commands[command.id] = command;
    slots[key(draft.ownerId, draft.id)] = PmDraftSlot(revision: current + 1);
    return _sources[source] = PmEnqueuedDraft(command, current + 1);
  }

  @override
  Future<List<PmSendCommand>> outboxFor(int ownerId) async =>
      commands.values.where((e) => e.ownerId == ownerId).toList();
  @override
  Future<PmSendCommand?> claimNext(int ownerId) async {
    for (final command in commands.values.toList()) {
      if (command.ownerId != ownerId || command.status != PmSendStatus.queued) {
        continue;
      }
      if (commands.values.any(
        (old) =>
            old.ownerId == ownerId &&
            old.targetKey == command.targetKey &&
            old.sequence < command.sequence &&
            !old.finished,
      )) {
        continue;
      }
      return commands[command.id] = command.copyWith(
        status: PmSendStatus.preparing,
        attempt: command.attempt + 1,
      );
    }
    return null;
  }

  @override
  Future<bool> changeCommand(
    int ownerId,
    String id, {
    required Set<PmSendStatus> from,
    required PmSendStatus to,
    int? baseline,
    int? attempt,
    String? error,
  }) async {
    final command = commands[id];
    if (command == null ||
        command.ownerId != ownerId ||
        !from.contains(command.status) ||
        (attempt != null && command.attempt != attempt)) {
      return false;
    }
    commands[id] = command.copyWith(
      status: to,
      baseline: baseline,
      error: error,
    );
    return true;
  }

  @override
  Future<void> recoverOutbox(int ownerId) async {
    for (final command in commands.values.toList().where(
      (e) => e.ownerId == ownerId,
    )) {
      if (command.status == PmSendStatus.preparing) {
        commands[command.id] = command.copyWith(status: PmSendStatus.queued);
      }
      if (command.status == PmSendStatus.sending) {
        commands[command.id] = command.copyWith(status: PmSendStatus.uncertain);
      }
    }
  }
}
