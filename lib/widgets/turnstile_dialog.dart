import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart' as mobile;
import 'package:webview_flutter_windows/webview_flutter_windows.dart'
    as windows;

const turnstileCallbackUri = 'bangumi://mubangumi/turnstile';

final turnstileVerificationUri = Uri.https('next.bgm.tv', '/p1/turnstile', {
  'theme': 'auto',
  'redirect_uri': turnstileCallbackUri,
});

String? parseTurnstileCallbackToken(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null ||
      uri.scheme != 'bangumi' ||
      uri.host != 'mubangumi' ||
      uri.path != '/turnstile') {
    return null;
  }
  final token = uri.queryParameters['token']?.trim() ?? '';
  return token.isEmpty ? null : token;
}

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
    title: const Text('请完成人机验证'),
    content: SizedBox(
      width: 400,
      height: Platform.isWindows ? 260 : 220,
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
            '验证完成后会自动继续发送；若页面空白，请重试',
            textAlign: TextAlign.center,
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
    _timeout = Timer(const Duration(seconds: 60), () {
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
      _subscriptions.addAll([
        controller.url.listen(_handleWindowsUrl),
        controller.onLoadError.listen((error) {
          if (_accepted) return;
          _setError('验证页面加载失败（$error）');
        }),
      ]);
      _ready = true;
      setState(() {});
      await controller.loadUrl(turnstileVerificationUri.toString());
    } catch (error) {
      _setError('无法启动验证组件：$error');
    }
  }

  void _handleWindowsUrl(String url) {
    final token = parseTurnstileCallbackToken(url);
    if (token == null) return;
    final controller = _windowsController;
    if (controller != null) unawaited(controller.stop());
    _acceptToken(token);
  }

  void _initializeMobile() {
    final controller = mobile.WebViewController()
      ..setJavaScriptMode(mobile.JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..setNavigationDelegate(
        mobile.NavigationDelegate(
          onNavigationRequest: (request) {
            final token = parseTurnstileCallbackToken(request.url);
            if (token == null) return mobile.NavigationDecision.navigate;
            _acceptToken(token);
            return mobile.NavigationDecision.prevent;
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame != true || _accepted) return;
            _setError('验证页面加载失败：${error.description}');
          },
        ),
      );
    _mobileController = controller;
    _ready = true;
    unawaited(controller.loadRequest(turnstileVerificationUri));
  }

  void _acceptToken(String token) {
    if (!mounted || _accepted) return;
    final value = token.trim();
    if (value.isEmpty || value.length > 2048) {
      _setError('验证结果无效，请点「重试验证」');
      return;
    }
    _accepted = true;
    _timeout?.cancel();
    widget.onToken(value);
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
