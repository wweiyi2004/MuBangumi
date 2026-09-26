import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/website_session_controller.dart';
import '../state/session_controller.dart';
import 'package:webview_flutter/webview_flutter.dart' as mobile;
import 'package:webview_flutter_windows/webview_flutter_windows.dart'
    as windows;

import '../core/auth/website_cookie_bridge.dart';
import '../core/auth/website_session.dart';
import '../core/auth/website_identity.dart';
import '../core/diagnostics/account_diagnostics.dart';
import '../state/account_diagnostics_provider.dart';
import '../core/external_link.dart';

enum _CommunitySection {
  rakuen('超展开', Icons.forum_outlined, 'https://bgm.tv/rakuen'),
  groups('小组', Icons.groups_outlined, 'https://bgm.tv/group'),
  discover(
    '发现小组',
    Icons.travel_explore_rounded,
    'https://bgm.tv/group/discover',
  );

  const _CommunitySection(this.label, this.icon, this.url);

  final String label;
  final IconData icon;
  final String url;
}

class CommunityWebScreen extends ConsumerStatefulWidget {
  const CommunityWebScreen({
    super.key,
    this.initialUrl = 'https://bgm.tv/rakuen',
    this.title = 'Bangumi 社区',
    this.showSectionSwitcher = true,
    this.loginHint = '登录后会自动保存，私信与小组等功能共用此登录。',
    this.seedCookies = const [],
    this.enableCookieCapture = false,
    this.onSessionSaved,
    this.captureActionLabel,
    this.requireBrowserIdentity = false,
  });

  final String initialUrl;
  final String title;

  /// When false, hides 超展开/小组 segment chips (e.g. PM / membership flows).
  final bool showSectionSwitcher;
  final String loginHint;

  /// Cookies injected before the first navigation (website session snapshot).
  final List<WebsiteCookie> seedCookies;

  /// Show a button to capture the current WebView cookies.
  final bool enableCookieCapture;
  final VoidCallback? onSessionSaved;
  final String? captureActionLabel;
  final bool requireBrowserIdentity;

  @override
  ConsumerState<CommunityWebScreen> createState() => _CommunityWebScreenState();
}

