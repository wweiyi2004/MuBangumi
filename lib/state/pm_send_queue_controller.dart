import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/network/pm_service.dart';
import '../core/storage/pm_draft_store.dart';
import '../core/storage/pm_outbox_repository.dart';
import '../models/bangumi_models.dart';
import '../models/pm_models.dart';
import '../models/pm_send_command.dart';
import 'pm_draft_controller.dart';
import 'session_controller.dart';
import 'website_session_controller.dart';
import 'network_status_controller.dart';

final pmSendQueueProvider =
    ChangeNotifierProvider.family<PmSendQueueController, PmService>((
      ref,
      service,
    ) {
      final repository = ref.watch(pmDraftRepositoryProvider);
      final queue = PmSendQueueController(
        repository: repository is PmOutboxRepository
            ? repository as PmOutboxRepository
            : null,
        service: service,
        currentUser: () => ref.read(sessionProvider).user,
      );
      ref.listen(
        sessionProvider.select((state) => state.user?.id),
        (_, _) => queue.accountChanged(),
      );
      ref.listen(websiteSessionProvider, (before, after) {
        if (before?.snapshot?.authenticationKey !=
            after.snapshot?.authenticationKey) {
          queue.invalidateSession();
        }
        if (before?.isSynced != true && after.isSynced) {
          unawaited(queue.resumeWaiting());
        }
      });
      ref.listen(networkStatusProvider, (before, after) {
        if (before != NetworkAvailability.available &&
            after == NetworkAvailability.available) {
          unawaited(queue.resumeWaiting());
        }
      });
      scheduleMicrotask(queue.accountChanged);
      return queue;
    });

class PmSendQueueController extends ChangeNotifier {
  PmSendQueueController({
    required this.repository,
    required this.service,
    required this.currentUser,
  });
  final PmOutboxRepository? repository;
  final PmService service;
  final BangumiUser? Function() currentUser;
  List<PmSendCommand> entries = const [];
  String? error;
  bool get supported => repository != null;
  int get pendingCount => entries.where((e) => !e.finished).length;
  bool _disposed = false, _working = false, _rerun = false;
  int? _owner;
  int _epoch = 0;
  int _readRevision = 0;
  Future<void> _ready = Future.value();
  final Set<int> _recovered = {};

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void accountChanged() {
    if (_disposed || !supported) return;
    final owner = currentUser()?.id;
    if (_owner == owner) return;
    _owner = owner;
    final epoch = ++_epoch;
    entries = const [];
    error = null;
    _notify();
    if (owner == null) return;
    _ready = () async {
      try {
        if (!_recovered.contains(owner)) {
          await repository!.recoverOutbox(owner);
          _recovered.add(owner);
        }
        if (!_disposed && epoch == _epoch) await reload();
      } catch (_) {
        if (!_disposed && epoch == _epoch) {
          error = '发送队列读取失败，请重试';
          _notify();
        }
      }
    }();
    wake();
  }

  void invalidateSession() {
    _epoch++;
    if (supported) wake();
  }

  Future<void> reload() async {
    if (_disposed || !supported) return;
    final owner = currentUser()?.id;
    final epoch = _epoch;
    final revision = ++_readRevision;
    if (!supported || owner == null || _disposed) return;
    try {
      final rows = await repository!.outboxFor(owner);
      if (!_disposed &&
          epoch == _epoch &&
          revision == _readRevision &&
          currentUser()?.id == owner) {
        entries = rows;
        error = null;
        _notify();
      }
    } catch (_) {
      if (!_disposed && epoch == _epoch && revision == _readRevision) {
        error = '发送队列暂时无法读取，请重试';
        _notify();
      }
    }
  }

  Future<PmSendCommand?> enqueue(
    PmDraftController draft, {
    required String receiver,
    String related = '',
  }) async {
    if (!supported || currentUser()?.id != draft.data.ownerId) {
      throw const PmAuthException('账号已变化，请重新打开发送界面');
    }
    accountChanged();
    await _ready;
    if (currentUser()?.id != draft.data.ownerId) throw const PmAuthException();
    final command = await draft.enqueue(receiver: receiver, related: related);
    if (command != null) {
      // The transaction is the acknowledgement. A later list refresh must not
      // turn an accepted message back into input that could be submitted twice.
      if (!_disposed && currentUser()?.id == command.ownerId) {
        _readRevision++;
        entries = [...entries.where((row) => row.id != command.id), command];
        _notify();
      }
      wake();
    }
    return command;
  }

