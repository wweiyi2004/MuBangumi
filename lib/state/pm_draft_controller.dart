import 'dart:async';

import 'package:flutter/foundation.dart';
import '../core/storage/pm_draft_store.dart';
import '../core/storage/pm_outbox_repository.dart';
import '../models/pm_send_command.dart';

/// Owns immutable snapshots so saving and clearing remain safe after a route
/// closes or a different conversation takes over its text fields.
class PmDraftController extends ChangeNotifier {
  PmDraftController(this.repository, this.data);
  final PmDraftRepository repository;
  PmDraft data;
  bool loading = true;
  bool saving = false;
  bool saved = false;
  bool sent = false;
  bool dirty = false;
  String? error;
  int _revision = 0;
  int _edit = 0;
  bool _closed = false;
  bool _abandoned = false;
  Timer? _timer;
  Future<void> _operations = Future.value();

  bool get ready => !loading && _loaded;
  bool _loaded = false;
  void _notify() {
    if (!_closed) notifyListeners();
  }

  Future<void> restore({
    bool findLatestCompose = false,
    String? recipient,
    bool fresh = false,
  }) async {
    loading = true;
    error = null;
    _notify();
    try {
      final slot = fresh
          ? const PmDraftSlot()
          : findLatestCompose
          ? await repository.findCompose(data.ownerId, recipient: recipient) ??
                const PmDraftSlot()
          : await repository.read(data.ownerId, data.id);
      if (_closed) return;
      if (slot.draft != null &&
          (slot.draft!.ownerId != data.ownerId ||
              slot.draft!.kind != data.kind)) {
        throw StateError('Mismatched draft context');
      }
      data = slot.draft ?? data;
      _revision = slot.revision;
      _loaded = true;
      saved = slot.draft != null;
      dirty = false;
    } catch (_) {
      if (!_closed) error = '草稿读取失败，请重试';
    } finally {
      loading = false;
      _notify();
    }
  }

  void edit({
    required String recipient,
    required String title,
    required String body,
  }) {
    if (!ready || sent || _closed || _abandoned) return;
    if (data.recipient == recipient &&
        data.title == title &&
        data.body == body) {
      return;
    }
    data = data.edited(recipient: recipient, title: title, body: body);
    _edit++;
    dirty = true;
    saved = false;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 350), () => unawaited(flush()));
    _notify();
  }

  Future<bool> flush() {
    _timer?.cancel();
    if (!ready || sent || _abandoned || !dirty) return Future.value(true);
    final snapshot = data;
    final edit = _edit;
    saving = true;
    _notify();
    final operation = _operations.then((_) async {
      if (sent || _abandoned || (saved && edit == _edit)) return true;
      try {
        _revision = await repository.save(
          snapshot,
          expectedRevision: _revision,
        );
        if (edit == _edit) {
          dirty = false;
          saved = true;
          error = null;
        }
        return true;
      } catch (failure) {
        if (edit == _edit) {
          error = failure is PmDraftConflict
              ? failure.toString()
              : '草稿保存失败，请重试';
        }
        return false;
      } finally {
        if (edit == _edit) saving = false;
        _notify();
      }
    });
    _operations = operation.then<void>((_) {});
    return operation;
  }

  Future<bool> markSent() {
    sent = true;
    saving = true;
    _timer?.cancel();
    _notify();
    final operation = _operations.then((_) async {
      try {
        _revision = await repository.clear(
          data.ownerId,
          data.id,
          expectedRevision: _revision,
        );
        dirty = false;
        saved = false;
        error = null;
        return true;
      } on PmDraftConflict {
        dirty = false;
        saved = false;
        error = '短信已发送；另一处更新的草稿已保留';
        return true;
      } catch (_) {
        error = '短信已发送，但草稿未能清除，请重试清除，勿重复发送';
        return false;
      } finally {
        saving = false;
        _notify();
      }
    });
    _operations = operation.then<void>((_) {});
    return operation;
  }

  /// Durably transfers the captured draft into the outbox in one transaction.
  /// Later edits belong to the next message and must survive this handoff.
  Future<PmSendCommand?> enqueue({
    required String receiver,
    String related = '',
  }) {
    final store = repository;
    if (store is! PmOutboxRepository || !ready || sent || _abandoned) {
      return Future.value();
    }
    _timer?.cancel();
    final snapshot = data;
    final edit = _edit;
    saving = true;
    _notify();
    final operation = _operations.then<PmSendCommand?>((_) async {
      try {
        final result = await (store as PmOutboxRepository).enqueueDraft(
          snapshot,
          expectedRevision: _revision,
          receiver: receiver,
          related: related,
        );
        _revision = result.revision;
        if (_edit == edit) {
          data = snapshot.edited(
            recipient: snapshot.recipient,
            title: snapshot.title,
            body: '',
          );
          dirty = false;
          saved = false;
        }
        error = null;
        return result.command;
      } catch (failure) {
        error = failure is PmDraftConflict
            ? failure.toString()
            : '消息未能保存到发送队列，请重试；输入已保留';
        return null;
      } finally {
        saving = false;
        _notify();
      }
    });
    _operations = operation.then<void>((_) {});
    return operation;
  }

  void abandonPendingEdits() {
    _abandoned = true;
    _timer?.cancel();
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (!sent && dirty && !_abandoned) unawaited(flush());
    _closed = true;
    super.dispose();
  }
}