class _CommunityWebScreenState extends ConsumerState<CommunityWebScreen>
    with WidgetsBindingObserver {
  final _browserKey = GlobalKey<_CommunityBrowserState>();
  _CommunitySection _section = _CommunitySection.rakuen;
  _BrowserSnapshot _browser = const _BrowserSnapshot();
  bool _showLoginHint = true;
  bool _capturing = false;
  late final WebsiteSessionController _session;
  int? _accountId;
  bool _accountChanged = false;
  Timer? _captureTimer;
  bool _foreground = true;
  String? _lastAutomaticCookies;
  Timer? _captureRetryCooldown;
  String? _lastAttemptedCookies;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.enableCookieCapture) {
      // Login panels may submit through AJAX without a page-finished event.
      _captureTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        if (_foreground) unawaited(_captureCookies(automatic: true));
      });
    }
    _session = ref.read(websiteSessionProvider.notifier);
    _accountId = ref.read(sessionProvider).user?.id;
    ref.listenManual(sessionProvider.select((state) => state.user?.id), (
      _,
      next,
    ) {
      if (next != _accountId && mounted) setState(() => _accountChanged = true);
    });
    if (widget.initialUrl.contains('/group/discover')) {
      _section = _CommunitySection.discover;
    } else if (widget.initialUrl.endsWith('/group')) {
      _section = _CommunitySection.groups;
    }
  }

  void _selectSection(_CommunitySection section) {
    setState(() => _section = section);
    _browserKey.currentState?.load(section.url);
  }

  Future<void> _openExternally() async {
    if (widget.enableCookieCapture) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('系统浏览器的登录不会同步到应用。请在当前页面完成账号验证。')),
      );
      return;
    }
    final uri = Uri.tryParse(_browser.url ?? widget.initialUrl);
    if (!await launchExternalLink(uri)) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法打开系统浏览器')));
    }
  }

  Future<void> _captureCookies({bool automatic = false}) async {
    bool sameAccount() =>
        mounted &&
        _accountId != null &&
        ref.read(sessionProvider).user?.id == _accountId;
    if (_capturing || !sameAccount()) return;
    final browser = _browserKey.currentState;
    if (browser == null || !browser.canCapture) return;
    final uri = Uri.tryParse(_browser.url ?? widget.initialUrl);
    if (uri == null || uri.scheme != 'https' || uri.host != 'bgm.tv') return;
    if (uri.path.startsWith('/logout')) {
      return;
    }
    _capturing = true;
    try {
      final cookies = await browser.captureCookies();
      if (!sameAccount()) return;
      final cookieKey = WebsiteSessionSnapshot(
        cookies: cookies,
        syncedAt: DateTime.now(),
      ).cookieHeader;
      if (automatic && cookieKey == _lastAutomaticCookies) return;
      if (automatic &&
          cookieKey == _lastAttemptedCookies &&
          _captureRetryCooldown?.isActive == true) {
        return;
      }
      _lastAttemptedCookies = cookieKey;
      _captureRetryCooldown?.cancel();
      _captureRetryCooldown = Timer(const Duration(seconds: 5), () {});
      final identity = await browser.captureIdentity(cookies);
      if (!mounted || !sameAccount()) return;
      if (identity == null &&
          (widget.requireBrowserIdentity ||
              ref.read(websiteSessionProvider).status ==
                  WebsiteAccessStatus.challenge)) {
        return;
      }
      // A cookie can still be present while this route displays a challenge.
      // Do not let a separate healthy homepage probe dismiss that page.
      if (identity != null &&
          identity.identifierFor(
                WebsiteSessionSnapshot(
                  cookies: cookies,
                  syncedAt: DateTime.now(),
                ),
              ) ==
              null) {
        if (!automatic) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('请在当前页面完成登录或网页验证后再核验')));
        }
        return;
      }
      await _session.attachAccount(ref.read(sessionProvider).user);
      if (!sameAccount()) return;
      final saved = await _session.captureCookies(
        () async {
          return sameAccount() ? cookies : const [];
        },
        automatic: automatic,
        browserIdentity: identity,
      );
      if (!mounted || !sameAccount()) return;
      final verified = saved && await _session.ensureVerified();
      if (!mounted || !sameAccount()) return;
      if (verified) {
        // Cache only successes. A failed probe must be retried after the page
        // finishes login/challenge, even when the auth cookie did not change.
        _lastAutomaticCookies = cookieKey;
        widget.onSessionSaved?.call();
      } else if (!automatic) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ref.read(websiteSessionProvider).message ?? '请完成登录后重试',
            ),
          ),
        );
      }
    } catch (_) {
      if (!automatic && sameAccount()) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('无法读取网页登录，请重试')));
      }
    } finally {
      _capturing = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
  }

  @override
  void dispose() {
    _captureTimer?.cancel();
    _captureRetryCooldown?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_accountChanged) {
      return Scaffold(
        appBar: AppBar(title: const Text('账号已变化')),
        body: const Center(child: Text('请返回后重新打开此页面')),
      );
    }
    final compact = MediaQuery.sizeOf(context).width < 620;
    final phone = MediaQuery.sizeOf(context).width < 420;
    final accountStatus = ref.watch(websiteSessionProvider);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            phone ? 10 : (compact ? 12 : 20),
            phone ? 8 : 12,
            phone ? 8 : (compact ? 12 : 20),
            12,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: compact ? 2 : 0),
                child: Row(
                  children: [
                    if (Navigator.canPop(context))
                      IconButton(
                        visualDensity: phone
                            ? VisualDensity.compact
                            : VisualDensity.standard,
                        tooltip: '返回',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                    Expanded(
                      child: Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: phone
                            ? Theme.of(context).textTheme.titleLarge
                            : Theme.of(context).textTheme.headlineMedium,
                      ),
                    ),
                    _BrowserButton(
                      tooltip: '后退',
                      icon: Icons.arrow_back_rounded,
                      enabled: _browser.canGoBack,
                      onPressed: () => _browserKey.currentState?.goBack(),
                    ),
                    _BrowserButton(
                      tooltip: '前进',
                      icon: Icons.arrow_forward_rounded,
                      enabled: _browser.canGoForward,
                      onPressed: () => _browserKey.currentState?.goForward(),
                    ),
                    _BrowserButton(
                      tooltip: '刷新',
                      icon: Icons.refresh_rounded,
                      onPressed: () => _browserKey.currentState?.reload(),
                    ),
                    if (!widget.enableCookieCapture)
                      _BrowserButton(
                        tooltip: '在浏览器中打开',
                        icon: Icons.open_in_new_rounded,
                        onPressed: _openExternally,
                      ),
                    if (widget.enableCookieCapture)
                      _BrowserButton(
                        tooltip: widget.captureActionLabel ?? '保存网站会话',
                        icon: Icons.verified_user_outlined,
                        onPressed: () => _captureCookies(),
                      ),
                  ],
                ),
              ),
              if (widget.showSectionSwitcher) ...[
                const SizedBox(height: 14),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SegmentedButton<_CommunitySection>(
                    segments: [
                      for (final section in _CommunitySection.values)
                        ButtonSegment(
                          value: section,
                          icon: Icon(section.icon, size: 19),
                          label: Text(section.label),
                        ),
                    ],
                    selected: {_section},
                    onSelectionChanged: (value) => _selectSection(value.first),
                    showSelectedIcon: false,
                  ),
                ),
              ],
              if (widget.enableCookieCapture &&
                  (accountStatus.message != null ||
                      accountStatus.status == WebsiteAccessStatus.checking))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      if (accountStatus.status == WebsiteAccessStatus.checking)
                        const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          accountStatus.message ?? accountStatus.statusLabel,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      if (accountStatus.status != WebsiteAccessStatus.checking)
                        TextButton(
                          onPressed: () => _captureCookies(),
                          child: const Text('重新核验'),
                        ),
                    ],
                  ),
                ),
              if (_showLoginHint) ...[
                const SizedBox(height: 12),
                Material(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 9, 6, 9),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 20,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSecondaryContainer,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            widget.loginHint,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        IconButton(
                          tooltip: '关闭提示',
                          visualDensity: VisualDensity.compact,
                          onPressed: () =>
                              setState(() => _showLoginHint = false),
                          icon: const Icon(Icons.close_rounded, size: 19),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: _CommunityBrowser(
                            key: _browserKey,
                            initialUrl: widget.initialUrl,
                            seedCookies: widget.seedCookies,
                            onPageFinished: () =>
                                unawaited(_captureCookies(automatic: true)),
                            onStateChanged: (value) {
                              if (mounted) setState(() => _browser = value);
                            },
                          ),
                        ),
                        if (_browser.loading)
                          const Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            child: LinearProgressIndicator(minHeight: 2),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BrowserButton extends StatelessWidget {
  const _BrowserButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.enabled = true,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool enabled;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    visualDensity: VisualDensity.compact,
    onPressed: enabled ? onPressed : null,
    icon: Icon(icon),
  );
}

