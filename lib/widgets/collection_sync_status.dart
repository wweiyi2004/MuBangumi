import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/session_controller.dart';
import 'sync_issues_sheet.dart';

/// Shows durable local edits where the user changes and browses progress.
class CollectionSyncStatus extends ConsumerStatefulWidget {
  const CollectionSyncStatus({super.key});

  @override
  ConsumerState<CollectionSyncStatus> createState() =>
      _CollectionSyncStatusState();
}

class _CollectionSyncStatusState extends ConsumerState<CollectionSyncStatus> {
  bool _busy = false;
  bool _syncingNow = false;

  Future<void> _activate() async {
    final session = ref.read(sessionProvider);
    if (_busy || session.phase != SessionPhase.signedIn) return;
    final issues = session.blockedSyncCount > 0;
    if (!issues && session.isSyncing) return;
    setState(() {
      _busy = true;
      _syncingNow = !issues;
    });
    try {
      if (issues) {
        await showSyncIssuesSheet(context);
      } else {
        await ref.read(sessionProvider.notifier).syncPendingChanges();
      }
    } catch (_) {
      if (mounted &&
          ref.read(sessionProvider).phase == SessionPhase.signedIn &&
          ref.read(sessionProvider).user?.username == session.user?.username) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(issues ? '暂时无法打开同步问题，请重试' : '暂时无法同步，修改已保存在本机'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _syncingNow = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(
      sessionProvider.select(
        (state) => (
          phase: state.phase,
          pending: state.pendingSyncCount,
          blocked: state.blockedSyncCount,
          syncing: state.isSyncing,
        ),
      ),
    );
    final syncing = status.syncing || _syncingNow;
    if (status.phase != SessionPhase.signedIn ||
        (status.pending == 0 && status.blocked == 0 && !syncing)) {
      return const SizedBox.shrink();
    }
    final issues = status.blocked > 0;
    final waiting = status.pending > status.blocked
        ? status.pending - status.blocked
        : 0;
    final message = issues
        ? '已保存在本机 · ${status.blocked} 项同步失败'
              '${waiting > 0 ? ' · $waiting 项${syncing ? '同步中' : '待同步'}' : ''}'
        : syncing
        ? '正在同步修改${status.pending > 0 ? ' · ${status.pending} 项' : '…'}'
        : '已保存在本机 · ${status.pending} 项待同步';
    final scheme = Theme.of(context).colorScheme;
    final color = issues ? scheme.error : scheme.onSurfaceVariant;
    final label = Row(
      children: [
        SizedBox.square(
          dimension: 20,
          child: syncing && !issues
              ? const CircularProgressIndicator(strokeWidth: 2)
              : Icon(
                  issues
                      ? Icons.sync_problem_rounded
                      : Icons.cloud_upload_outlined,
                  color: color,
                  size: 20,
                ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            style: TextStyle(color: color, fontSize: 13, height: 1.4),
          ),
        ),
      ],
    );
    final action = syncing && !issues
        ? null
        : TextButton(
            onPressed: _busy || (syncing && !issues) ? null : _activate,
            child: Text(issues ? '查看问题' : '立即同步'),
          );
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        color: issues
            ? scheme.errorContainer.withValues(alpha: .45)
            : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (action == null) return label;
              final stacked =
                  constraints.maxWidth < 360 &&
                  MediaQuery.textScalerOf(context).scale(13) > 18;
              return stacked
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        label,
                        Align(alignment: Alignment.centerRight, child: action),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(child: label),
                        const SizedBox(width: 6),
                        action,
                      ],
                    );
            },
          ),
        ),
      ),
    );
  }
}
