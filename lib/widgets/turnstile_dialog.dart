import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart' as mobile;
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
import '../core/theme/app_tokens.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart'
    as windows;

/// Official `/p1/turnstile` only accepts prefix-whitelisted redirect URIs.
/// `bangumi://` is the generic prefix already on that list; a custom HTTPS
/// landing is rejected with 400 before the widget even renders.
const turnstileCallbackUri = 'bangumi://mubangumi/turnstile';

final turnstileVerificationUri = Uri.https('next.bgm.tv', '/p1/turnstile', {
  'theme': 'auto',
  'redirect_uri': turnstileCallbackUri,
});

/// The official page renders explicitly without a <form>, so Cloudflare
/// usually creates no hidden input; `turnstile.getResponse()` is the
/// dependable source. Kept as the Dart-driven fallback for when the injected
/// bridge itself failed to run.
// Only the official application widget can issue a posting token. An upstream
// Cloudflare clearance page may also contain cf-turnstile-response; its token
// belongs to a different site key and must never be submitted to the P1 API.
const turnstileReadTokenScript = r'''
(function () {
  if (window.top !== window || location.origin !== 'https://next.bgm.tv' ||
      location.pathname !== '/p1/turnstile' ||
      !document.getElementById('turnstile-container') ||
      typeof window.turnstileCallback !== 'function') return '';
  try {
    return window.turnstile && window.turnstile.getResponse
      ? window.turnstile.getResponse() || '' : '';
  } catch (e) { return ''; }
})();
''';

// Wrap only the page's own completion callback. Leave Turnstile and browser
// navigation APIs intact, including those used by Cloudflare clearance pages.
const turnstileBridgeScript = r'''
(function () {
  if (window.top !== window || location.origin !== 'https://next.bgm.tv' ||
      location.pathname !== '/p1/turnstile' || window.__muPostingBridge) return;
  window.__muPostingBridge = true;
  var delivered = false;
  function post(token) {
    if (delivered || !token) return;
    delivered = true;
    var raw = JSON.stringify({token: String(token)});
    if (window.chrome && window.chrome.webview) window.chrome.webview.postMessage(raw);
    if (window.MuBangumiTurnstile) window.MuBangumiTurnstile.postMessage(raw);
  }
  function connectCallback() {
    if (!document.getElementById('turnstile-container') ||
        typeof window.turnstileCallback !== 'function') return false;
    if (!window.turnstileCallback.__muWrapped) {
      var original = window.turnstileCallback;
      var callback = function (token) { post(token); return original.apply(this, arguments); };
      callback.__muWrapped = true;
      window.turnstileCallback = callback;
    }
    return true;
  }
  // The page passes a function reference to render() during window.onload.
  // Connect in the earlier capture listener before that reference is retained.
  window.addEventListener('load', connectCallback, true);
  connectCallback();
  var timer = setInterval(function () {
    if (delivered) { clearInterval(timer); return; }
    if (!connectCallback()) return;
    try {
      if (window.turnstile && window.turnstile.getResponse) post(window.turnstile.getResponse());
    } catch (e) {}
  }, 250);
})();
''';

String? parseTurnstileCallbackToken(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return null;
  final fromJson = _tokenFromBridgeJson(value);
  if (fromJson != null) return fromJson;
  return _tokenFromUri(value);
}

String? _tokenFromBridgeJson(String raw) {
  if (!raw.startsWith('{')) return null;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    final url = decoded['url']?.toString();
    if (url != null && url.trim().isNotEmpty) {
      return _tokenFromUri(url);
    }
    final token = decoded['token']?.toString().trim() ?? '';
    return token.isEmpty ? null : token;
  } catch (_) {
    return null;
  }
}

String? _tokenFromUri(String raw) {
  final uri = Uri.tryParse(raw);
  if (uri == null || !_isTurnstileCallback(uri)) return null;
  final token = uri.queryParameters['token']?.trim() ?? '';
  if (token.isNotEmpty) return token;
  if (uri.fragment.isEmpty) return null;
  final fragmentToken =
      Uri.splitQueryString(uri.fragment)['token']?.trim() ?? '';
  return fragmentToken.isEmpty ? null : fragmentToken;
}

bool _isTurnstileCallback(Uri uri) {
  if (uri.scheme != 'bangumi' || uri.host != 'mubangumi') return false;
  return uri.path == '/turnstile' || uri.path.isEmpty;
}

