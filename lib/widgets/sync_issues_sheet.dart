import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/storage/bangumi_sync_store.dart';
import '../models/bangumi_models.dart';
import '../state/session_controller.dart';

Future<void> showSyncIssuesSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const SyncIssuesSheet(),
    );

class SyncIssuesSheet extends ConsumerStatefulWidget {
  const SyncIssuesSheet({super.key});

  @override
  ConsumerState<SyncIssuesSheet> createState() => _SyncIssuesSheetState();
}

class _SyncIssuesSheetState extends ConsumerState<SyncIssuesSheet> {
  List<PendingBangumiMutation> _issues = const [];
  final Set<int> _busyIds = {};
  bool _loading = true;
  bool _retryingAll = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<List<PendingBangumiMutation>> _load({bool showSpinner = true}) async {
    if (showSpinner && mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      final issues = await ref
          .read(sessionProvider.notifier)
          .blockedSyncMutations();
      if (!mounted) return issues;
      setState(() {
        _issues = issues;
        _loading = false;
        _loadError = null;
      });
      return issues;
    } catch (error) {
      if (!mounted) return const [];
      setState(() {
        _loading = false;
        _loadError = '读取同步问题失败：${_errorText(error)}';
      });
      return const [];
    }
  }

  Future<void> _retry(PendingBangumiMutation mutation) async {
    if (_busyIds.contains(mutation.id)) return;
    setState(() => _busyIds.add(mutation.id));
    final error = await ref
        .read(sessionProvider.notifier)
        .retryBlockedMutation(mutation);
    final issues = await _load(showSpinner: false);
    if (!mounted) return;
    setState(() => _busyIds.remove(mutation.id));
    final stillBlocked = issues.any(
      (item) => item.id == mutation.id && item.revision == mutation.revision,
    );
    _showMessage(error ?? (stillBlocked ? '重试仍未成功，请查看最新失败原因' : '已重新提交这条修改'));
  }

  Future<void> _retryAll() async {
    if (_retryingAll || _busyIds.isNotEmpty) return;
    setState(() => _retryingAll = true);
    await ref
        .read(sessionProvider.notifier)
        .syncPendingChanges(retryBlocked: true);
    final issues = await _load(showSpinner: false);
    if (!mounted) return;
    setState(() => _retryingAll = false);
    if (issues.isEmpty) {
      _showMessage('失败记录已重新提交同步');
    } else {
      _showMessage('${issues.length} 条修改仍未同步，请查看最新原因');
    }
  }

