import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/website_session.dart';
import '../core/auth/website_cookie_bridge.dart';
import '../state/account_access_controller.dart';
import '../state/session_controller.dart';
import '../state/website_session_controller.dart';
import 'community_page.dart';

/// Lets the user log into bgm.tv once and persist WebView cookies for
/// website-only features (PM, group membership, etc.).
class WebsiteLoginScreen extends ConsumerStatefulWidget {
  const WebsiteLoginScreen({super.key, this.cookieLoader});

  static const loginUrl = 'https://bgm.tv/login';

  final Future<List<WebsiteCookie>> Function()? cookieLoader;

  @override
  ConsumerState<WebsiteLoginScreen> createState() => _WebsiteLoginScreenState();
}

class _WebsiteLoginScreenState extends ConsumerState<WebsiteLoginScreen> {
  List<WebsiteCookie>? _seedCookies;
  String? _seedError;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSeedCookies());
  }

  Future<void> _loadSeedCookies() async {
    // Always prefer disk snapshot over possibly-stale Riverpod memory. Load
    // once up-front so the WebView is initialized with the real cookies;
    // CommunityWebScreen injects seedCookies only during its initState, so a
    // FutureBuilder that completes after first build would silently drop them.
    setState(() {
      _seedCookies = null;
      _seedError = null;
    });
    try {
      await WebsiteCookieBridge.waitForPendingCleanup();
      final cookies = await (widget.cookieLoader ?? loadWebsiteSeedCookies)();
      if (!mounted) return;
      setState(() => _seedCookies = cookies);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _seedError = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cookies = _seedCookies;
    final error = _seedError;
    if (error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('补充账号验证')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded, size: 48),
                const SizedBox(height: 16),
                const Text('无法读取网站登录，请重试', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _loadSeedCookies,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('重试'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (cookies == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return CommunityWebScreen(
      initialUrl: WebsiteLoginScreen.loginUrl,
      title: '验证 Bangumi 账号',
      showSectionSwitcher: false,
      seedCookies: cookies,
      enableCookieCapture: true,
      captureActionLabel: '核验登录',
      loginHint: '使用与应用相同的 Bangumi 账号，登录成功后自动返回。',
      onSessionSaved: () {
        if (context.mounted) Navigator.of(context).maybePop(true);
      },
    );
  }
}

Future<bool?> openWebsiteLoginScreen(BuildContext context) =>
    ensureWebsiteAccess(context, forceLogin: true);

Future<bool> ensureWebsiteAccess(
  BuildContext context, {
  bool forceLogin = false,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final access = container.read(accountAccessProvider);
  if (container.read(sessionProvider).user == null) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('请先登录 Bangumi 账号')));
    return false;
  }
  if (await access.verify()) return true;
  if (!context.mounted) return false;
  final state = container.read(websiteSessionProvider);
  if (!forceLogin && state.status == WebsiteAccessStatus.unavailable) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(state.message ?? state.statusLabel)));
    return false;
  }
  return access.runLogin(() async {
    if (state.status == WebsiteAccessStatus.mismatch ||
        state.status == WebsiteAccessStatus.expired ||
        state.status == WebsiteAccessStatus.cleanupRequired) {
      try {
        await WebsiteCookieBridge.clearBgmCookies(strict: true);
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('登录会话清理失败，请稍后重试')));
        }
        return false;
      }
    }
    if (!context.mounted) return false;
    return await Navigator.of(context).push<bool>(
          MaterialPageRoute<bool>(builder: (_) => const WebsiteLoginScreen()),
        ) ??
        false;
  });
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
  if (!await ensureWebsiteAccess(context) || !context.mounted) return;
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
            (cookies.isEmpty ? '登录一次，私信与小组等功能会自动共用。' : '已使用保存的登录，重新登录后也会自动保存。'),
      ),
    ),
  );
}
