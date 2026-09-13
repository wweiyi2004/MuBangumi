import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/storage/community_draft_store.dart';

final shortReviewDraftRepositoryProvider = Provider<CommunityDraftRepository>(
  (_) => CommunityDraftStore.shared,
);

/// Reuses versioned storage; numeric first keys stay outside community exports.
/// Keys use immutable account IDs, so renaming/logging out cannot mix drafts.
class ShortReviewDraft extends ChangeNotifier {
  ShortReviewDraft(
    this.repository, {
    required int ownerId,
    required int subjectId,
    required this.original,
  }) : key = jsonEncode([ownerId, 'short-review', subjectId]),
       text = original;

  final CommunityDraftRepository repository;
  final String key, original;
  String text;
  bool ready = false,
      dirty = false,
      saved = false,
      saving = false,
      submitted = false;
  String? error, conflictingText;
  int _storedRevision = 0, _editRevision = 0;
  bool _disposed = false;
  Timer? _timer;
  Future<void> _writes = Future.value();

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> restore() async {
    try {
      final slot = await repository.loadVersioned(key);
      if (_disposed) return;
      _storedRevision = slot.revision;
      final data = slot.data;
      if (data != null) {
        final base = jsonDecode(data.title) as Map<String, dynamic>;
        if (data.content == original) {
          // Already submitted by a previous process: don't offer a stale draft.
          text = original;
        } else if (base['base'] == original) {
          text = data.content;
          saved = true;
        } else {
          conflictingText = data.content;
        }
      }
      ready = true;
      error = null;
    } catch (_) {
      error = '短评草稿读取失败，请重试';
    }
    _notify();
  }

  void edit(String value) {
    if (!ready || submitted || _disposed) return;
    text = value;
    dirty = true;
    saved = false;
    _editRevision++;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 350), () => unawaited(flush()));
    _notify();
  }

  void recoverConflict() {
    final value = conflictingText;
    conflictingText = null;
    if (value != null) edit(value);
  }

  Future<bool> flush({bool clear = false}) async {
    _timer?.cancel();
    if (!ready) return false;
    if (!clear && (!dirty || submitted)) return true;
    final revision = _editRevision;
    final data = clear
        ? (title: '', content: '')
        : (title: jsonEncode({'base': original}), content: text);
    saving = true;
    _notify();
    final next = _writes.then((_) async {
      _storedRevision = await repository.saveVersioned(
        key,
        data,
        expectedRevision: _storedRevision,
      );
    });
    _writes = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    try {
      await next;
      if (revision == _editRevision) {
        dirty = false;
        saved = !clear;
        error = null;
      }
      return true;
    } catch (e) {
      error = e is CommunityDraftConflict
          ? '草稿已在其他窗口修改，请保留当前文字后重新打开'
          : clear
          ? '短评已提交，旧草稿清理失败，可重试清理'
          : '草稿未保存，请重试';
      return false;
    } finally {
      saving = false;
      _notify();
    }
  }

  Future<bool> markSubmitted() {
    submitted = true;
    return flush(clear: true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    // Captures immutable data before the editor is destroyed.
    if (ready && dirty && !submitted) unawaited(flush());
    _disposed = true;
    super.dispose();
  }
}
