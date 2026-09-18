import '../core/update/update_download.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/update/app_update_service.dart';
import '../state/background_controller.dart';
import '../state/session_controller.dart';
import '../state/theme_controller.dart';
import '../state/update_controller.dart';
import '../state/website_session_controller.dart';
import '../widgets/network_route_picker.dart';
import '../widgets/github_release_dialog.dart';
import '../widgets/sync_issues_sheet.dart';
import '../widgets/update_ready_dialog.dart';
import 'background_settings_sheet.dart';
import 'account_status_screen.dart';
import 'backup_page.dart';
import '../features/anime_appreciation/room_pages.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final user = session.user;
    if (user == null) return const Scaffold(body: Center(child: Text('尚未登录')));
    final background = ref.watch(
      backgroundSettingsProvider.select(
        (settings) => (hasImage: settings.hasImage, enabled: settings.enabled),
      ),
    );
    final backgroundActive =
        ref.watch(
          effectiveBackgroundProvider.select((settings) => settings.isActive),
        ) &&
        !MediaQuery.highContrastOf(context);
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
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
                        final controller = ref.read(sessionProvider.notifier);
                        await controller.syncPendingChanges(retryBlocked: true);
                        await controller.refresh();
                      },
              ),
              const Divider(height: 1, indent: 56),
              ListTile(
                leading: const Icon(Icons.backup_outlined),
                title: const Text('本地备份与导入'),
                subtitle: const Text('保存与恢复新番表、偏好和可选草稿'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const BackupPage()),
                ),
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
                      ? '自选壁纸 · 清晰阅读 · 导航材质'
                      : background.enabled && !backgroundActive
                      ? '已选图 · 当前使用纯色界面'
                      : backgroundActive
                      ? '已启用 · 背景模糊/柔化/导航材质'
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
                leading: const Icon(Icons.science_outlined),
                title: const Text('实验性功能'),
                subtitle: const Text('番剧鉴赏 · 番键会'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ExperimentalFeaturesPage(),
                  ),
                ),
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
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                onTap: () => _confirmSignOut(context, ref),
              ),
            ],
          ),
          Center(child: Text(_footerVersionLabel(ref))),
        ],
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
    final user = ref.watch(sessionProvider.select((state) => state.user));
    final website = ref.watch(websiteSessionProvider);
    return ListTile(
      leading: const Icon(Icons.account_circle_outlined),
      title: const Text('Bangumi 账号'),
      subtitle: Text(
        user == null ? '尚未登录' : '@${user.username} · ${website.statusLabel}',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const AccountStatusScreen()),
      ),
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
    final download = ref.read(updateDownloadProvider);
    final cached = ref.read(updateControllerProvider).snapshot;
    if (download.release != null &&
        cached != null &&
        (download.busy ||
            download.phase == UpdateDownloadPhase.ready ||
            download.phase == UpdateDownloadPhase.error)) {
      await showGithubReleaseDialog(
        context,
        currentVersion: cached.appVersion,
        currentBuild: cached.buildNumber,
        release: download.release!,
      );
      return;
    }
    final snapshot = await controller.checkNow(downloadIfOutdated: true);
    if (!context.mounted) return;

    if (snapshot.isRestartReady) {
      await showUpdateReadyDialog(context, snapshot: snapshot);
      return;
    }

    final github = ref.read(updateControllerProvider).githubRelease;
    if (github != null) {
      await showGithubReleaseDialog(
        context,
        currentVersion: snapshot.appVersion,
        currentBuild: snapshot.buildNumber,
        release: github,
      );
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
