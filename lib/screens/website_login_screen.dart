import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/website_session.dart';
import '../core/auth/website_cookie_bridge.dart';
import '../core/auth/website_identity.dart' show websiteRecoveryUri;
import '../core/diagnostics/account_diagnostics.dart';
import '../state/account_diagnostics_provider.dart';
import '../state/account_access_controller.dart';
import '../state/session_controller.dart';
import '../state/website_session_controller.dart';
import 'community_page.dart';

/// Lets the user log into bgm.tv once and persist WebView cookies for
/// website-only features (PM, group membership, etc.).
class WebsiteLoginScreen extends ConsumerStatefulWidget {
  const WebsiteLoginScreen({
    super.key,
    this.cookieLoader,
    this.freshLogin = false,
    this.clearBeforeLoad = false,
    this.initialUrl = loginUrl,
  });

  static const loginUrl = 'https://bgm.tv/login';

  final Future<List<WebsiteCookie>> Function()? cookieLoader;
  final bool freshLogin;
  final bool clearBeforeLoad;
  final String initialUrl;

  @override
  ConsumerState<WebsiteLoginScreen> createState() => _WebsiteLoginScreenState();
}

class _WebsiteLoginScreenState extends ConsumerState<WebsiteLoginScreen> {
  List<WebsiteCookie>? _seedCookies;
  String? _seedError;
  int _loadGeneration = 0;
  final _closed = Completer<void>();

  @override
  void dispose() {
    _closed.complete();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadSeedCookies());
  }

  Future<void> _loadSeedCookies() async {
    final generation = ++_loadGeneration;
    // Always prefer disk snapshot over possibly-stale Riverpod memory. Load
    // once up-front so the WebView is initialized with the real cookies;
    // CommunityWebScreen injects seedCookies only during its initState, so a
    // FutureBuilder that completes after first build would silently drop them.
    setState(() {
      _seedCookies = null;
      _seedError = null;
    });
    try {
      if (widget.clearBeforeLoad) {
        await WebsiteCookieBridge.clearBgmCookies(strict: true);
      }
      await WebsiteCookieBridge.waitForPendingCleanup();
      if (!mounted || generation != _loadGeneration) return;
      final cookies = widget.freshLogin
          ? const <WebsiteCookie>[]
          : await Future.any([
              (widget.cookieLoader ?? loadWebsiteSeedCookies)(),
              _closed.future.then((_) => const <WebsiteCookie>[]),
            ]).timeout(const Duration(seconds: 10));
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _seedCookies = cookies);
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _seedError = widget.clearBeforeLoad ? '登录会话清理未完成，请重试' : '无法读取网站登录，请重试';
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
                Text(error, textAlign: TextAlign.center),
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
      return Scaffold(
        appBar: AppBar(title: const Text('补充账号验证')),
        body: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('正在准备登录页面…'),
            ],
          ),
        ),
      );
    }
    return CommunityWebScreen(
      initialUrl: widget.initialUrl,
      title: '验证账号',
      showSectionSwitcher: false,
      seedCookies: cookies,
      enableCookieCapture: true,
      requireBrowserIdentity: true,
      captureActionLabel: '核验登录',
      loginHint: '使用与应用相同的 Bangumi 账号，登录成功后自动返回。',
      onSessionSaved: () {
        if (context.mounted) Navigator.of(context).maybePop(true);
      },
    );
  }
}

Future<bool?> openWebsiteLoginScreen(BuildContext context) =>
    ensureWebsiteAccess(
      context,
      retryVerification: true,
      interactiveRecovery: true,
    );

Future<bool> ensureWebsiteAccess(
  BuildContext context, {
  bool retryVerification = false,
  bool interactiveRecovery = false,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final access = container.read(accountAccessProvider);
  if (container.read(sessionProvider).user == null) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('请先登录 Bangumi 账号')));
    return false;
  }
  // Explicit repair is navigation, not another hidden network check. In
  // particular, an expired/challenged session must reach its recovery page
  // even when the independent HTTP probe is slow or returns a healthy home.
  final before = container.read(websiteSessionProvider);
  final rejected = const {
    WebsiteAccessStatus.expired,
    WebsiteAccessStatus.mismatch,
    WebsiteAccessStatus.challenge,
    WebsiteAccessStatus.cleanupRequired,
  }.contains(before.status);
  if (!interactiveRecovery &&
      !rejected &&
      await access.verify(force: retryVerification)) {
    return true;
  }
  if (!context.mounted) return false;
  final state = container.read(websiteSessionProvider);
  if (!state.requiresLogin && !interactiveRecovery) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(state.message ?? state.statusLabel)));
    return false;
  }
  return access.runLogin(() async {
    container
        .read(accountDiagnosticsProvider)
        .record(
          AccountArea.website,
          AccountEvent.loginOpened,
          state: state.status.index,
        );
    final freshLogin =
        state.status == WebsiteAccessStatus.mismatch ||
        state.status == WebsiteAccessStatus.expired ||
        state.status == WebsiteAccessStatus.cleanupRequired;
    // A rejected HTTP snapshot does not establish that the browser's current
    // cookies are bad. Preserve them and capture the visible account again,
    // without reinjecting the rejected snapshot. Account mismatch still needs
    // cleanup, performed inside the visible route with retry/error feedback.
    if (!context.mounted) return false;
    return await Navigator.of(context).push<bool>(
          MaterialPageRoute<bool>(
            builder: (_) => WebsiteLoginScreen(
              freshLogin: freshLogin,
              clearBeforeLoad:
                  state.status == WebsiteAccessStatus.mismatch ||
                  state.status == WebsiteAccessStatus.cleanupRequired,
              initialUrl: state.status == WebsiteAccessStatus.challenge
                  ? (websiteRecoveryUri(state.recoveryUri)?.toString() ??
                        'https://bgm.tv/pm')
                  : WebsiteLoginScreen.loginUrl,
            ),
          ),
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
  final container = ProviderScope.containerOf(context, listen: false);
  final access = container.read(accountAccessProvider);
  final revision = access.revision;
  if (!await ensureWebsiteAccess(context) || !context.mounted) return;
  if (revision != access.revision) return;
  final WebsiteSessionSnapshot session;
  try {
    // Use the verified owner-bound snapshot, not a second disk read that can
    // race logout, account switching, or a pending cookie-store write.
    session = await access.requireWebsiteSession();
  } on WebsiteAccessException catch (error) {
    if (context.mounted && revision == access.revision) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
    return;
  }
  if (!context.mounted || revision != access.revision) return;
  final cookies = session.cookies;
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
