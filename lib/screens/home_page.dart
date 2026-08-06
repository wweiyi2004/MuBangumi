import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/bangumi_models.dart';
import '../state/session_controller.dart';
import '../widgets/episode_grid_sheet.dart';
import '../widgets/subject_widgets.dart';
import 'subject_detail_screen.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key, required this.onDiscover});

  final VoidCallback onDiscover;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Selective watches avoid rebuilding the whole home tree on every token tick.
    final collections = ref.watch(
      sessionProvider.select((state) => state.collections),
    );
    final isRefreshing = ref.watch(
      sessionProvider.select((state) => state.isRefreshing),
    );
    final isLoadingCollections = ref.watch(
      sessionProvider.select((state) => state.isLoadingCollections),
    );
    final nickname = ref.watch(
      sessionProvider.select((state) => state.user?.nickname ?? ''),
    );
    final updating = ref.watch(
      sessionProvider.select((state) => state.updatingSubjects),
    );
    final watchingAll = collections
        .where((item) => item.type == CollectionType.doing)
        .toList();
    // Cap rendered tiles so huge "doing" lists do not freeze the home page.
    const previewLimit = 12;
    final watching = watchingAll.length > previewLimit
        ? watchingAll.take(previewLimit).toList()
        : watchingAll;
    final completed = collections
        .where((item) => item.type == CollectionType.done)
        .length;
    final typeCounts = {
      for (final type in SubjectType.values)
        type: collections.where((item) => item.subject.type == type).length,
    };
    final hour = DateTime.now().hour;
    final greeting = hour < 11
        ? '早上好'
        : hour < 18
        ? '下午好'
        : '晚上好';

    return RefreshIndicator(
      onRefresh: () => ref.read(sessionProvider.notifier).refresh(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 60),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1220),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$greeting，$nickname',
                            style: Theme.of(context).textTheme.headlineLarge,
                          ),
                          const SizedBox(height: 5),
                          Text(
                            _todayLabel(),
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton.filledTonal(
                      tooltip: '同步收藏',
                      onPressed: isRefreshing
                          ? null
                          : () => ref.read(sessionProvider.notifier).refresh(),
                      icon: isRefreshing
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.sync_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                _OverviewBanner(
                  watching: watchingAll.length,
                  completed: completed,
                  total: collections.length,
                  onDiscover: onDiscover,
                ),
                if (isLoadingCollections) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const SizedBox.square(
                        dimension: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '正在同步其他类型收藏…',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 18),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final type in SubjectType.values)
                      if ((typeCounts[type] ?? 0) > 0)
                        Chip(
                          avatar: Icon(subjectTypeIcon(type), size: 16),
                          label: Text('${type.label} ${typeCounts[type]}'),
                        ),
                  ],
                ),
                const SizedBox(height: 28),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '进行中',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                    ),
                    Text(
                      watchingAll.length > previewLimit
                          ? '显示 $previewLimit / ${watchingAll.length} 部'
                          : '${watchingAll.length} 部',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (watching.isEmpty)
                  EmptyState(
                    icon: Icons.playlist_add_rounded,
                    title: '还没有进行中的收藏',
                    message: '去发现页搜索喜欢的作品，把它加入“在看 / 在读 / 在玩”。',
                    action: FilledButton.icon(
                      onPressed: onDiscover,
                      icon: const Icon(Icons.explore_rounded),
                      label: const Text('去发现'),
                    ),
                  )
                else
                  SubjectGrid(
                    itemCount: watching.length,
                    itemBuilder: (context, index) {
                      final collection = watching[index];
                      final supportsEpisodes =
                          collection.subject.type.hasEpisodes;
                      return SubjectTile(
                        subject: collection.subject,
                        collection: collection,
                        busy: updating.contains(collection.subjectId),
                        onTap: () => _openDetail(context, collection.subject),
                        onEpisodeGrid: supportsEpisodes
                            ? () =>
                                  showEpisodeGridSheet(context, ref, collection)
                            : null,
                        onNextEpisode: supportsEpisodes
                            ? () => _markNext(context, ref, collection)
                            : null,
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _markNext(
    BuildContext context,
    WidgetRef ref,
    UserCollection collection,
  ) async {
    final error = await ref
        .read(sessionProvider.notifier)
        .markNextEpisode(collection);
    if (!context.mounted) return;
    showAppMessage(context, error ?? '已看完下一集');
  }

  void _openDetail(BuildContext context, Subject subject) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SubjectDetailScreen(subject: subject)),
    );
  }

  String _todayLabel() {
    const weekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    final now = DateTime.now();
    return '${now.month} 月 ${now.day} 日 · ${weekdays[now.weekday - 1]}';
  }
}

class _OverviewBanner extends StatelessWidget {
  const _OverviewBanner({
    required this.watching,
    required this.completed,
    required this.total,
    required this.onDiscover,
  });

  final int watching;
  final int completed;
  final int total;
  final VoidCallback onDiscover;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF272E47), Color(0xFF3A4262)],
      ),
      borderRadius: BorderRadius.circular(26),
      boxShadow: const [
        BoxShadow(
          color: Color(0x1F27304A),
          blurRadius: 24,
          offset: Offset(0, 12),
        ),
      ],
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 600;
        final stats = Wrap(
          spacing: 11,
          runSpacing: 11,
          children: [
            _StatPill(value: '$watching', label: '进行中'),
            _StatPill(value: '$completed', label: '已完成'),
            _StatPill(value: '$total', label: '总收藏'),
          ],
        );
        final intro = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.auto_awesome_rounded, color: Color(0xFFFF89AD)),
            const SizedBox(height: 14),
            Text(
              '今天也有好故事在等你',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 6),
            const Text(
              '轻点 “+” 就能同步下一集进度',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        );
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [intro, const SizedBox(height: 22), stats],
          );
        }
        return Row(
          children: [
            Expanded(child: intro),
            stats,
            const SizedBox(width: 8),
          ],
        );
      },
    ),
  );
}

class _StatPill extends StatelessWidget {
  const _StatPill({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    width: 82,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.white12),
    ),
    child: Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 21,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.white60, fontSize: 12),
        ),
      ],
    ),
  );
}
