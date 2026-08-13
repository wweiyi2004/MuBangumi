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
  const HomePage({
    super.key,
    required this.onDiscover,
    required this.onSchedule,
  });

  final VoidCallback onDiscover;
  final VoidCallback onSchedule;

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
    const previewLimit = 18;
    final watching = watchingAll.length > previewLimit
        ? watchingAll.take(previewLimit).toList()
        : watchingAll;
    final completed = collections
        .where((item) => item.type == CollectionType.done)
        .length;
    final hour = DateTime.now().hour;
    final greeting = hour < 11
        ? '早上好'
        : hour < 18
        ? '下午好'
        : '晚上好';

    final phone = AppLayout.isPhone(context);
    final desktop = AppLayout.isDesktop(context);
    // On desktop the greeting/notify/sync header stays pinned at the top of
    // the page — the buttons anchored to the window's top-right — instead of
    // scrolling away with the content.
    final header = _buildHeader(
      context,
      ref,
      greeting: greeting,
      nickname: nickname,
      isRefreshing: isRefreshing,
      phone: phone,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (desktop)
          Padding(
            padding: AppLayout.pageInsets(context, top: 24, bottom: 0),
            child: header,
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => ref.read(sessionProvider.notifier).refresh(),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: AppLayout.pageInsets(
                context,
                top: desktop ? 0 : 24,
                bottom: 60,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1220),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!desktop) header,
                      SizedBox(height: AppLayout.blockGap(context)),
                      _HomeStats(
                        watching: watchingAll.length,
                        completed: completed,
                        total: collections.length,
                      ),
                      SizedBox(height: AppLayout.sectionGap(context)),
                      _HomeQuickActions(
                        onSchedule: onSchedule,
                        onCalendar: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const CalendarPage(),
                          ),
                        ),
                        onRecommend: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const FanRecommendPage(),
                          ),
                        ),
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
                      SizedBox(height: AppLayout.blockGap(context)),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '继续追',
                              style: AppLayout.sectionTitleStyle(context),
                            ),
                          ),
                          Text(
                            watchingAll.length > previewLimit
                                ? '显示 $previewLimit / ${watchingAll.length} 部'
                                : '${watchingAll.length} 部',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                              fontSize: phone ? 13 : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      if (watching.isEmpty)
                        isLoadingCollections
                            ? const _HomeCollectionSkeleton()
                            : EmptyState(
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
                        SubjectPosterGrid(
                          itemCount: watching.length,
                          itemBuilder: (context, index) {
                            final collection = watching[index];
                            final supportsEpisodes =
                                collection.subject.type.hasEpisodes;
                            return SubjectPosterCard(
                              subject: collection.subject,
                              collection: collection,
                              busy: updating.contains(collection.subjectId),
                              onTap: () =>
                                  _openDetail(context, collection.subject),
                              onEpisodeGrid: supportsEpisodes
                                  ? () => showEpisodeGridSheet(
                                      context,
                                      ref,
                                      collection,
                                    )
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
          ),
        ),
      ],
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

  Widget _buildHeader(
    BuildContext context,
    WidgetRef ref, {
    required String greeting,
    required String nickname,
    required bool isRefreshing,
    required bool phone,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                phone ? '$greeting\n$nickname' : '$greeting，$nickname',
                maxLines: phone ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                style: AppLayout.pageTitleStyle(context),
              ),
              const SizedBox(height: 5),
              Text(
                _todayLabel(),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: phone ? 13 : null,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Builder(
              builder: (context) {
                final unread = ref.watch(
                  notifyBadgeProvider.select((s) => s.unreadCount),
                );
                return IconButton(
                  visualDensity: phone
                      ? VisualDensity.compact
                      : VisualDensity.standard,
                  tooltip: unread > 0 ? '电波提醒（$unread 未读）' : '电波提醒',
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const NotifyPage(),
                      ),
                    );
                  },
                  icon: Badge(
                    isLabelVisible: unread > 0,
                    label: Text(unread > 99 ? '99+' : '$unread'),
                    child: const Icon(Icons.notifications_outlined),
                  ),
                );
              },
            ),
            IconButton(
              visualDensity: phone
                  ? VisualDensity.compact
                  : VisualDensity.standard,
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
      ],
    );
  }

  String _todayLabel() {
    const weekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    final now = DateTime.now();
    return '${now.month} 月 ${now.day} 日 · ${weekdays[now.weekday - 1]}';
  }
}

