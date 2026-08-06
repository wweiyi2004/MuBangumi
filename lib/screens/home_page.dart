import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/layout/app_layout.dart';
import '../models/bangumi_models.dart';
import '../state/notify_controller.dart';
import '../state/session_controller.dart';
import '../widgets/episode_grid_sheet.dart';
import '../widgets/subject_widgets.dart';
import 'calendar_page.dart';
import 'fan_recommend_page.dart';
import 'notify_page.dart';
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

    final phone = AppLayout.isPhone(context);
    return RefreshIndicator(
      onRefresh: () => ref.read(sessionProvider.notifier).refresh(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: AppLayout.pageInsets(context, top: 24, bottom: 60),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1220),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            phone
                                ? '$greeting\n$nickname'
                                : '$greeting，$nickname',
                            maxLines: phone ? 2 : 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppLayout.pageTitleStyle(context),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            _todayLabel(),
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                              fontSize: phone ? 13 : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Builder(
                              builder: (context) {
                                final unread = ref.watch(
                                  notifyBadgeProvider.select(
                                    (s) => s.unreadCount,
                                  ),
                                );
                                return IconButton.filledTonal(
                                  visualDensity: phone
                                      ? VisualDensity.compact
                                      : VisualDensity.standard,
                                  tooltip: unread > 0
                                      ? '电波提醒（$unread 未读）'
                                      : '电波提醒',
                                  onPressed: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) => const NotifyPage(),
                                      ),
                                    );
                                  },
                                  icon: Badge(
                                    isLabelVisible: unread > 0,
                                    label: Text(
                                      unread > 99 ? '99+' : '$unread',
                                    ),
                                    child: const Icon(
                                      Icons.notifications_outlined,
                                    ),
                                  ),
                                );
                              },
                            ),
                            IconButton.filledTonal(
                              visualDensity: phone
                                  ? VisualDensity.compact
                                  : VisualDensity.standard,
                              tooltip: '每日放送',
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => const CalendarPage(),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.live_tv_outlined),
                            ),
                            IconButton.filledTonal(
                              visualDensity: phone
                                  ? VisualDensity.compact
                                  : VisualDensity.standard,
                              tooltip: '同步收藏',
                              onPressed: isRefreshing
                                  ? null
                                  : () => ref
                                        .read(sessionProvider.notifier)
                                        .refresh(),
                              icon: isRefreshing
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.sync_rounded),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: AppLayout.blockGap(context)),
                _OverviewBanner(
                  watching: watchingAll.length,
                  completed: completed,
                  total: collections.length,
                  onDiscover: onDiscover,
                ),
                SizedBox(height: AppLayout.sectionGap(context)),
                _FanRecommendEntry(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const FanRecommendPage(),
                      ),
                    );
                  },
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
                      Expanded(
                        child: Text(
                          '正在同步其他类型收藏…',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                SizedBox(height: AppLayout.sectionGap(context)),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final type in SubjectType.values)
                      if ((typeCounts[type] ?? 0) > 0)
                        Chip(
                          avatar: Icon(subjectTypeIcon(type), size: 16),
                          label: Text('${type.label} ${typeCounts[type]}'),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                  ],
                ),
                SizedBox(height: AppLayout.blockGap(context)),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '进行中',
                        style: AppLayout.sectionTitleStyle(context),
                      ),
                    ),
                    Text(
                      watchingAll.length > previewLimit
                          ? '显示 $previewLimit / ${watchingAll.length} 部'
                          : '${watchingAll.length} 部',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: phone ? 13 : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
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

class _FanRecommendEntry extends StatelessWidget {
  const _FanRecommendEntry({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final phone = AppLayout.isPhone(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [Color(0x22E95383), Color(0x228B6CEF)],
            ),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              phone ? 12 : 16,
              phone ? 12 : 14,
              12,
              phone ? 12 : 14,
            ),
            child: Row(
              children: [
                Container(
                  width: phone ? 42 : 48,
                  height: phone ? 42 : 48,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFE95383), Color(0xFF8B6CEF)],
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.theater_comedy_rounded,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '番会荐',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        phone
                            ? '按喜好 / 一句话需求，筛出想看的番'
                            : '根据个人喜好或你的要求，智能筛出想看的番剧',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 600;
      final veryNarrow = constraints.maxWidth < 360;
      return Container(
        width: double.infinity,
        padding: EdgeInsets.all(compact ? 16 : 24),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF272E47), Color(0xFF3A4262)],
          ),
          borderRadius: BorderRadius.circular(compact ? 20 : 26),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1F27304A),
              blurRadius: 24,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: Builder(
          builder: (context) {
            final stats = Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _StatPill(
                  value: '$watching',
                  label: '进行中',
                  compact: veryNarrow,
                ),
                _StatPill(
                  value: '$completed',
                  label: '已完成',
                  compact: veryNarrow,
                ),
                _StatPill(
                  value: '$total',
                  label: '总收藏',
                  compact: veryNarrow,
                ),
              ],
            );
            final intro = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.auto_awesome_rounded,
                  color: Color(0xFFFF89AD),
                ),
                SizedBox(height: compact ? 10 : 14),
                Text(
                  '今天也有好故事在等你',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontSize: compact ? 18 : null,
                  ),
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
                children: [intro, const SizedBox(height: 16), stats],
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
    },
  );
}

class _StatPill extends StatelessWidget {
  const _StatPill({
    required this.value,
    required this.label,
    this.compact = false,
  });

  final String value;
  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
    width: compact ? 72 : 82,
    padding: EdgeInsets.symmetric(
      horizontal: compact ? 8 : 12,
      vertical: compact ? 10 : 12,
    ),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.white12),
    ),
    child: Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: Colors.white,
            fontSize: compact ? 18 : 21,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white60,
            fontSize: compact ? 11 : 12,
          ),
        ),
      ],
    ),
  );
}