/// Cloudflare tokens are long; reject the placeholders a WebView can emit
/// before the challenge actually finishes.
bool isPlausibleTurnstileToken(String token) {
  final value = token.trim();
  if (value.length < 32 || value.length > 2048) return false;
  final lower = value.toLowerCase();
  return lower != 'null' && lower != 'undefined' && lower != 'true';
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
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return AlertDialog(
      title: const Text('请完成人机验证'),
      content: SizedBox(
        width: size.width < 520 ? size.width - 48 : 480,
        height: (size.height * 0.62).clamp(360.0, 560.0),
        child: Column(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: AppRadius.small,
                child: TurnstileView(
                  key: _key,
                  onToken: (token) {
                    if (!mounted) return;
                    Navigator.of(context).pop(token);
                  },
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '验证成功后会自动继续发送。若勾选后没有跳转，请点「重试验证」。',
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
}

class TurnstileView extends StatefulWidget {
  const TurnstileView({super.key, required this.onToken, this.uri});

  final ValueChanged<String> onToken;

  /// Overrides the verification page; defaults to the official
  /// [turnstileVerificationUri]. Only used by diagnostics tooling.
  final Uri? uri;

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
  Timer? _poller;

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
    _timeout = Timer(const Duration(minutes: 3), () {
      if (!mounted || _accepted) return;
      _setError('验证等待超时，请点「重试验证」');
    });
  }

  bool _consumeCallback(String raw) {
    final token = parseTurnstileCallbackToken(raw);
    if (token == null || !isPlausibleTurnstileToken(token)) return false;
    _acceptToken(token);
    return true;
  }

  Future<void> _initializeWindows() async {
    final controller = windows.WebviewController();
    _windowsController = controller;
    try {
      await controller.initialize();
      if (!mounted) return;
      await controller.addScriptToExecuteOnDocumentCreated(
        turnstileBridgeScript,
      );
      _subscriptions.addAll([
        controller.url.listen(_handleWindowsUrl),
        controller.webMessage.listen(_handleWindowsMessage, onError: (_) {}),
        controller.onLoadError.listen((error) {
          if (_accepted) return;
          // Official page then navigates to bangumi://… WebView2 reports that
          // as a load error and never emits the URL. Read the token in-page.
          unawaited(_readHiddenToken());
        }),
      ]);
      // Belt-and-braces next to the injected bridge: if the page script was
      // blocked or the bridge never ran, keep asking the page for the token
      // until the challenge succeeds or the dialog is dismissed.
      _poller = Timer.periodic(const Duration(milliseconds: 500), (_) {
        unawaited(_readHiddenToken());
      });
      _ready = true;
      setState(() {});
      await controller.loadUrl(
        (widget.uri ?? turnstileVerificationUri).toString(),
      );
    } catch (error) {
      _setError('无法启动验证组件：$error');
    }
  }

  void _handleWindowsUrl(String url) {
    if (_consumeCallback(url)) {
      final controller = _windowsController;
      if (controller != null) unawaited(controller.stop());
    }
  }

  void _handleWindowsMessage(dynamic message) {
    if (message is String) {
      _consumeCallback(message);
      return;
    }
    if (message is Map) {
      _consumeCallback(jsonEncode(message));
    }
  }

  void _initializeMobile() {
    final controller = mobile.WebViewController()
      ..setJavaScriptMode(mobile.JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..addJavaScriptChannel(
        'MuBangumiTurnstile',
        onMessageReceived: (message) => _consumeCallback(message.message),
      )
      ..setNavigationDelegate(
        mobile.NavigationDelegate(
          onNavigationRequest: (request) {
            if (_consumeCallback(request.url)) {
              return mobile.NavigationDecision.prevent;
            }
            return mobile.NavigationDecision.navigate;
          },
          onPageStarted: (url) {
            _consumeCallback(url);
            unawaited(_injectMobileBridge());
          },
          onPageFinished: (url) {
            _consumeCallback(url);
            unawaited(_injectMobileBridge());
          },
          onUrlChange: (change) {
            final url = change.url;
            if (url != null) _consumeCallback(url);
          },
          onWebResourceError: (error) {
            final url = error.url;
            if (url != null && _consumeCallback(url)) return;
            unawaited(_readHiddenToken());
            if (error.errorType ==
                mobile.WebResourceErrorType.unsupportedScheme) {
              return;
            }
            if (error.isForMainFrame != true || _accepted) return;
            _setError('验证页面加载失败：${error.description}');
          },
        ),
      );
    _mobileController = controller;
    _ready = true;
    unawaited(_prepareMobile(controller));
  }

  Future<void> _prepareMobile(mobile.WebViewController controller) async {
    await _enableAndroidThirdPartyCookies(controller);
    if (!mounted || _accepted) return;
    await controller.loadRequest(widget.uri ?? turnstileVerificationUri);
  }

  Future<void> _readHiddenToken() async {
    if (!mounted || _accepted) return;
    try {
      final windowsController = _windowsController;
      if (windowsController != null) {
        final result = await windowsController.executeScript(
          turnstileReadTokenScript,
        );
        _acceptHiddenToken(result);
        return;
      }
      final mobileController = _mobileController;
      if (mobileController == null) return;
      final result = await mobileController.runJavaScriptReturningResult(
        turnstileReadTokenScript,
      );
      _acceptHiddenToken(result);
    } catch (_) {}
  }

  void _acceptHiddenToken(Object? result) {
    if (result == null) return;
    final raw = result.toString().trim();
    if (raw.isEmpty || raw == 'null' || raw == '""') return;
    final decoded = raw.startsWith('"') ? jsonDecode(raw) : raw;
    if (decoded is! String) return;
    final token = decoded;
    if (token.isEmpty) return;
    _consumeCallback(jsonEncode({'token': token}));
  }

  Future<void> _injectMobileBridge() async {
    final controller = _mobileController;
    if (controller == null || _accepted) return;
    try {
      await controller.runJavaScript(turnstileBridgeScript);
    } catch (_) {}
  }

  Future<void> _enableAndroidThirdPartyCookies(
    mobile.WebViewController controller,
  ) async {
    if (!Platform.isAndroid) return;
    try {
      final platform = controller.platform;
      if (platform is! AndroidWebViewController) return;
      await AndroidWebViewCookieManager(
        AndroidWebViewCookieManagerCreationParams.fromPlatformWebViewCookieManagerCreationParams(
          const PlatformWebViewCookieManagerCreationParams(),
        ),
      ).setAcceptThirdPartyCookies(platform, true);
    } catch (_) {}
  }

  void _acceptToken(String token) {
    if (!mounted || _accepted) return;
    final value = token.trim();
    if (!isPlausibleTurnstileToken(value)) {
      _setError('验证结果无效，请点「重试验证」');
      return;
    }
    _accepted = true;
    _timeout?.cancel();
    _poller?.cancel();
    widget.onToken(value);
  }

  void _setError(String message) {
    if (!mounted || _accepted) return;
    setState(() => _error = message);
  }

  @override
  void dispose() {
    _timeout?.cancel();
    _poller?.cancel();
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
