import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart' as mobile;
import 'package:webview_flutter_windows/webview_flutter_windows.dart'
    as windows;

Future<String?> showTurnstileDialog(BuildContext context) => showDialog<String>(
  context: context,
  barrierDismissible: false,
  builder: (context) => const _TurnstileDialog(),
);

class _TurnstileDialog extends StatefulWidget {
  const _TurnstileDialog();

  @override
  State<_TurnstileDialog> createState() => _TurnstileDialogState();
}

class _TurnstileDialogState extends State<_TurnstileDialog> {
  var _key = UniqueKey();

  void _reload() => setState(() => _key = UniqueKey());

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('请完成验证'),
    content: SizedBox(
      width: 360,
      height: Platform.isWindows ? 180 : 120,
      child: Column(
        children: [
          Expanded(
            child: TurnstileView(
              key: _key,
              onToken: (token) {
                if (!mounted) return;
                Navigator.of(context).pop(token);
              },
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '若验证框空白，请点下方重试',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: _reload, child: const Text('重试验证')),
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
    ],
  );
}

class TurnstileView extends StatefulWidget {
  const TurnstileView({super.key, required this.onToken});

  final ValueChanged<String> onToken;

  @override
  State<TurnstileView> createState() => _TurnstileViewState();
}

class _TurnstileViewState extends State<TurnstileView> {
  windows.WebviewController? _windowsController;
  mobile.WebViewController? _mobileController;
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  bool _ready = false;
  bool _injected = false;
  bool _accepted = false;
  String? _error;
  Timer? _timeout;

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows) {
      unawaited(_initializeWindows());
    } else if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
      _initializeMobile();
    } else {
      _error = '当前平台暂不支持 Turnstile 验证';
    }
    _timeout = Timer(const Duration(seconds: 45), () {
      if (!mounted || _accepted) return;
      _setError('验证加载超时，请点「重试验证」');
    });
  }

  Future<void> _initializeWindows() async {
    final controller = windows.WebviewController();
    _windowsController = controller;
    try {
      await controller.initialize();
      if (!mounted) return;
      _subscriptions.add(
        controller.webMessage.listen(
          _handleWindowsMessage,
          onError: (_) => _setError('验证结果读取失败'),
        ),
      );
      _subscriptions.add(
        controller.loadingState.listen((state) {
          if (state == windows.LoadingState.navigationCompleted) {
            unawaited(_injectWindows());
          }
        }),
      );
      _ready = true;
      setState(() {});
      await controller.loadUrl('https://next.bgm.tv/turnstile');
    } catch (error) {
      _setError('无法启动验证组件：$error');
    }
  }

  void _initializeMobile() {
    final controller = mobile.WebViewController()
      ..setJavaScriptMode(mobile.JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..addJavaScriptChannel(
        'Turnstile',
        onMessageReceived: (message) => _acceptToken(message.message),
      )
      ..setNavigationDelegate(
        mobile.NavigationDelegate(
          onPageFinished: (_) => unawaited(_injectMobile()),
          onWebResourceError: (error) {
            if (error.isForMainFrame == true) {
              _setError('验证页面加载失败：${error.description}');
            }
          },
        ),
      );
    _mobileController = controller;
    _ready = true;
    unawaited(
      controller.loadRequest(Uri.parse('https://next.bgm.tv/turnstile')),
    );
  }

  Future<void> _injectWindows() async {
    if (_injected) return;
    _injected = true;
    try {
      await _windowsController?.executeScript(_turnstileScript);
    } catch (error) {
      _injected = false;
      _setError('验证组件初始化失败：$error');
    }
  }

  Future<void> _injectMobile() async {
    if (_injected) return;
    _injected = true;
    try {
      await _mobileController?.runJavaScript(_turnstileScript);
    } catch (error) {
      _injected = false;
      _setError('验证组件初始化失败：$error');
    }
  }

  void _handleWindowsMessage(dynamic message) {
    if (message is Map) {
      final values = message.values.map((item) => item?.toString() ?? '');
      _acceptToken(
        message['token']?.toString() ??
            message['data']?.toString() ??
            values.cast<String>().firstWhere(
              (item) => item.trim().isNotEmpty,
              orElse: () => '',
            ),
      );
      return;
    }
    if (message is String) {
      final text = message.trim();
      if (text.isEmpty) return;
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map) {
          _acceptToken(decoded['token']?.toString() ?? '');
          return;
        }
        if (decoded is String) {
          _acceptToken(decoded);
          return;
        }
      } on FormatException {
        // Plain token string from WebView2.
      }
      _acceptToken(text);
      return;
    }
    _acceptToken(message?.toString() ?? '');
  }

  void _acceptToken(String token) {
    if (!mounted || _accepted) return;
    final value = token.trim();
    if (value.isEmpty || value == 'null' || value == '{}') return;
    // Strip accidental JSON wrappers.
    var resolved = value;
    if (value.startsWith('{') && value.contains('token')) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map && decoded['token'] != null) {
          resolved = decoded['token'].toString();
        }
      } on FormatException {
        // keep raw
      }
    }
    if (resolved.isEmpty) return;
    _accepted = true;
    _timeout?.cancel();
    widget.onToken(resolved);
  }

  void _setError(String message) {
    if (!mounted || _accepted) return;
    setState(() => _error = message);
  }

  @override
  void dispose() {
    _timeout?.cancel();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    final controller = _windowsController;
    if (controller != null) unawaited(controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(child: Text(_error!, textAlign: TextAlign.center));
    }
    if (!_ready) return const Center(child: CircularProgressIndicator());
    if (Platform.isWindows) {
      return windows.Webview(_windowsController!);
    }
    return mobile.WebViewWidget(controller: _mobileController!);
  }
}

const _turnstileScript = r'''
(() => {
  if (window.__mubangumiTurnstileInstalled) return;
  window.__mubangumiTurnstileInstalled = true;

  document.documentElement.style.colorScheme = 'light dark';
  document.body.innerHTML = '<div id="mubangumi-turnstile"></div>';
  document.body.style.margin = '0';
  document.body.style.padding = '8px';
  document.body.style.overflow = 'hidden';

  const deliver = (token) => {
    if (!token) return;
    try {
      if (window.chrome && window.chrome.webview) {
        // WebView2 is most reliable with string messages.
        window.chrome.webview.postMessage(String(token));
        window.chrome.webview.postMessage(JSON.stringify({token: String(token)}));
      }
    } catch (_) {}
    try {
      if (window.Turnstile && window.Turnstile.postMessage) {
        window.Turnstile.postMessage(String(token));
      }
    } catch (_) {}
  };

  const render = () => {
    try {
      window.turnstile.render('#mubangumi-turnstile', {
        sitekey: '0x4AAAAAAABkMYinukE8nzYS',
        theme: 'auto',
        callback: deliver,
        'error-callback': () => {},
        'expired-callback': () => {},
      });
    } catch (error) {
      console && console.error && console.error(error);
    }
  };

  if (window.turnstile) {
    render();
    return;
  }
  const script = document.createElement('script');
  script.src = 'https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit';
  script.async = true;
  script.defer = true;
  script.onload = render;
  script.onerror = () => {};
  document.head.appendChild(script);
})();
''';
