import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/recommendation_feedback_controller.dart';
import '../state/session_controller.dart';
import 'readable_subject_title.dart';

class RecommendationFeedbackNotice extends ConsumerWidget {
  const RecommendationFeedbackNotice({super.key, required this.ownerId});
  final int ownerId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(recommendationFeedbackProvider(ownerId));
    if (state.error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              state.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            TextButton.icon(
              onPressed: state.loading
                  ? null
                  : () => ref
                        .read(recommendationFeedbackProvider(ownerId).notifier)
                        .retry(),
              icon: const Icon(Icons.refresh_rounded),
              label: Text(state.ready ? '重试保存' : '重新读取'),
            ),
          ],
        ),
      );
    }
    if (state.loading || state.pending.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          state.loading ? '正在读取推荐偏好…' : '正在保存推荐偏好…',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

Future<void> showHiddenRecommendations(BuildContext context, int ownerId) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 720),
      builder: (_) => FractionallySizedBox(
        heightFactor: .8,
        child: _HiddenRecommendations(ownerId: ownerId),
      ),
    );

class _HiddenRecommendations extends ConsumerWidget {
  const _HiddenRecommendations({required this.ownerId});
  final int ownerId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentOwner =
        ref.watch(sessionProvider.select((state) => state.user?.id)) ?? 0;
    final sameAccount = currentOwner == ownerId;
    final state = ref.watch(recommendationFeedbackProvider(ownerId));
    final items = state.hidden.values.toList()
      ..sort((a, b) => b.hiddenAt.compareTo(a.hiddenAt));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '已隐藏作品',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: '关闭',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        if (!sameAccount)
          const Expanded(child: Center(child: Text('账号已变化，请关闭后重新打开')))
        else ...[
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text('只隐藏作品，不改变标签偏好。可随时恢复。'),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
            child: Text(
              '本机记录 · 按账号区分',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: RecommendationFeedbackNotice(ownerId: ownerId),
          ),
          Expanded(
            child: !state.ready
                ? const SizedBox.shrink()
                : items.isEmpty
                ? Center(
                    child: Text(state.pending.isEmpty ? '没有隐藏的作品' : '正在保存更改…'),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return ListTile(
                        key: ValueKey(
                          'hidden-recommendation-${item.subjectId}',
                        ),
                        title: ReadableSubjectTitle(item.title, maxLines: 2),
                        subtitle: Text(item.type.label),
                        trailing: TextButton(
                          onPressed:
                              state.pending.contains(item.subjectId) ||
                                  state.loading
                              ? null
                              : () {
                                  if ((ref.read(sessionProvider).user?.id ??
                                          0) ==
                                      ownerId) {
                                    ref
                                        .read(
                                          recommendationFeedbackProvider(
                                            ownerId,
                                          ).notifier,
                                        )
                                        .restore(item.subjectId);
                                  }
                                },
                          child: const Text('恢复'),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ],
    );
  }
}
