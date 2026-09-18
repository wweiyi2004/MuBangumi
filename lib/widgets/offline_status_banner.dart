import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/network_status_controller.dart';
import '../state/session_controller.dart';

final offlineNoticeVisibleProvider = Provider<bool>((ref) {
  final availability = ref.watch(networkStatusProvider);
  final status = ref.watch(
    sessionProvider.select(
      (s) => (
        phase: s.phase,
        cached: s.isUsingCachedCollections,
        loading: s.isLoadingCollections,
      ),
    ),
  );
  return status.phase == SessionPhase.signedIn &&
      (availability == NetworkAvailability.unavailable ||
          (status.cached && !status.loading));
});

String snapshotDateLabel(DateTime savedAt) {
  final local = savedAt.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}/${two(local.month)}/${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}

/// Consistent context on every route, separate from the pending-write status.
class OfflineStatusBanner extends ConsumerWidget {
  const OfflineStatusBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(offlineNoticeVisibleProvider)) {
      return const SizedBox.shrink();
    }
    final availability = ref.watch(networkStatusProvider);
    final status = ref.watch(
      sessionProvider.select(
        (s) => (
          phase: s.phase,
          cached: s.isUsingCachedCollections,
          loading: s.isLoadingCollections,
          savedAt: s.collectionsSavedAt,
        ),
      ),
    );
    final offline = availability == NetworkAvailability.unavailable;
    final scheme = Theme.of(context).colorScheme;
    final message = offline
        ? '当前无网络 · 可继续查看本地内容，收藏修改会保存在本机'
        : '收藏暂未更新 · 已保留本地内容';
    return Material(
      color: scheme.surfaceContainerHigh,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              Icon(
                offline ? Icons.wifi_off_rounded : Icons.cloud_off_outlined,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$message${status.cached && status.savedAt != null ? '\n收藏快照：${snapshotDateLabel(status.savedAt!)}' : ''}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              TextButton(
                onPressed: status.loading
                    ? null
                    : () async {
                        await ref
                            .read(networkStatusProvider.notifier)
                            .refresh();
                        if (!context.mounted) return;
                        await ref.read(sessionProvider.notifier).refresh();
                      },
                child: Text(status.loading ? '更新中' : '重试'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
