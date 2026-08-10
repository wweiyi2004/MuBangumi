import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/layout/app_layout.dart';
import '../core/network/bangumi_endpoints.dart';
import '../models/bangumi_models.dart';
import '../state/background_controller.dart';
import '../state/session_controller.dart';
import '../state/theme_controller.dart';
import '../widgets/network_route_picker.dart';
import '../widgets/subject_widgets.dart';
import '../state/notify_controller.dart';
import 'background_settings_sheet.dart';
import 'calendar_page.dart';
import 'collection_stats_page.dart';
import 'friends_page.dart';
import 'notify_page.dart';
import 'pm_page.dart';

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final user = session.user;
    if (user == null) {
      return const Center(child: Text('尚未登录'));
    }
    int count(CollectionType type) =>
        session.collections.where((item) => item.type == type).length;
    final typeCounts = {
      for (final type in SubjectType.values)
        type: session.collections
            .where((item) => item.subject.type == type)
            .length,
    };
    final phone = AppLayout.isPhone(context);
    final background = ref.watch(backgroundSettingsProvider);
    return SingleChildScrollView(
      padding: AppLayout.pageInsets(context, top: 24, bottom: 60),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('我的', style: AppLayout.pageTitleStyle(context)),
              SizedBox(height: phone ? 16 : 24),
              // Stretch full width: previously narrow panes collapsed the card to
              // avatar/text intrinsic width (looked like a thin strip).
              Card(
                child: Padding(
                  padding: EdgeInsets.all(phone ? 14 : 20),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 360;
                      final avatarRadius = compact ? 34.0 : 42.0;
                      final avatar = CircleAvatar(
                        radius: avatarRadius,
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.primaryContainer,
                        backgroundImage: user.avatarUrl.isEmpty
                            ? null
                            : CachedNetworkImageProvider(
                                BangumiEndpoints.imageUrl(user.avatarUrl),
                              ),
                        child: user.avatarUrl.isEmpty
                            ? Text(
                                user.nickname.characters.first.toUpperCase(),
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineMedium,
                              )
                            : null,
                      );
                      final info = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user.nickname,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '@${user.username}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if (user.sign.isNotEmpty) ...[
                            const SizedBox(height: 9),
                            Text(
                              user.sign,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      );
                      // Prefer horizontal 名片; stack only when extremely narrow.
                      if (constraints.maxWidth < 280) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [avatar, const SizedBox(height: 14), info],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          avatar,
                          SizedBox(width: compact ? 14 : 22),
                          Expanded(child: info),
                        ],
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 18),
              LayoutBuilder(
                builder: (context, constraints) {
                  // Avoid three razor-thin stat cards on phone-width panes.
                  final columns = constraints.maxWidth < 340
                      ? 1
                      : constraints.maxWidth < 520
                      ? 2
                      : 3;
                  final gap = 12.0;
                  final width =
                      (constraints.maxWidth - gap * (columns - 1)) / columns;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      _CountCard(
                        width: width,
                        value: count(CollectionType.doing),
                        label: '进行中',
                      ),
                      _CountCard(
                        width: width,
                        value: count(CollectionType.done),
                        label: '已完成',
                      ),
                      _CountCard(
                        width: width,
                        value: session.collections.length,
                        label: '总收藏',
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 14),
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
              const SizedBox(height: 30),
              Text('社交', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.people_alt_rounded),
                      title: const Text('我的好友'),
                      subtitle: const Text('查看好友列表，浏览对方公开收藏'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const FriendsPage(),
                        ),
                      ),
                    ),
                    const Divider(height: 1, indent: 56),
                    Builder(
                      builder: (context) {
                        final unread = ref
                            .watch(notifyBadgeProvider)
                            .unreadCount;
                        return ListTile(
                          leading: Badge(
                            isLabelVisible: unread > 0,
                            label: Text(unread > 99 ? '99+' : '$unread'),
                            child: const Icon(Icons.notifications_outlined),
                          ),
                          title: const Text('电波提醒'),
                          subtitle: Text(
                            unread > 0
                                ? '$unread 条未读 · 原生通知列表'
                                : '原生通知列表（OAuth / P1）',
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const NotifyPage(),
                              ),
                            );
                            if (context.mounted) {
                              ref.read(notifyBadgeProvider.notifier).refresh();
                            }
                          },
                        );
                      },
                    ),
                    const Divider(height: 1, indent: 56),
                    ListTile(
                      leading: const Icon(Icons.mail_outline_rounded),
                      title: const Text('站内短信'),
                      subtitle: const Text('应用内打开官网收件箱（需网站登录）'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => openPmPage(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              Text('发现', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.insights_outlined),
                      title: const Text('收藏统计与年度回顾'),
                      subtitle: Text(
                        session.isLoadingCollections
                            ? '正在同步全部类型收藏，请稍候'
                            : '评分分布、年度记录与 JSON 数据导出',
                      ),
                      trailing: session.isLoadingCollections
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.chevron_right_rounded),
                      onTap: session.isLoadingCollections
                          ? null
                          : () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => CollectionStatsPage(
                                  username: user.username,
                                  collections: session.collections,
                                ),
                              ),
                            ),
                    ),
                    const Divider(height: 1, indent: 56),
                    ListTile(
                      leading: const Icon(Icons.live_tv_outlined),
                      title: const Text('每日放送'),
                      subtitle: const Text('官方放送日历（非本地新番表）'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const CalendarPage(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              Text('设置', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.sync_rounded),
                      title: const Text('立即同步'),
                      subtitle: const Text('重新获取全部类型的 Bangumi 收藏'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => ref.read(sessionProvider.notifier).refresh(),
                    ),
                    const Divider(height: 1, indent: 56),
                    ListTile(
                      leading: const Icon(Icons.brightness_6_outlined),
                      title: const Text('外观主题'),
                      subtitle: Text(_themeLabel(ref.watch(themeModeProvider))),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => _pickTheme(context, ref),
                    ),
                    const Divider(height: 1, indent: 56),
                    ListTile(
                      leading: const Icon(Icons.wallpaper_rounded),
                      title: const Text('背景与毛玻璃'),
                      subtitle: Text(
                        !background.hasImage
                            ? '自选壁纸 · 分层磨砂效果'
                            : background.isActive
                            ? '已启用 · 可调模糊/压暗/玻璃浓度'
                            : '已选图 · 未启用',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => showBackgroundSettingsSheet(context, ref),
                    ),
                    const Divider(height: 1, indent: 56),
                    ListTile(
                      leading: const Icon(Icons.alt_route_rounded),
                      title: const Text('Bangumi 网络线路'),
                      subtitle: Text(
                        '${session.networkRoute.label} · '
                        '${session.networkRoute.description}',
                      ),
                      trailing: session.isRefreshing
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.chevron_right_rounded),
                      onTap: session.isRefreshing
                          ? null
                          : () => showNetworkRoutePicker(context, ref),
                    ),
                    const Divider(height: 1, indent: 56),
                    ListTile(
                      leading: const Icon(Icons.open_in_new_rounded),
                      title: const Text('打开 Bangumi 个人主页'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => launchUrl(
                        Uri.parse(
                          'https://bgm.tv/user/${Uri.encodeComponent(user.username)}',
                        ),
                        mode: LaunchMode.externalApplication,
                      ),
                    ),
                    const Divider(height: 1, indent: 56),
                    ListTile(
                      leading: Icon(
                        Icons.logout_rounded,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      title: Text(
                        '退出登录',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      onTap: () => _confirmSignOut(context, ref),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 26),
              Center(
                child: Text(
                  'MuBangumi 1.1.0 · 数据来自 Bangumi.tv',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _themeLabel(ThemeMode mode) => switch (mode) {
    ThemeMode.light => '浅色',
    ThemeMode.dark => '深色',
    ThemeMode.system => '跟随系统',
  };

  Future<void> _pickTheme(BuildContext context, WidgetRef ref) async {
    final current = ref.read(themeModeProvider);
    final selected = await showModalBottomSheet<ThemeMode>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final mode in ThemeMode.values)
              ListTile(
                leading: Icon(
                  mode == ThemeMode.dark
                      ? Icons.dark_mode_outlined
                      : mode == ThemeMode.light
                      ? Icons.light_mode_outlined
                      : Icons.brightness_auto_outlined,
                ),
                title: Text(_themeLabel(mode)),
                trailing: current == mode
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.pop(context, mode),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (selected != null) {
      await ref.read(themeModeProvider.notifier).setMode(selected);
    }
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出登录？'),
        content: const Text('本机保存的 Access Token 会被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (confirmed == true) await ref.read(sessionProvider.notifier).signOut();
  }
}

class _CountCard extends StatelessWidget {
  const _CountCard({
    required this.width,
    required this.value,
    required this.label,
  });

  final double width;
  final int value;
  final String label;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
        child: Column(
          children: [
            Text('$value', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
