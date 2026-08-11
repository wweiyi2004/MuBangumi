import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/website_session.dart';
import '../state/website_session_controller.dart';
import 'community_page.dart';

/// Lets the user log into bgm.tv once and persist WebView cookies for
/// website-only features (PM, group membership, etc.).
class WebsiteLoginScreen extends ConsumerWidget {
  const WebsiteLoginScreen({super.key});

  static const loginUrl = 'https://bgm.tv/login';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Always prefer disk snapshot over possibly-stale Riverpod memory.
    return FutureBuilder<List<WebsiteCookie>>(
      future: loadWebsiteSeedCookies(),
      builder: (context, snapshot) {
        final cookies = snapshot.data ?? const <WebsiteCookie>[];
        return CommunityWebScreen(
          initialUrl: loginUrl,
          title: '同步网站登录',
          showSectionSwitcher: false,
          seedCookies: cookies,
          enableCookieCapture: true,
          captureActionLabel: '保存网站会话',
          loginHint:
              '在此登录 Bangumi 官网后点右上角「保存」。OAuth 与网站会话独立：'
              '收藏走 Token，加组/私信等走网站 Cookie。',
          onCookiesCaptured: (cookies) async {
            final ok = await ref
                .read(websiteSessionProvider.notifier)
                .saveCookies(cookies);
            if (!context.mounted) return;
            final message =
                ref.read(websiteSessionProvider).message ??
                (ok ? '网站登录已同步' : '保存失败');
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(message)));
            if (ok && context.mounted) {
              Navigator.of(context).maybePop(true);
            }
          },
        );
      },
    );
  }
}

Future<bool?> openWebsiteLoginScreen(BuildContext context) {
  return Navigator.of(context).push<bool>(
    MaterialPageRoute<bool>(builder: (_) => const WebsiteLoginScreen()),
  );
}

/// Loads persisted website cookies for WebView injection.
Future<List<WebsiteCookie>> loadWebsiteSeedCookies() async {
  final snapshot = await WebsiteSessionStore().read();
  return snapshot?.cookies ?? const [];
}

/// Opens an official Bangumi page in the in-app WebView with seeded cookies.
Future<void> openSeededCommunityWeb(
  BuildContext context, {
  required String initialUrl,
  required String title,
  bool showSectionSwitcher = true,
  String? loginHint,
}) async {
  final cookies = await loadWebsiteSeedCookies();
  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => CommunityWebScreen(
        initialUrl: initialUrl,
        title: title,
        showSectionSwitcher: showSectionSwitcher,
        seedCookies: cookies,
        loginHint:
            loginHint ??
            (cookies.isEmpty
                ? '官网页面可使用「我的 → 同步网站登录」保存会话，减少重复登录。'
                : '已注入同步的网站会话。若仍提示登录，请重新同步。'),
      ),
    ),
  );
}
