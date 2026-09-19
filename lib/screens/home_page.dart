import '../navigation/app_destination.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/layout/app_layout.dart';
import '../models/bangumi_models.dart';
import '../models/episode_edit.dart';
import '../widgets/episode_undo_message.dart';
import '../state/notify_controller.dart';
import '../state/session_controller.dart';
import '../state/home_pins_controller.dart';
import '../widgets/home_pins_sheet.dart';
import '../widgets/episode_grid_sheet.dart';
import '../widgets/friend_qr_actions.dart';
import '../widgets/subject_widgets.dart';
import '../widgets/collection_sync_status.dart';
import '../widgets/continue_watching_tile.dart';
import 'calendar_page.dart';
import 'fan_recommend_page.dart';
import 'notify_page.dart';
import 'library_page.dart';

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
    final user = ref.watch(sessionProvider.select((state) => state.user));
    final sessionMessage = ref.watch(
      sessionProvider.select((state) => state.message),
    );
    final nickname = user?.nickname ?? '';
    final updating = ref.watch(
      sessionProvider.select((state) => state.updatingSubjects),
    );
    final pins = user == null
        ? const HomePinsState(loading: false)
        : ref.watch(homePinsProvider(user.id));
    final pinController = user == null
        ? null
        : ref.read(homePinsProvider(user.id).notifier);
    final watchingAll = orderHomeCollections(collections, pins.ids);
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
      user: user,
      isRefreshing: isRefreshing,
      showRefreshProgress: isRefreshing && collections.isNotEmpty,
      phone: phone,
    );
    final quickActions = _HomeQuickActions(
      onSchedule: onSchedule,
      onCalendar: () => Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const CalendarPage())),
      onRecommend: () => Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const FanRecommendPage())),
      onDiscover: onDiscover,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (desktop)
          Padding(
            padding: EdgeInsets.fromLTRB(
              AppLayout.pagePadding(context),
              AppLayout.pageTopPadding(context),
              AppLayout.pagePadding(context),
              0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [header, const SizedBox(height: 12), quickActions],
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => ref.read(sessionProvider.notifier).refresh(),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                AppLayout.pagePadding(context),
                desktop ? 0 : AppLayout.pageTopPadding(context),
                AppLayout.pagePadding(context),
                60,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1220),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!desktop) ...[
                        header,
                        const SizedBox(height: 12),
                        quickActions,
                      ],
                      const CollectionSyncStatus(),
                      if (sessionMessage != null) ...[
                        const SizedBox(height: 12),
                        MaterialBanner(
                          content: Text(sessionMessage),
                          actions: [
                            TextButton(
                              onPressed: isRefreshing
                                  ? null
                                  : () => ref
                                        .read(sessionProvider.notifier)
                                        .refresh(),
                              child: const Text('重新加载'),
                            ),
                            TextButton(
                              onPressed: ref
                                  .read(sessionProvider.notifier)
                                  .clearMessage,
                              child: const Text('关闭'),
                            ),
                          ],
                        ),
                      ],
                      SizedBox(height: AppLayout.blockGap(context)),
                      _WatchingHeading(
                        count: watchingAll.length,
                        onManage: user == null
                            ? null
                            : () => showHomePinsSheet(context, user.id),
                        onViewAll: () => openCollectionLibrary(
                          context,
                          collectionType: CollectionType.doing,
                        ),
                      ),
                      if (pins.error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(
                            children: [
                              Expanded(child: Text(pins.error!)),
                              TextButton(
                                onPressed: pins.saving
                                    ? null
                                    : pinController?.load,
                                child: const Text('重试'),
                              ),
                            ],
                          ),
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
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final columns = constraints.maxWidth >= 820 ? 2 : 1;
                            final width =
                                (constraints.maxWidth - (columns - 1) * 12) /
                                columns;
                            return Wrap(
                              spacing: 12,
                              runSpacing: 8,
                              children: [
                                for (final collection in watching)
                                  SizedBox(
                                    width: width,
                                    child: ContinueWatchingTile(
                                      key: ValueKey(
                                        'continue-${collection.subjectId}',
                                      ),
                                      collection: collection,
                                      busy: updating.contains(
                                        collection.subjectId,
                                      ),
                                      pinned: pins.ids.contains(
                                        collection.subjectId,
                                      ),
                                      onOpen: () => _openDetail(
                                        context,
                                        collection.subject,
                                      ),
                                      onEpisodes:
                                          collection.subject.type.hasEpisodes
                                          ? () => showEpisodeGridSheet(
                                              context,
                                              ref,
                                              collection,
                                            )
                                          : null,
                                      onNext:
                                          collection.subject.type.hasEpisodes
                                          ? () => _markNext(
                                              context,
                                              ref,
                                              collection,
                                            )
                                          : null,
                                      onPin:
                                          pinController == null ||
                                              !pinController.canEdit
                                          ? null
                                          : () => pinController.setPinned(
                                              collection.subjectId,
                                              !pins.ids.contains(
                                                collection.subjectId,
                                              ),
                                            ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      SizedBox(height: AppLayout.blockGap(context)),
                      SizedBox(height: AppLayout.sectionGap(context)),
                      Text(
                        '进行中 ${watchingAll.length} · 已完成 $completed · 总收藏 ${collections.length}',
                        key: const Key('home-collection-summary'),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
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
    EpisodeUndo? undo;
    final controller = ref.read(sessionProvider.notifier);
    final error = await controller.markNextEpisode(
      collection,
      onUndoReady: (value) => undo = value,
    );
    if (!context.mounted) return;
    if (error != null) {
      showAppMessage(context, error);
    } else if (undo != null) {
      showEpisodeUndoMessage(context, controller, undo!);
    }
  }

  void _openDetail(BuildContext context, Subject subject) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => SubjectRoute(subject: subject)));
  }

  Widget _buildHeader(
    BuildContext context,
    WidgetRef ref, {
    required String greeting,
    required String nickname,
    required BangumiUser? user,
    required bool isRefreshing,
    required bool showRefreshProgress,
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
                phone ? greeting : '$greeting，$nickname',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppLayout.pageTitleStyle(context),
              ),
              const SizedBox(height: 5),
              Text(
                _todayLabel(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
              icon: showRefreshProgress
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync_rounded),
            ),
            if (user != null && phone)
              PopupMenuButton<String>(
                tooltip: '更多操作',
                onSelected: (value) {
                  if (value == 'qr') {
                    showMyFriendQr(context, user);
                  } else {
                    scanAndAddFriend(context, myUsername: user.username);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'qr', child: Text('我的二维码')),
                  PopupMenuItem(value: 'scan', child: Text('扫一扫')),
                ],
              ),
            if (user != null && !phone) ...[
              IconButton(
                visualDensity: phone
                    ? VisualDensity.compact
                    : VisualDensity.standard,
                tooltip: '我的二维码',
                onPressed: () => showMyFriendQr(context, user),
                icon: const Icon(Icons.qr_code_2_rounded),
              ),
              IconButton(
                visualDensity: phone
                    ? VisualDensity.compact
                    : VisualDensity.standard,
                tooltip: '扫一扫',
                onPressed: () =>
                    scanAndAddFriend(context, myUsername: user.username),
                icon: const Icon(Icons.qr_code_scanner_rounded),
              ),
            ],
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
        final minWidth = MediaQuery.textScalerOf(context).scale(14) * 4 + 52;
        final columns = ((constraints.maxWidth + 8) / (minWidth + 8))
            .floor()
            .clamp(1, 4);
        final availableWidth =
            (constraints.maxWidth - 8 * (columns - 1)) / columns;
        final width = columns == 4
            ? availableWidth.clamp(minWidth, minWidth + 40)
            : availableWidth;
        return Wrap(
          key: const Key('home-quick-actions'),
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final action in actions)
              SizedBox(
                width: width,
                child: Tooltip(
                  message: action.subtitle,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.onSurface,
                      backgroundColor: Theme.of(context).colorScheme.surface,
                      alignment: Alignment.centerLeft,
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: action.onTap,
                    icon: Icon(action.icon, color: action.color, size: 19),
                    label: Text(action.title),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _WatchingHeading extends StatelessWidget {
  const _WatchingHeading({
    required this.count,
    required this.onViewAll,
    this.onManage,
  });
  final int count;
  final VoidCallback onViewAll;
  final VoidCallback? onManage;
  @override
  Widget build(BuildContext context) {
    final title = Text('继续追', style: AppLayout.sectionTitleStyle(context));
    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (count > 0 && onManage != null)
          IconButton(
            tooltip: '管理首页置顶',
            onPressed: onManage,
            icon: const Icon(Icons.push_pin_outlined),
          ),
        if (count > 0)
          TextButton(onPressed: onViewAll, child: Text('查看全部（$count）'))
        else
          const Text('0 部'),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 420 &&
            MediaQuery.textScalerOf(context).scale(14) > 18) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              title,
              Align(alignment: Alignment.centerRight, child: actions),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: title),
            actions,
          ],
        );
      },
    );
  }
}