  void wake() {
    if (_disposed || !supported) return;
    if (_working) {
      _rerun = true;
      return;
    }
    unawaited(_run());
  }

  Future<void> _run() async {
    if (_working || _disposed) return;
    _working = true;
    try {
      await _ready;
      while (!_disposed) {
        final readiness = _ready;
        await readiness;
        if (_disposed) break;
        if (!identical(readiness, _ready)) continue;
        final user = currentUser();
        if (user == null || user.id != _owner) break;
        final epoch = _epoch;
        final command = await repository!.claimNext(user.id);
        if (command == null) break;
        var submitted = false;
        try {
          await reload();
          await service.verifyDraftOwner(user);
          PmReplyForm? reply;
          PmComposeParams? compose;
          var baseline = -1;
          if (command.compose) {
            compose = await service.loadComposeParams(command.receiver);
            if (compose.msgReceivers.trim() != command.receiver) {
              throw const _TargetChanged('收件人校验不一致，请取消任务并重新选择收件人');
            }
          } else {
            final detail = await _loadCommandConversation(command);
            reply = detail.form;
            if (reply.msgReceivers.trim() != command.receiver ||
                reply.related != command.related) {
              throw const _TargetChanged('会话目标发生变化，请取消任务并重新打开会话');
            }
            baseline = matchingMessages(detail, command.body);
          }
          if (_disposed || epoch != _epoch || currentUser()?.id != user.id) {
            await repository!.changeCommand(
              user.id,
              command.id,
              attempt: command.attempt,
              from: {PmSendStatus.preparing},
              to: PmSendStatus.queued,
            );
            break;
          }
          final claimed = await repository!.changeCommand(
            user.id,
            command.id,
            attempt: command.attempt,
            from: {PmSendStatus.preparing},
            to: PmSendStatus.sending,
            baseline: baseline,
          );
          if (!claimed) continue;
          await reload();
          // Recheck after the durable transition and immediately before POST.
          if (_disposed || epoch != _epoch || currentUser()?.id != user.id) {
            await repository!.changeCommand(
              user.id,
              command.id,
              attempt: command.attempt,
              from: {PmSendStatus.sending},
              to: PmSendStatus.queued,
            );
            break;
          }
          submitted = true;
          if (compose != null) {
            await service.compose(
              params: compose,
              title: command.title,
              body: command.body,
            );
          } else {
            await service.reply(
              form: reply!,
              body: command.body,
              title: command.title,
            );
          }
          await repository!.changeCommand(
            user.id,
            command.id,
            attempt: command.attempt,
            from: {PmSendStatus.sending},
            to: PmSendStatus.sent,
          );
        } catch (failure) {
          if (!submitted &&
              (_disposed || epoch != _epoch || currentUser()?.id != user.id)) {
            await repository!.changeCommand(
              user.id,
              command.id,
              attempt: command.attempt,
              from: {PmSendStatus.preparing, PmSendStatus.sending},
              to: PmSendStatus.queued,
            );
            break;
          }
          final uncertain =
              failure is PmDeliveryUncertain ||
              (submitted &&
                  failure is PmAuthException &&
                  failure is! PmPreflightAuthException) ||
              (submitted &&
                  failure is! PmException &&
                  failure is! PmAuthException);
          final status = uncertain
              ? PmSendStatus.uncertain
              : failure is PmAuthException ||
                    !submitted && failure is PmException
              ? PmSendStatus.waiting
              : PmSendStatus.failed;
          final message = uncertain
              ? '服务器可能已收到，请先核对结果，勿直接重复发送'
              : failure is PmAuthException
              ? '请补充同一账号的网页登录后继续'
              : failure is PmException
              ? failure.message
              : failure is _TargetChanged
              ? failure.message
              : '发送任务未完成，请检查连接后重试';
          await repository!.changeCommand(
            user.id,
            command.id,
            attempt: command.attempt,
            from: {PmSendStatus.preparing, PmSendStatus.sending},
            to: status,
            error: message,
          );
        }
        await reload();
      }
    } catch (_) {
      error = '发送队列暂时无法处理，请重试';
      _notify();
    } finally {
      _working = false;
      if (_rerun && !_disposed) {
        _rerun = false;
        wake();
      }
    }
  }

