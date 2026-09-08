import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/home_pins_controller.dart';
import '../state/session_controller.dart';

Future<void> showHomePinsSheet(BuildContext context, int ownerId) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 700),
      builder: (_) => FractionallySizedBox(
        heightFactor: .8,
        child: _HomePinsPanel(ownerId: ownerId),
      ),
    );

class _HomePinsPanel extends ConsumerWidget {
  const _HomePinsPanel({required this.ownerId});
  final int ownerId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    if (session.user?.id != ownerId) {
      return const Center(child: Text('登录已变化，请重新打开首页置顶'));
    }
    final state = ref.watch(homePinsProvider(ownerId));
    final controller = ref.read(homePinsProvider(ownerId).notifier);
    final items = orderHomeCollections(session.collections, state.ids);
    final pinned = items
        .where((item) => state.ids.contains(item.subjectId))
        .map((item) => item.subjectId)
        .toList();
    final busy = !controller.canEdit;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '首页置顶',
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
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Text('置顶作品优先显示在“继续追”。用箭头调整顺序，已完成的作品会退出首页列表。'),
        ),
        if (state.error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    state.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: state.saving ? null : controller.load,
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        if (state.loading || state.saving) const LinearProgressIndicator(),
        const SizedBox(height: 8),
        Expanded(
          child: items.isEmpty
              ? const Center(child: Text('暂无进行中的作品'))
              : ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final rank = pinned.indexOf(item.subjectId);
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 4, 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                item.subject.displayName,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      rank < 0 ? '未置顶' : '置顶 ${rank + 1}',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                  ),
                                  if (rank >= 0) ...[
                                    IconButton(
                                      tooltip: '上移',
                                      onPressed: busy || rank == 0
                                          ? null
                                          : () => controller.move(
                                              item.subjectId,
                                              pinned[rank - 1],
                                            ),
                                      icon: const Icon(
                                        Icons.arrow_upward_rounded,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: '下移',
                                      onPressed:
                                          busy || rank == pinned.length - 1
                                          ? null
                                          : () => controller.move(
                                              item.subjectId,
                                              pinned[rank + 1],
                                            ),
                                      icon: const Icon(
                                        Icons.arrow_downward_rounded,
                                      ),
                                    ),
                                  ],
                                  IconButton(
                                    tooltip: rank < 0 ? '置顶到首页' : '取消置顶',
                                    onPressed: busy
                                        ? null
                                        : () => controller.setPinned(
                                            item.subjectId,
                                            rank < 0,
                                          ),
                                    icon: Icon(
                                      rank < 0
                                          ? Icons.push_pin_outlined
                                          : Icons.push_pin_rounded,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
