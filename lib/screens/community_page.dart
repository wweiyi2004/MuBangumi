import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart' as mobile;
import 'package:webview_flutter_windows/webview_flutter_windows.dart'
    as windows;

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

class CommunityWebScreen extends StatefulWidget {
  const CommunityWebScreen({
    super.key,
    this.initialUrl = 'https://bgm.tv/rakuen',
    this.title = 'Bangumi 社区',
    this.showSectionSwitcher = true,
    this.loginHint =
        '社区使用 Bangumi 官方网页。发帖或回复时，需要在这里单独登录一次。',
  });

  final String initialUrl;
  final String title;
  /// When false, hides 超展开/小组 segment chips (e.g. PM / membership flows).
  final bool showSectionSwitcher;
  final String loginHint;

  @override
  State<CommunityWebScreen> createState() => _CommunityWebScreenState();
}

class _CommunityWebScreenState extends State<CommunityWebScreen> {
  final _browserKey = GlobalKey<_CommunityBrowserState>();
  _CommunitySection _section = _CommunitySection.rakuen;
  _BrowserSnapshot _browser = const _BrowserSnapshot();
  bool _showLoginHint = true;

  @override
  void initState() {
    super.initState();
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
    final uri = Uri.tryParse(_browser.url ?? widget.initialUrl);
    if (uri == null ||
        !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法打开系统浏览器')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 620;
    final phone = MediaQuery.sizeOf(context).width < 420;
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
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
                    _BrowserButton(
                      tooltip: '在浏览器中打开',
                      icon: Icons.open_in_new_rounded,
                      onPressed: _openExternally,
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

class _CommunityBrowser extends StatefulWidget {
  const _CommunityBrowser({
    super.key,
    required this.initialUrl,
    required this.onStateChanged,
  });

  final String initialUrl;
  final ValueChanged<_BrowserSnapshot> onStateChanged;

  @override
  State<_CommunityBrowser> createState() => _CommunityBrowserState();
}

class _CommunityBrowserState extends State<_CommunityBrowser> {
  windows.WebviewController? _windowsController;
  mobile.WebViewController? _mobileController;
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  String? _error;
  String? _currentUrl;
  late String _targetUrl;
  bool _ready = false;
  bool _loading = true;
  bool _canGoBack = false;
  bool _canGoForward = false;

  @override
  void initState() {
    super.initState();
    _targetUrl = widget.initialUrl;
    if (Platform.isWindows) {
      unawaited(_initializeWindows());
    } else if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
      _initializeMobile();
    } else {
      _error = '当前平台暂不支持内嵌社区页面，请使用右上角的外部浏览器按钮。';
      _loading = false;
    }
  }

  Future<void> _initializeWindows() async {
    final controller = windows.WebviewController();
    _windowsController = controller;
    try {
      await controller.initialize();
      if (!mounted) return;
      _subscriptions.addAll([
        controller.url.listen((url) {
          _currentUrl = url;
          _notify();
        }),
        controller.loadingState.listen((state) {
          _loading = state == windows.LoadingState.loading;
          _notify();
        }),
        controller.historyChanged.listen((history) {
          _canGoBack = history.canGoBack;
          _canGoForward = history.canGoForward;
          _notify();
        }),
        controller.onLoadError.listen((error) {
          if (!mounted) return;
          setState(() => _error = '页面加载失败（$error）');
        }),
      ]);
      await controller.setPopupWindowPolicy(
        windows.WebviewPopupWindowPolicy.sameWindow,
      );
      await controller.setDefaultContextMenusEnabled(true);
      _ready = true;
      if (mounted) setState(() {});
      await controller.loadUrl(_targetUrl);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '无法启动内嵌浏览器。请确认系统已安装 Microsoft Edge WebView2 Runtime。\n$error';
      });
      _notify();
    }
  }

  void _initializeMobile() {
    final controller = mobile.WebViewController()
      ..setJavaScriptMode(mobile.JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        mobile.NavigationDelegate(
          onPageStarted: (url) {
            _currentUrl = url;
            _loading = true;
            _error = null;
            _notify();
          },
          onPageFinished: (url) async {
            _currentUrl = url;
            _loading = false;
            await _updateMobileHistory();
            _notify();
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame != true) return;
            if (!mounted) return;
            setState(() {
              _loading = false;
              _error = '页面加载失败：${error.description}';
            });
            _notify();
          },
        ),
      );
    _mobileController = controller;
    _ready = true;
    unawaited(controller.loadRequest(Uri.parse(_targetUrl)));
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
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    final windowsController = _windowsController;
    if (windowsController != null) unawaited(windowsController.dispose());
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