class _BrowserSnapshot {
  const _BrowserSnapshot({
    this.loading = true,
    this.canGoBack = false,
    this.canGoForward = false,
    this.url,
  });

  final bool loading;
  final bool canGoBack;
  final bool canGoForward;
  final String? url;
}

/// Whether [uri] may render inside the address-bar-less embedded browser.
/// Community content can link anywhere, and embedding arbitrary third-party
/// pages in-app invites phishing, so only Bangumi's own domains stay embedded.
@visibleForTesting
bool isBangumiCommunityHost(Uri uri) {
  if (!uri.isScheme('http') && !uri.isScheme('https')) return false;
  final host = uri.host.toLowerCase();
  return host == 'bgm.tv' ||
      host.endsWith('.bgm.tv') ||
      host == 'bangumi.tv' ||
      host.endsWith('.bangumi.tv') ||
      host == 'chii.in' ||
      host.endsWith('.chii.in');
}

/// Intermediate WebView documents that are not community-controlled links.
@visibleForTesting
bool isBenignEmbeddedWebViewUrl(Uri uri) {
  if (!uri.isScheme('about')) return false;
  final target = (uri.path.isNotEmpty ? uri.path : uri.host).toLowerCase();
  return target == 'blank' || target == 'srcdoc';
}

class _CommunityBrowser extends ConsumerStatefulWidget {
  const _CommunityBrowser({
    super.key,
    required this.initialUrl,
    required this.onStateChanged,
    this.onPageFinished,
    this.seedCookies = const [],
  });

  final String initialUrl;
  final ValueChanged<_BrowserSnapshot> onStateChanged;
  final VoidCallback? onPageFinished;
  final List<WebsiteCookie> seedCookies;

  @override
  ConsumerState<_CommunityBrowser> createState() => _CommunityBrowserState();
}

class _CommunityBrowserState extends ConsumerState<_CommunityBrowser> {
  bool get canCapture => _ready;
  windows.WebviewController? _windowsController;
  Future<void>? _windowsInitialization;
  mobile.WebViewController? _mobileController;
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  String? _error;
  String? _currentUrl;
  late String _targetUrl;

  String? _lastBangumiUrl;
  bool _ready = false;
  bool _loading = true;
  bool _canGoBack = false;
  bool _canGoForward = false;
  bool _initializing = false;
  final _closed = Completer<void>();