class _HomeCollectionSkeleton extends StatelessWidget {
  const _HomeCollectionSkeleton();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return KeyedSubtree(
      key: const ValueKey('home-collection-skeleton'),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = subjectPosterColumnCount(constraints.maxWidth);
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: columns * 2,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.58,
            ),
            itemBuilder: (_, _) => DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _HomeQuickActions extends StatelessWidget {
  const _HomeQuickActions({
    required this.onSchedule,
    required this.onCalendar,
    required this.onRecommend,
    required this.onDiscover,
  });

  final VoidCallback onSchedule;
  final VoidCallback onCalendar;
  final VoidCallback onRecommend;
  final VoidCallback onDiscover;

  @override
  Widget build(BuildContext context) {
    final actions = [
      (
        icon: Icons.calendar_view_week_rounded,
        title: '新番表',
        subtitle: '我的一周',
        color: const Color(0xFF7C6CE7),
        onTap: onSchedule,
      ),
      (
        icon: Icons.live_tv_rounded,
        title: '每日放送',
        subtitle: '官方日历',
        color: const Color(0xFFE95383),
        onTap: onCalendar,
      ),
      (
        icon: Icons.auto_awesome_rounded,
        title: '番会荐',
        subtitle: '按口味推荐',
        color: const Color(0xFFE38A3F),
        onTap: onRecommend,
      ),
      (
        icon: Icons.travel_explore_rounded,
        title: '找新番',
        subtitle: '榜单与搜索',
        color: const Color(0xFF2CA69A),
        onTap: onDiscover,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 620) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            child: Row(
              children: [
                for (var i = 0; i < actions.length; i++) ...[
                  SizedBox(
                    width: 142,
                    child: _QuickActionCard(action: actions[i]),
                  ),
                  if (i != actions.length - 1) const SizedBox(width: 10),
                ],
              ],
            ),
          );
        }
        return Row(
          children: [
            for (var i = 0; i < actions.length; i++) ...[
              Expanded(child: _QuickActionCard(action: actions[i])),
              if (i != actions.length - 1) const SizedBox(width: 12),
            ],
          ],
        );
      },
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({required this.action});

  final ({
    IconData icon,
    String title,
    String subtitle,
    Color color,
    VoidCallback onTap,
  })
  action;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: action.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: action.color.withValues(alpha: .14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: SizedBox.square(
                dimension: 38,
                child: Icon(action.icon, color: action.color, size: 20),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    action.title,
                    maxLines: 1,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    action.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _HomeStats extends StatelessWidget {
  const _HomeStats({
    required this.watching,
    required this.completed,
    required this.total,
  });

  final int watching;
  final int completed;
  final int total;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 16),
    decoration: BoxDecoration(
      border: Border.symmetric(
        horizontal: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
    ),
    child: Row(
      children: [
        Expanded(
          child: _StatItem(value: '$watching', label: '进行中'),
        ),
        const SizedBox(height: 30, child: VerticalDivider()),
        Expanded(
          child: _StatItem(value: '$completed', label: '已完成'),
        ),
        const SizedBox(height: 30, child: VerticalDivider()),
        Expanded(
          child: _StatItem(value: '$total', label: '总收藏'),
        ),
      ],
    ),
  );
}

class _StatItem extends StatelessWidget {
  const _StatItem({required this.value, required this.label});

  final String value;
  final String label;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(value, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 2),
      Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ],
  );
}
