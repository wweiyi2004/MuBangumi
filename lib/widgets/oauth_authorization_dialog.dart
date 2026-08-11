import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart'
    as windows;

/// Hosts Bangumi authorize in an in-app WebView2 dialog on Windows.
///
/// Returns `true` when the authorization UI was accepted long enough for the
/// OAuth flow to continue (callback arrived, or user left the dialog open until
/// the provider finished). Returns `false` only for explicit user cancel before
/// a callback has settled.
Future<bool> showOAuthAuthorizationDialog(
  BuildContext context, {
  required Uri authorizationUri,
  required Future<Uri> callback,
}) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _OAuthAuthorizationDialog(
        authorizationUri: authorizationUri,
        callback: callback,
      ),
    ) ??
    false;

class _OAuthAuthorizationDialog extends StatefulWidget {
  const _OAuthAuthorizationDialog({
    required this.authorizationUri,
    required this.callback,
  });

  final Uri authorizationUri;
  final Future<Uri> callback;

  @override
  State<_OAuthAuthorizationDialog> createState() =>
      _OAuthAuthorizationDialogState();
}

class _OAuthAuthorizationDialogState extends State<_OAuthAuthorizationDialog> {
  windows.WebviewController? _controller;
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  bool _ready = false;
  bool _loading = true;
  bool _finished = false;
  bool _callbackSettled = false;
  bool _initializing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.callback.then<void>(
      (_) {
        _callbackSettled = true;
        // Callback success/failure both keep the launcher "opened" so
        // authorize() can observe the same Future and surface the real result.
        _finish(accepted: true);
      },
      onError: (Object _, StackTrace _) {
        _callbackSettled = true;
        _finish(accepted: true);
      },
    );
    unawaited(_initialize());
  }

  Future<void> _disposeController() async {
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
    if (_initializing || _finished) return;
    _initializing = true;
    try {
      await _disposeController();
      if (!mounted || _finished) return;
      final controller = windows.WebviewController();
      _controller = controller;
      try {
        await controller.initialize();
        if (!mounted || _finished) return;
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
              _error = '授权页面加载失败（$error）';
            });
          }),
        ]);
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
          _error =
              '无法启动应用内授权窗口。请确认已安装 Microsoft Edge WebView2 Runtime。\n$error';
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
    if (!_ready || _controller == null) {
      await _initialize();
      return;
    }
    await _controller!.loadUrl(widget.authorizationUri.toString());
  }

  Future<void> _openExternally() async {
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
    unawaited(_disposeController());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final width = math.min(980.0, math.max(560.0, size.width - 64));
    final height = math.min(760.0, math.max(480.0, size.height - 64));
    final colors = Theme.of(context).colorScheme;
    return Dialog(
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
                          '官方 bgm.tv 授权页面 · MuBangumi 不会读取你的密码',
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
                  if (_ready && _error == null && _controller != null)
                    Positioned.fill(child: windows.Webview(_controller!)),
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
