import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/layout/app_layout.dart';
import '../core/network/bangumi_endpoints.dart';
import '../core/update/app_update_service.dart';
import '../models/bangumi_models.dart';
import '../state/background_controller.dart';
import '../state/session_controller.dart';
import '../state/theme_controller.dart';
import '../state/update_controller.dart';
import '../state/website_session_controller.dart';
import '../widgets/network_route_picker.dart';
import '../widgets/github_release_dialog.dart';
import '../widgets/sync_issues_sheet.dart';
import '../widgets/update_ready_dialog.dart';
import '../state/notify_controller.dart';
import 'background_settings_sheet.dart';
import 'calendar_page.dart';
import 'collection_stats_page.dart';
import 'friends_page.dart';
import 'notify_page.dart';
import 'pm_page.dart';
import 'website_login_screen.dart';

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
      padding: EdgeInsets.fromLTRB(
        AppLayout.pagePadding(context),
        AppLayout.pageTopPadding(context),
        AppLayout.pagePadding(context),
        60,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('我的', style: AppLayout.pageTitleStyle(context)),
              SizedBox(height: phone ? 16 : 24),
              Padding(
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
                              user.nickname.isEmpty
                                  ? '?'
                                  : user.nickname.characters.first
                                        .toUpperCase(),
                              style: Theme.of(context).textTheme.headlineMedium,
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
              const SizedBox(height: 10),
              Text(
                [
                  for (final type in SubjectType.values)
                    if ((typeCounts[type] ?? 0) > 0)
                      '${type.label} ${typeCounts[type]}',
                ].join('  ·  '),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 28),
              Text('社交', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Column(
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
                      final unread = ref.watch(notifyBadgeProvider).unreadCount;
                      return ListTile(
                        leading: Badge(
                          isLabelVisible: unread > 0,
                          label: Text(unread > 99 ? '99+' : '$unread'),
                          child: const Icon(Icons.notifications_outlined),
                        ),
                        title: const Text('电波提醒'),
                        subtitle: Text(
                          unread > 0 ? '$unread 条未读' : '查看回复、提及与好友提醒',
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
                    subtitle: const Text('查看和发送私信'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => openPmPage(context),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Text('发现', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.insights_outlined),
                    title: const Text('收藏统计与年度回顾'),
                    subtitle: Text(
                      session.isLoadingCollections
                          ? '正在同步全部类型收藏，请稍候'
                          : '收藏偏好、年度记录与数据导出',
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
                                displayName: user.displayName,
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
                    subtitle: const Text('查看每日播出的动画'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const CalendarPage(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Text('设置', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Column(
                children: [
                  ListTile(
                    leading: Icon(
                      session.blockedSyncCount > 0
                          ? Icons.sync_problem_rounded
                          : session.pendingSyncCount > 0
                          ? Icons.cloud_upload_outlined
                          : Icons.sync_rounded,
                      color: session.blockedSyncCount > 0
                          ? Theme.of(context).colorScheme.error
                          : null,
                    ),
                    title: Text(session.blockedSyncCount > 0 ? '同步问题' : '立即同步'),
                    subtitle: Text(
                      session.pendingSyncCount > 0
                          ? session.blockedSyncCount > 0
                                ? '${session.blockedSyncCount} 条修改同步失败，点击查看原因并处理'
                                : '${session.pendingSyncCount} 条本地修改等待上传，联网后会自动同步'
                          : '收藏已同步，点击刷新',
                    ),
                    trailing: session.isSyncing || session.isRefreshing
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.chevron_right_rounded),
                    onTap: session.isSyncing || session.isRefreshing
                        ? null
                        : () async {
                            if (session.blockedSyncCount > 0) {
                              await showSyncIssuesSheet(context);
                              return;
                            }
                            final controller = ref.read(
                              sessionProvider.notifier,
                            );
                            await controller.syncPendingChanges(
                              retryBlocked: true,
                            );
                            await controller.refresh();
                          },
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
                  _UpdateSettingsTile(),
                  const Divider(height: 1, indent: 56),
                  _WebsiteSessionTile(),
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
              const SizedBox(height: 26),
              Center(
                child: Text(
                  _footerVersionLabel(ref),
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

  String _footerVersionLabel(WidgetRef ref) {
    final snapshot = ref.watch(updateControllerProvider).snapshot;
    if (snapshot == null) {
      return 'MuBangumi · 数据来自 Bangumi.tv';
    }
    return 'MuBangumi ${snapshot.versionLabel} · 数据来自 Bangumi.tv';
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
        content: const Text('退出后需要重新登录，网站登录也会一并清除。'),
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
    if (confirmed == true) {
      await ref.read(sessionProvider.notifier).signOut();
      await ref.read(websiteSessionProvider.notifier).reload();
    }
  }
}

class _WebsiteSessionTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final website = ref.watch(websiteSessionProvider);
    return ListTile(
      leading: Icon(
        website.isSynced
            ? Icons.verified_user_outlined
            : Icons.language_rounded,
      ),
      title: const Text('同步网站登录'),
      subtitle: Text(website.statusLabel),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () async {
        final action = await showModalBottomSheet<String>(
          context: context,
          showDragHandle: true,
          builder: (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.login_rounded),
                  title: Text(website.isSynced ? '重新同步网站登录' : '去官网登录并保存'),
                  subtitle: const Text('使用私信等功能时需要，请登录同一个 Bangumi 账号。'),
                  onTap: () => Navigator.pop(context, 'sync'),
                ),
                if (website.isSynced)
                  ListTile(
                    leading: Icon(
                      Icons.delete_outline_rounded,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    title: Text(
                      '清除网站会话',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    onTap: () => Navigator.pop(context, 'clear'),
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
        if (!context.mounted || action == null) return;
        if (action == 'clear') {
          await ref.read(websiteSessionProvider.notifier).clear();
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                ref.read(websiteSessionProvider).message ?? '已清除网站登录会话',
              ),
            ),
          );
          return;
        }
        final synced = await openWebsiteLoginScreen(context);
        if (!context.mounted) return;
        await ref.read(websiteSessionProvider.notifier).reload();
        if (synced == true && context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('网站登录已保存')));
        }
      },
    );
  }
}

class _UpdateSettingsTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final update = ref.watch(updateControllerProvider);
    final snapshot = update.snapshot;
    final github = update.githubRelease;
    final subtitle = update.busy
        ? '正在检查更新…'
        : github != null
        ? '发现新版本 ${github.version}'
        : snapshot == null
        ? '检查是否有新版本'
        : switch (snapshot.phase) {
            AppUpdatePhase.notChecked => '当前版本 · ${snapshot.versionLabel}',
            AppUpdatePhase.upToDate => '已是最新 · ${snapshot.versionLabel}',
            AppUpdatePhase.outdated => '发现可用更新',
            AppUpdatePhase.restartRequired => '更新已就绪，重启后生效',
            AppUpdatePhase.unavailable => '当前版本 · ${snapshot.versionLabel}',
            AppUpdatePhase.error => snapshot.message ?? '检查失败',
          };

    return ListTile(
      leading: const Icon(Icons.system_update_alt_rounded),
      title: const Text('检查更新'),
      subtitle: Text(subtitle),
      trailing: update.busy
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.chevron_right_rounded),
      onTap: update.busy ? null : () => _checkUpdate(context, ref),
    );
  }

  Future<void> _checkUpdate(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final controller = ref.read(updateControllerProvider.notifier);
    final snapshot = await controller.checkNow(downloadIfOutdated: true);
    if (!context.mounted) return;

    if (snapshot.isRestartReady) {
      final restart = await showUpdateReadyDialog(context, snapshot: snapshot);
      if (restart == true && context.mounted) {
        controller.restartApp();
      }
      return;
    }

    final github = ref.read(updateControllerProvider).githubRelease;
    if (github != null) {
      final result = await showGithubReleaseDialog(
        context,
        currentVersion: snapshot.appVersion,
        currentBuild: snapshot.buildNumber,
        release: github,
      );
      if (result == GithubReleaseDialogResult.skip && context.mounted) {
        await controller.skipGithubRelease(github);
      }
      return;
    }

    final text = switch (snapshot.phase) {
      AppUpdatePhase.notChecked => '尚未完成更新检查',
      AppUpdatePhase.upToDate => '已是最新版本（${snapshot.versionLabel}）',
      AppUpdatePhase.outdated => '发现可用更新，请稍后再试或重启后重试',
      AppUpdatePhase.unavailable =>
        '当前版本 ${snapshot.versionLabel}，可前往 GitHub 查看安装包',
      AppUpdatePhase.error => snapshot.message ?? '检查更新失败',
      AppUpdatePhase.restartRequired => '更新已就绪，请重启应用',
    };
    messenger.showSnackBar(SnackBar(content: Text(text)));
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
  );
}