  Future<void> _discard(PendingBangumiMutation mutation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('不再上传这条修改？'),
        content: const Text('这条修改将不再同步到 Bangumi。当前显示可能暂不变化，下次刷新成功后将恢复为官网上的内容。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('停止上传'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busyIds.add(mutation.id));
    final controller = ref.read(sessionProvider.notifier);
    final error = await controller.discardBlockedMutation(mutation);
    await _load(showSpinner: false);
    if (!mounted) return;
    setState(() => _busyIds.remove(mutation.id));
    if (error != null) {
      _showMessage(error);
      return;
    }
    _showMessage('已停止上传；下次成功刷新后将以服务器数据为准');
    unawaited(controller.refresh(showIndicator: false));
  }

  void _showMessage(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final colorScheme = Theme.of(context).colorScheme;
    return FractionallySizedBox(
      heightFactor: 0.82,
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '同步问题',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: '刷新列表',
                    onPressed: _loading || _retryingAll ? null : _load,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                  const SizedBox(width: 4),
                  FilledButton.tonalIcon(
                    onPressed:
                        _issues.isEmpty || _retryingAll || _busyIds.isNotEmpty
                        ? null
                        : _retryAll,
                    icon: _retryingAll
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync_rounded, size: 18),
                    label: const Text('全部重试'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    '这些修改已保存在本机，但服务器拒绝了上传。你可以查看原因后重试，'
                    '或者停止上传不再需要的任务。',
                    style: TextStyle(color: colorScheme.onErrorContainer),
                  ),
                ),
              ),
            ),
            Expanded(child: _buildBody(session)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(SessionState session) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null) {
      return _SyncIssuesEmptyState(
        icon: Icons.error_outline_rounded,
        message: _loadError!,
        actionLabel: '重试读取',
        onAction: _load,
      );
    }
    if (_issues.isEmpty) {
      return const _SyncIssuesEmptyState(
        icon: Icons.cloud_done_outlined,
        message: '当前没有需要处理的同步问题',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: _issues.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final issue = _issues[index];
        final busy = _busyIds.contains(issue.id);
        return Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _subjectLabel(issue, session),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  _actionLabel(issue, session),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                SelectableText(
                  issue.lastError?.trim().isNotEmpty == true
                      ? issue.lastError!.trim()
                      : '服务器拒绝了这次修改，但没有返回具体原因。',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                const SizedBox(height: 6),
                Text(
                  '尝试 ${issue.attempts} 次 · ${_formatTime(issue.updatedAt)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: Wrap(
                    spacing: 4,
                    children: [
                      TextButton(
                        onPressed: busy || _retryingAll
                            ? null
                            : () => _discard(issue),
                        child: const Text('不再上传'),
                      ),
                      FilledButton.tonal(
                        onPressed: busy || _retryingAll
                            ? null
                            : () => _retry(issue),
                        child: busy
                            ? const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('重试'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SyncIssuesEmptyState extends StatelessWidget {
  const _SyncIssuesEmptyState({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 42,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    ),
  );
}

String _subjectLabel(PendingBangumiMutation mutation, SessionState session) {
  final subjectId = (mutation.payload['subject_id'] as num?)?.toInt();
  if (subjectId != null) {
    final collection = session.collectionFor(subjectId);
    if (collection != null &&
        collection.subject.displayName.trim().isNotEmpty) {
      return collection.subject.displayName;
    }
  }
  final rawSubject = mutation.payload['subject'];
  if (rawSubject is Map) {
    try {
      final subject = Subject.fromJson(Map<String, dynamic>.from(rawSubject));
      if (subject.displayName.trim().isNotEmpty) return subject.displayName;
    } catch (_) {}
  }
  return subjectId == null ? '未知条目' : '条目 #$subjectId';
}

String _actionLabel(PendingBangumiMutation mutation, SessionState session) {
  final payload = mutation.payload;
  return switch (mutation.kind) {
    BangumiMutationKind.collection => _collectionActionLabel(payload, session),
    BangumiMutationKind.episode =>
      '章节 #${payload['episode_id'] ?? '?'}：${_episodeStatusLabel(payload['type'])}',
    BangumiMutationKind.episodesBatch =>
      '批量修改 ${(payload['episode_ids'] as List?)?.length ?? 0} 个章节：'
          '${_episodeStatusLabel(payload['type'])}',
  };
}

String _collectionActionLabel(
  Map<String, dynamic> payload,
  SessionState session,
) {
  final subjectId = (payload['subject_id'] as num?)?.toInt();
  SubjectType type = SubjectType.anime;
  final collection = subjectId == null
      ? null
      : session.collectionFor(subjectId);
  if (collection != null) {
    type = collection.subject.type;
  } else {
    final rawSubject = payload['subject'];
    if (rawSubject is Map) {
      final value = (rawSubject['type'] as num?)?.toInt();
      if (value != null) type = SubjectType.fromValue(value);
    }
  }
  final value = (payload['collection_type'] as num?)?.toInt();
  final status = value == null
      ? '更新收藏资料'
      : CollectionType.fromValue(value).labelFor(type);
  return '收藏修改：$status';
}

String _episodeStatusLabel(Object? value) => switch ((value as num?)?.toInt()) {
  0 => '撤销状态',
  1 => '想看',
  2 => '看过',
  3 => '抛弃',
  _ => '未知状态',
};

String _formatTime(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

String _errorText(Object error) {
  final text = error.toString().replaceFirst('Exception: ', '').trim();
  return text.isEmpty ? '发生了意外错误' : text;
}