  Future<void> _waitForBrowser(Future<void> operation, {int seconds = 10}) =>
      Future.any([
        operation,
        _closed.future,
      ]).timeout(Duration(seconds: seconds));

  void _disposeWindows(
    windows.WebviewController controller,
    Future<void>? startup,
  ) {
    unawaited(
      () async {
        try {
          await startup;
        } catch (_) {
          // Failed initialization may still have allocated native resources.
        }
        await controller.dispose();
      }().catchError((Object _) {}),
    );
  }

  void _recordBrowser(AccountEvent event) {
    ref.read(accountDiagnosticsProvider).record(AccountArea.website, event);
  }

  @override
  void initState() {
    super.initState();
    _targetUrl = widget.initialUrl;
    final initial = Uri.tryParse(widget.initialUrl);
    if (initial != null && isBangumiCommunityHost(initial)) {
      _lastBangumiUrl = widget.initialUrl;
    }
    if (Platform.isWindows) {
      unawaited(_initializeWindows());
    } else if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
      unawaited(_initializeMobile());
    } else {
      _error = '当前平台暂不支持内嵌社区页面，请使用右上角的外部浏览器按钮。';
      _loading = false;
    }
  }

  Future<void> _initializeWindows() async {
    if (_initializing || !mounted) return;
    _initializing = true;
    setState(() {
      _error = null;
      _loading = true;
      _ready = false;
    });
    _recordBrowser(AccountEvent.browserStarting);
    final controller = windows.WebviewController();
    _windowsController = controller;
    final startup = _windowsInitialization = controller.initialize();
    try {
      await _waitForBrowser(startup, seconds: 15);
      if (!mounted || !identical(_windowsController, controller)) return;
      _subscriptions.addAll([
        controller.url.listen(_handleWindowsUrl),
        controller.loadingState.listen((state) {
          if (!mounted) return;
          _loading = state == windows.LoadingState.loading;
          _notify();
          if (state == windows.LoadingState.navigationCompleted) {
            widget.onPageFinished?.call();
          }
        }),
        controller.historyChanged.listen((history) {
          _canGoBack = history.canGoBack;
          _canGoForward = history.canGoForward;
          _notify();
        }),
        controller.onLoadError.listen((error) {
          if (!mounted) return;
          setState(() => _error = '页面加载失败，请检查网络后重试');
        }),
      ]);
      await _waitForBrowser(
        controller.setPopupWindowPolicy(
          windows.WebviewPopupWindowPolicy.sameWindow,
        ),
      );
      if (!mounted) return;
      await _waitForBrowser(controller.setDefaultContextMenusEnabled(true));
      if (!mounted) return;
      await _waitForBrowser(
        WebsiteCookieBridge.injectWindows(controller, widget.seedCookies),
      );
      if (!mounted) return;
      _ready = true;
      setState(() {});
      await _waitForBrowser(controller.loadUrl(_targetUrl));
      if (mounted) _recordBrowser(AccountEvent.browserReady);
    } catch (error) {
      if (!mounted) return;
      _recordBrowser(
        error is TimeoutException
            ? AccountEvent.browserTimeout
            : AccountEvent.browserFailed,
      );
      for (final subscription in _subscriptions) {
        unawaited(subscription.cancel());
      }
      _subscriptions.clear();
      _windowsController = null;
      // Dispose only after native creation settles, without blocking retry.
      // A late instance must never navigate or replace the current browser.
      _disposeWindows(controller, startup);
      setState(() {
        _ready = false;
        _loading = false;
        _error = error is TimeoutException
            ? '内置浏览器启动超时，请重试；仍无法打开时请重启应用。'
            : '无法启动内置浏览器，请检查 Microsoft Edge WebView2 Runtime 后重试。';
      });
      _notify();
    } finally {
      _initializing = false;
    }
  }

  /// WebView2 has no NavigationStarting hook, so the whitelist is applied
  /// after the URL changes.
  void _handleWindowsUrl(String url) {
    _currentUrl = url;
    _notify();
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (isBangumiCommunityHost(uri)) {
      _lastBangumiUrl = url;
      return;
    }
    if (isBenignEmbeddedWebViewUrl(uri)) return;
    unawaited(_detachWindowsNavigation(url));
  }

  Future<void> _detachWindowsNavigation(String url) async {
    final controller = _windowsController;
    if (controller == null) return;
    try {
      await controller.stop();
    } catch (_) {
      // Navigation may already have finished; restoring still applies.
    }
    final restore = _lastBangumiUrl;
    if (restore != null && restore != url) {
      try {
        await controller.loadUrl(restore);
      } catch (_) {}
    }
    await launchExternalLink(Uri.tryParse(url));
  }

  Future<void> _initializeMobile() async {
    await WebsiteCookieBridge.injectMobile(widget.seedCookies);
    if (!mounted) return;
    final controller = mobile.WebViewController()
      ..setJavaScriptMode(mobile.JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        mobile.NavigationDelegate(
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri == null) return mobile.NavigationDecision.navigate;
            if (isBangumiCommunityHost(uri) ||
                isBenignEmbeddedWebViewUrl(uri)) {
              return mobile.NavigationDecision.navigate;
            }
            unawaited(launchExternalLink(uri));
            return mobile.NavigationDecision.prevent;
          },
          onPageStarted: (url) {
            _currentUrl = url;
            _loading = true;
            _error = null;
            _notify();
          },
          onUrlChange: (change) {
            if (change.url == null) return;
            _currentUrl = change.url;
            _notify();
          },
          onPageFinished: (url) async {
            _currentUrl = url;
            _loading = false;
            await _updateMobileHistory();
            _notify();
            if (mounted) widget.onPageFinished?.call();
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame != true) return;
            if (!mounted) return;
            setState(() {
              _loading = false;
              _error = '页面加载失败，请检查网络后重试';
            });
            _notify();
          },
        ),
      );
    _mobileController = controller;
    _ready = true;
    if (mounted) setState(() {});
    unawaited(controller.loadRequest(Uri.parse(_targetUrl)));
  }

  Future<List<WebsiteCookie>> captureCookies() => WebsiteCookieBridge.capture(
    windowsController: _windowsController,
    mobileController: _mobileController,
  );

  Future<WebsiteBrowserIdentity?> captureIdentity(
    List<WebsiteCookie> cookies,
  ) async {
    if (!_ready) return null;
    final beforeUrl = _currentUrl ?? _targetUrl;
    return WebsiteBrowserIdentity.capture(
      cookies: cookies,
      evaluate: (script) async => Platform.isWindows
          ? await _windowsController?.executeScript(script)
          : await _mobileController?.runJavaScriptReturningResult(script),
      recapture: captureCookies,
      expectedUrl: beforeUrl,
      isCurrent: () => mounted && beforeUrl == (_currentUrl ?? _targetUrl),
    );
  }

  Future<void> _updateMobileHistory() async {
    final controller = _mobileController;
    if (controller == null) return;
    _canGoBack = await controller.canGoBack();
    _canGoForward = await controller.canGoForward();
  }

  void _notify() {
    if (!mounted) return;
    widget.onStateChanged(
      _BrowserSnapshot(
        loading: _loading,
        canGoBack: _canGoBack,
        canGoForward: _canGoForward,
        url: _currentUrl,
      ),
    );
  }

  Future<void> load(String url) async {
    _targetUrl = url;
    if (!_ready) return;
    if (mounted) setState(() => _error = null);
    if (Platform.isWindows) {
      await _windowsController?.loadUrl(url);
    } else {
      await _mobileController?.loadRequest(Uri.parse(url));
    }
  }

  Future<void> goBack() async {
    if (Platform.isWindows) {
      await _windowsController?.goBack();
    } else {
      await _mobileController?.goBack();
      await _updateMobileHistory();
      _notify();
    }
  }

  Future<void> goForward() async {
    if (Platform.isWindows) {
      await _windowsController?.goForward();
    } else {
      await _mobileController?.goForward();
      await _updateMobileHistory();
      _notify();
    }
  }

  Future<void> reload() async {
    if (!_ready) {
      if (Platform.isWindows) unawaited(_initializeWindows());
      return;
    }
    if (mounted) setState(() => _error = null);
    if (Platform.isWindows) {
      await _windowsController?.reload();
    } else {
      await _mobileController?.reload();
    }
  }

  @override
  void dispose() {
    _closed.complete();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    final windowsController = _windowsController;
    if (windowsController != null) {
      _disposeWindows(windowsController, _windowsInitialization);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.public_off_rounded,
                size: 42,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 14),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: reload,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    if (!_ready) return const Center(child: CircularProgressIndicator());
    if (Platform.isWindows) {
      return windows.Webview(_windowsController!);
    }
    return mobile.WebViewWidget(controller: _mobileController!);
  }
}
