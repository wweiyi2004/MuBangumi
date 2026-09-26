import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/account_access_controller.dart';
import '../state/session_controller.dart';
import '../state/website_session_controller.dart';
import 'website_login_screen.dart';
import '../widgets/account_content_preferences_tile.dart';
import '../widgets/account_diagnostics_dialog.dart';

class AccountStatusScreen extends ConsumerWidget {
  const AccountStatusScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(accountAccessProvider);
    final session = ref.watch(sessionProvider);
    final website = ref.watch(websiteSessionProvider);
    final user = session.user;
    final checking = website.status == WebsiteAccessStatus.checking;
    return Scaffold(
      appBar: AppBar(title: const Text('Bangumi 账号')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            user?.displayName ?? '尚未登录',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          if (user != null) Text('@${user.username}'),
          const SizedBox(height: 20),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              user == null ? Icons.person_outline : Icons.check_circle_outline,
            ),
            title: const Text('收藏与进度'),
            subtitle: Text(user == null ? '需要登录 Bangumi' : '已登录；暂时断网时保留本地内容'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              website.isSynced
                  ? Icons.verified_user_outlined
                  : Icons.chat_bubble_outline,
            ),
            title: const Text('好友聊天与小组操作'),
            subtitle: Text(website.message ?? website.statusLabel),
          ),
          if (checking) const LinearProgressIndicator(),
          if (user != null) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: checking ? null : () => access.verify(force: true),
                  icon: const Icon(Icons.refresh),
                  label: const Text('重新核验'),
                ),
                if (!website.isSynced)
                  FilledButton.icon(
                    onPressed: () => openWebsiteLoginScreen(context),
                    icon: const Icon(Icons.login),
                    label: const Text('补充账号验证'),
                  ),
                if (website.status == WebsiteAccessStatus.cleanupRequired)
                  TextButton(
                    onPressed: () =>
                        ref.read(websiteSessionProvider.notifier).clear(),
                    child: const Text('重试清理会话'),
                  ),
              ],
            ),
            const Divider(height: 32),
            AccountContentPreferencesTile(
              key: ValueKey(user.id),
              onOpenWebsite: () => openSeededCommunityWeb(
                context,
                initialUrl: 'https://bgm.tv/settings',
                title: '官网内容设置',
                showSectionSwitcher: false,
                loginHint: '在「系统设置 → 受限内容」修改并保存，返回后会重新读取账号偏好。',
              ),
            ),
          ],
          const SizedBox(height: 24),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.troubleshoot),
            title: const Text('登录诊断'),
            subtitle: const Text('查看状态记录并导出排查信息'),
            onTap: () => showAccountDiagnostics(context),
          ),
          const Text('网页登录过期不会清除收藏账号。需要时完成验证，即可继续原来的聊天或小组操作。'),
        ],
      ),
    );
  }
}
