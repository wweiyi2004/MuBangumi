import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/website_session.dart';
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
        appBar: AppBar(title: const Text('同步网站登录')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded, size: 48),
                const SizedBox(height: 16),
                Text('读取网站会话失败：$error', textAlign: TextAlign.center),
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