  static int matchingMessages(PmConversationDetail detail, String body) =>
      detail.messages
          .where(
            (m) =>
                m.isSelf &&
                m.contentText.replaceAll('\r\n', '\n').trim() ==
                    body.replaceAll('\r\n', '\n').trim(),
          )
          .length;

  Future<PmConversationDetail> _loadCommandConversation(
    PmSendCommand command,
  ) async {
    final detail = await service.loadConversation(command.conversationId);
    // A draft's fallback thread key can be `form.related`, not a valid
    // website filter ID. Only send a filter explicitly advertised by the page.
    if (command.threadId.isNotEmpty &&
        detail.threads.any(
          (thread) => thread.id == command.threadId && !thread.current,
        )) {
      return service.loadConversation(
        command.conversationId,
        threadId: command.threadId,
      );
    }
    return detail;
  }

  Future<void> resumeWaiting() async {
    if (_disposed || !supported) return;
    accountChanged();
    await _ready;
    if (_disposed) return;
    final user = currentUser();
    if (user == null) return;
    try {
      final rows = await repository!.outboxFor(user.id);
      if (_disposed || currentUser()?.id != user.id) return;
      for (final row in rows.where((e) => e.status == PmSendStatus.waiting)) {
        await repository!.changeCommand(
          user.id,
          row.id,
          attempt: row.attempt,
          from: {PmSendStatus.waiting},
          to: PmSendStatus.queued,
        );
      }
      await reload();
      wake();
    } catch (_) {
      if (!_disposed && currentUser()?.id == user.id) {
        error = '发送队列暂时无法恢复，请重试';
        _notify();
      }
    }
  }

  Future<void> retry(
    PmSendCommand command, {
    bool confirmedUncertain = false,
  }) async {
    if (currentUser()?.id != command.ownerId) return;
    await repository!.changeCommand(
      command.ownerId,
      command.id,
      attempt: command.attempt,
      from: {
        PmSendStatus.failed,
        PmSendStatus.waiting,
        if (confirmedUncertain) PmSendStatus.uncertain,
      },
      to: PmSendStatus.queued,
    );
    await reload();
    wake();
  }

  Future<void> cancel(PmSendCommand command) async {
    if (currentUser()?.id != command.ownerId) return;
    await repository!.changeCommand(
      command.ownerId,
      command.id,
      attempt: command.attempt,
      from: {
        PmSendStatus.queued,
        PmSendStatus.waiting,
        PmSendStatus.failed,
        PmSendStatus.uncertain,
      },
      to: PmSendStatus.cancelled,
    );
    await reload();
    wake();
  }

  Future<bool> check(PmSendCommand command) async {
    final user = currentUser();
    if (user == null ||
        user.id != command.ownerId ||
        command.compose ||
        command.baseline < 0) {
      return false;
    }
    final epoch = _epoch;
    await service.verifyDraftOwner(user);
    final detail = await _loadCommandConversation(command);
    if (epoch != _epoch ||
        currentUser()?.id != user.id ||
        detail.form.msgReceivers.trim() != command.receiver ||
        detail.form.related != command.related ||
        matchingMessages(detail, command.body) <= command.baseline) {
      return false;
    }
    final changed = await repository!.changeCommand(
      user.id,
      command.id,
      attempt: command.attempt,
      from: {PmSendStatus.uncertain},
      to: PmSendStatus.sent,
    );
    await reload();
    wake();
    return changed;
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    super.dispose();
  }
}

class _TargetChanged implements Exception {
  const _TargetChanged(this.message);
  final String message;
}
