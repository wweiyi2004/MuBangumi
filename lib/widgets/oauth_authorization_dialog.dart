import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart' as mobile;
import 'package:webview_flutter_windows/webview_flutter_windows.dart'
    as windows;

import '../core/auth/website_cookie_bridge.dart';
import '../core/auth/website_session.dart';
import '../core/auth/bangumi_oauth.dart';

/// Official authorization shares the app WebView cookie jar on mobile and Windows.
///
/// Returns `true` when the authorization UI was accepted long enough for the
/// OAuth flow to continue (callback arrived, or user left the dialog open until
/// the provider finished). Returns `false` only for explicit user cancel before
/// a callback has settled.
Future<bool> showOAuthAuthorizationDialog(
  BuildContext context, {
  required Uri authorizationUri,
  required Future<Uri> callback,
  ValueChanged<List<WebsiteCookie>>? onCookiesCaptured,
  bool Function(Uri)? onAuthorizationRedirect,
}) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _OAuthAuthorizationDialog(
        authorizationUri: authorizationUri,
        callback: callback,
        onCookiesCaptured: onCookiesCaptured,
        onAuthorizationRedirect: onAuthorizationRedirect,
      ),
    ) ??
    false;

class _OAuthAuthorizationDialog extends StatefulWidget {
  const _OAuthAuthorizationDialog({
    required this.authorizationUri,
    required this.callback,
    this.onCookiesCaptured,
    this.onAuthorizationRedirect,
  });

  final Uri authorizationUri;
  final Future<Uri> callback;
  final ValueChanged<List<WebsiteCookie>>? onCookiesCaptured;
  final bool Function(Uri)? onAuthorizationRedirect;

  @override
  State<_OAuthAuthorizationDialog> createState() =>
      _OAuthAuthorizationDialogState();
}

