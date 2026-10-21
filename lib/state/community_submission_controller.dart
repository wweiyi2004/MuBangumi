import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/network/community_service.dart';
import '../models/community_topic_submission.dart';
import '../core/auth/website_identity.dart';

enum CommunitySubmissionStatus { publishing, sent, failed, uncertain }

/// Tracks an already-verified single attempt. It never stores or replays tokens.
class CommunityPendingSubmission extends ChangeNotifier {
  CommunityPendingSubmission({
    required this.title,
    required this.content,
    this.draftKey,
    required this.isAccountCurrent,
    required Future<void> Function() send,
    required Future<void> Function(bool rejected) finishDraft,
  }) {
    completion = _run(send, finishDraft);
  }
  final String title, content;
  final String? draftKey;
  final DateTime attemptedAt = DateTime.now();
  final bool Function() isAccountCurrent;
  late final Future<void> completion;
  CommunitySubmissionStatus status = CommunitySubmissionStatus.publishing;
  String? error;
  Future<void> _run(
    Future<void> Function() send,
    Future<void> Function(bool) finishDraft,
  ) async {
    // Let the caller attach the card before starting the request.
    await Future<void>.value();
    try {
      if (!isAccountCurrent()) {
        throw const CommunitySubmissionRejected('账号已变化，尚未提交');
      }
      await send();
      status = CommunitySubmissionStatus.sent;
      try {
        await finishDraft(false);
      } catch (_) {
        error = '已发布，本地草稿清理失败，请勿重复提交';
      }
    } catch (failure) {
      final rejected =
          failure is CommunitySubmissionRejected ||
          failure is WebsiteAccessException;
      status = rejected
          ? CommunitySubmissionStatus.failed
          : CommunitySubmissionStatus.uncertain;
      error = failure is FormatException ? failure.message : failure.toString();
      if (rejected) {
        try {
          await finishDraft(true);
        } catch (_) {
          error = '$error；草稿状态保存失败，请先核对';
          status = CommunitySubmissionStatus.uncertain;
        }
      }
    }
    notifyListeners();
  }
}

final communitySubmissionsProvider =
    ChangeNotifierProvider.family<CommunitySubmissions, CommunityService>((
      ref,
      service,
    ) {
      final entries = CommunitySubmissions();
      service.accountChanges.addListener(entries.changed);
      ref.onDispose(
        () => service.accountChanges.removeListener(entries.changed),
      );
      return entries;
    });

class CommunitySubmissions extends ChangeNotifier {
  final _entries = <String, List<CommunityPendingSubmission>>{};
  bool _disposed = false;
  List<CommunityPendingSubmission> forScope(String scope) =>
      (_entries[scope] ?? [])
          .where((entry) => entry.isAccountCurrent())
          .toList();
  void add(String scope, CommunityPendingSubmission entry) {
    // One persistent draft represents one in-flight attempt for this target.
    final entries = _entries.putIfAbsent(scope, () => []);
    entries.removeWhere((old) {
      if (old.draftKey != entry.draftKey ||
          old.status == CommunitySubmissionStatus.publishing) {
        return false;
      }
      old.removeListener(changed);
      return true;
    });
    entries.add(entry);
    entry.addListener(changed);
    changed();
  }

  void changed() {
    if (!_disposed) notifyListeners();
  }

  void removeDraft(String scope, String? key) {
    _entries[scope]?.removeWhere((entry) {
      if (entry.draftKey != key ||
          entry.status == CommunitySubmissionStatus.publishing) {
        return false;
      }
      entry.removeListener(changed);
      return true;
    });
    changed();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final entry in _entries.values.expand((rows) => rows)) {
      entry.removeListener(changed);
    }
    super.dispose();
  }
}
