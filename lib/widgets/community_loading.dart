import 'package:flutter/material.dart';

class CommunityRefreshStatus extends StatelessWidget {
  const CommunityRefreshStatus({
    super.key,
    required this.loading,
    required this.error,
    required this.onRetry,
  });
  final bool loading;
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (loading) return const LinearProgressIndicator(minHeight: 2);
    if (error == null) return const SizedBox(height: 2);
    return Row(
      children: [
        const Icon(Icons.cloud_off_rounded, size: 18),
        const SizedBox(width: 8),
        const Expanded(child: Text('刷新失败，已保留当前内容')),
        TextButton(onPressed: onRetry, child: const Text('重试')),
      ],
    );
  }
}

class CommunityLoadMoreFooter extends StatelessWidget {
  const CommunityLoadMoreFooter({
    super.key,
    required this.loading,
    required this.hasMore,
    required this.error,
    required this.onLoad,
  });
  final bool loading;
  final bool hasMore;
  final String? error;
  final VoidCallback? onLoad;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(12),
    child: Center(
      child: loading
          ? const SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : error != null
          ? TextButton.icon(
              onPressed: onLoad,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('加载失败，点击重试'),
            )
          : hasMore
          ? TextButton(onPressed: onLoad, child: const Text('加载更多'))
          : const Text('已经到底了'),
    ),
  );
}