class _OAuthAuthorizationDialogState extends State<_OAuthAuthorizationDialog> {
  windows.WebviewController? _controller;
  mobile.WebViewController? _mobileController;
  bool _usedExternalBrowser = false;
  List<WebsiteCookie> _redirectCookies = const [];
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  bool _ready = false;
  bool _loading = true;
  bool _finished = false;
  bool _callbackSettled = false;
  bool _initializing = false;
  bool _disposed = false;
  Future<void>? _disposing;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.callback.then<void>(
      (_) async {
        _callbackSettled = true;
        // Callback success/failure both keep the launcher "opened" so
        // authorize() can observe the same Future and surface the real result.
        await _completeAuthorization();
      },
      onError: (Object _, StackTrace _) {
        _callbackSettled = true;
        _finish(accepted: true);
      },
    );
    unawaited(_initialize());
  }

  Future<void> _completeAuthorization() async {
    if (_finished || _disposed) return;
    if (!_usedExternalBrowser) {
      try {
        final cookies = _redirectCookies.isNotEmpty
            ? _redirectCookies
            : await _captureCookies().timeout(const Duration(seconds: 3));
        if (mounted && !_finished && !_disposed) {
          widget.onCookiesCaptured?.call(cookies);
        }
      } catch (_) {
        // Website-session capture is optional; never lose a valid OAuth callback.
      }
    }
    _finish(accepted: true);
  }

  Future<List<WebsiteCookie>> _captureCookies() => WebsiteCookieBridge.capture(
    windowsController: _controller,
    mobileController: _mobileController,
  );

  Future<void> _initializeMobile() async {
    try {
      final saved = await WebsiteSessionStore().read();
      await WebsiteCookieBridge.injectMobile(saved?.cookies ?? const []);
      if (!mounted || _finished || _disposed) return;
      final controller = mobile.WebViewController();
      _mobileController = controller;
      await controller.setJavaScriptMode(mobile.JavaScriptMode.unrestricted);
      await controller.setNavigationDelegate(
        mobile.NavigationDelegate(
          onNavigationRequest: (request) async {
            final uri = Uri.tryParse(request.url);
            if (uri == null) return mobile.NavigationDecision.prevent;
            final redirect = Uri.parse(OAuthConfig.redirectUri);
            if (uri.scheme == redirect.scheme &&
                uri.host == redirect.host &&
                uri.port == redirect.port &&
                uri.path == redirect.path &&
                uri.queryParameters['state'] ==
                    widget.authorizationUri.queryParameters['state']) {
              try {
                _redirectCookies = await _captureCookies().timeout(
                  const Duration(seconds: 3),
                );
              } catch (_) {}
              if (widget.onAuthorizationRedirect?.call(uri) == true) {
                return mobile.NavigationDecision.prevent;
              }
              return mobile.NavigationDecision.navigate;
            }
            // The official OAuth pages and their login challenges stay in this view.
            if (uri.scheme == 'https' &&
                (uri.host == 'bgm.tv' ||
                    uri.host == 'bangumi.tv' ||
                    uri.host == 'chii.in' ||
                    uri.host == 'challenges.cloudflare.com')) {
              return mobile.NavigationDecision.navigate;
            }
            if (uri.scheme == 'about') {
              return mobile.NavigationDecision.navigate;
            }
            return mobile.NavigationDecision.prevent;
          },
          onPageStarted: (_) {
            if (mounted && !_finished) {
              setState(() {
                _loading = true;
                _error = null;
              });
            }
          },
          onPageFinished: (_) {
            if (mounted && !_finished) setState(() => _loading = false);
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame == true &&
                mounted &&
                !_finished &&
                !_callbackSettled) {
              setState(() {
                _loading = false;
                _error = '授权页面加载失败，请重试或改用系统浏览器';
              });
            }
          },
        ),
      );
      if (!mounted || _finished || _disposed) return;
      setState(() => _ready = true);
      await controller.loadRequest(widget.authorizationUri);
    } catch (_) {
      if (mounted && !_finished) {
        setState(() {
          _loading = false;
          _error = '无法打开授权页面，请重试或改用系统浏览器';
        });
      }
    }
  }

  /// Single-flight disposal: dispose() and _initialize() could previously
  /// run this concurrently (interleaving _subscriptions snapshots), and a
  /// controller created mid-dispose could leak. Sharing one future plus a
  /// _disposed flag closes both gaps.
  Future<void> _disposeController() {
    final inFlight = _disposing;
    if (inFlight != null) return inFlight;
    final future = _runDispose();
    _disposing = future;
    return future.whenComplete(() {
      if (identical(_disposing, future)) _disposing = null;
    });
  }

  Future<void> _runDispose() async {
    final subscriptions = List<StreamSubscription<dynamic>>.from(
      _subscriptions,
    );
    _subscriptions.clear();
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    final controller = _controller;
    _controller = null;
    _ready = false;
    if (controller != null) {
      await controller.dispose();
    }
  }

  Future<void> _initialize() async {
    if (_initializing || _finished || _disposed) return;
    _initializing = true;
    try {
      if (!Platform.isWindows) {
        await _initializeMobile();
        return;
      }
      await _disposeController();
      if (!mounted || _finished || _disposed) return;
      final controller = windows.WebviewController();
      _controller = controller;
      try {
        await controller.initialize();
        if (!mounted || _finished || _disposed) {
          await _runDispose();
          return;
        }
        _subscriptions.addAll([
          controller.loadingState.listen((state) {
            if (!mounted || _finished) return;
            setState(() {
              _loading = state == windows.LoadingState.loading;
              _error = null;
            });
          }),
          controller.onLoadError.listen((error) {
            if (!mounted || _finished) return;
            setState(() {
              _loading = false;
              _error = '授权页面加载失败，请重试或改用系统浏览器';
            });
          }),
        ]);
        final saved = await WebsiteSessionStore().read();
        await WebsiteCookieBridge.injectWindows(
          controller,
          saved?.cookies ?? const [],
        );
        if (!mounted || _finished || _disposed) return;
        await controller.setPopupWindowPolicy(
          windows.WebviewPopupWindowPolicy.sameWindow,
        );
        await controller.setDefaultContextMenusEnabled(false);
        _ready = true;
        if (mounted) setState(() {});
        await controller.loadUrl(widget.authorizationUri.toString());
      } catch (error) {
        if (!mounted || _finished) return;
        setState(() {
          _loading = false;
          _error = '无法打开授权窗口，请安装 Microsoft Edge WebView2 Runtime，或改用系统浏览器。';
        });
      }
    } finally {
      _initializing = false;
    }
  }

  void _finish({required bool accepted}) {
    if (!mounted || _finished) return;
    _finished = true;
    Navigator.of(context).pop(accepted);
  }

  void _cancel() {
    // If the provider already finished, do not discard a usable auth code.
    _finish(accepted: _callbackSettled);
  }

  Future<void> _retry() async {
    if (_initializing || _finished) return;
    setState(() {
      _error = null;
      _loading = true;
    });
    if (!_ready ||
        (Platform.isWindows
            ? _controller == null
            : _mobileController == null)) {
      await _initialize();
      return;
    }
    if (Platform.isWindows) {
      await _controller!.loadUrl(widget.authorizationUri.toString());
    } else {
      await _mobileController!.loadRequest(widget.authorizationUri);
    }
  }

  Future<void> _openExternally() async {
    _usedExternalBrowser = true;
    final opened = await launchUrl(
      widget.authorizationUri,
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法打开系统浏览器')));
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_disposeController());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final phone = size.width < 600;
    final width = math.min(980.0, size.width - (phone ? 16 : 64));
    final height = math.min(760.0, size.height - (phone ? 32 : 64));
    final colors = Theme.of(context).colorScheme;
    return Dialog(
      insetPadding: EdgeInsets.all(phone ? 8 : 32),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: width,
        height: height,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 8, 10),
              child: Row(
                children: [
                  Icon(Icons.verified_user_outlined, color: colors.primary),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '登录 Bangumi',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          '官方 bgm.tv · 登录后可直接使用私信与小组',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '在系统浏览器中打开',
                    onPressed: _openExternally,
                    icon: const Icon(Icons.open_in_new_rounded),
                  ),
                  IconButton(
                    tooltip: '取消登录',
                    onPressed: _cancel,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Stack(
                children: [
                  if (_ready && _error == null)
                    if (Platform.isWindows && _controller != null)
                      Positioned.fill(child: windows.Webview(_controller!))
                    else if (_mobileController != null)
                      Positioned.fill(
                        child: mobile.WebViewWidget(
                          controller: _mobileController!,
                        ),
                      ),
                  if (!_ready && _error == null)
                    const Center(child: CircularProgressIndicator()),
                  if (_error != null)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.public_off_rounded,
                              size: 46,
                              color: colors.error,
                            ),
                            const SizedBox(height: 16),
                            Text(_error!, textAlign: TextAlign.center),
                            const SizedBox(height: 18),
                            Wrap(
                              spacing: 10,
                              children: [
                                FilledButton.icon(
                                  onPressed: _retry,
                                  icon: const Icon(Icons.refresh_rounded),
                                  label: const Text('重试'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: _openExternally,
                                  icon: const Icon(Icons.open_in_new_rounded),
                                  label: const Text('改用系统浏览器'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (_loading && _error == null)
                    const Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: LinearProgressIndicator(minHeight: 2),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
