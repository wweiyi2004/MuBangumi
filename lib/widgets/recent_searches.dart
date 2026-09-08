import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/storage/browsing_store.dart';

class RecentSearches extends ConsumerStatefulWidget {
  const RecentSearches({
    super.key,
    required this.account,
    required this.onSelected,
  });
  final String account;
  final ValueChanged<RecentSearch> onSelected;
  @override
  ConsumerState<RecentSearches> createState() => _RecentSearchesState();
}

class _RecentSearchesState extends ConsumerState<RecentSearches> {
  bool _clearing = false;
  Future<void> _clear() async {
    if (_clearing) return;
    setState(() => _clearing = true);
    final account = widget.account;
    try {
      await ref.read(browsingRepositoryProvider).clearSearches(account);
      if (mounted) ref.invalidate(recentSearchesProvider(account));
    } catch (_) {
      if (mounted && widget.account == account) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('未能清空搜索历史，请重试')));
      }
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  @override
  Widget build(BuildContext context) => ref
      .watch(recentSearchesProvider(widget.account))
      .when(
        skipLoadingOnRefresh: false,
        loading: () => const SizedBox.shrink(),
        error: (_, _) => TextButton.icon(
          onPressed: () =>
              ref.invalidate(recentSearchesProvider(widget.account)),
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: const Text('重新读取最近搜索'),
        ),
        data: (items) {
          if (items.isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '最近搜索',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                    TextButton(
                      onPressed: _clearing ? null : _clear,
                      child: const Text('清空历史'),
                    ),
                  ],
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final item in items) ...[
                        Tooltip(
                          message: item.label,
                          child: ActionChip(
                            label: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 220),
                              child: Text(
                                item.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            onPressed: () => widget.onSelected(item),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );
}
