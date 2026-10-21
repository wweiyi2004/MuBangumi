import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../core/auth/website_navigation.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart' as mobile;
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
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

/// Gives the official widget a device-width page and room to grow.
///
/// The verification page has no viewport tag. Inside a short dialog the
/// checkbox and the follow-up image grid are clipped, so the challenge looks
/// unusable. This only adjusts the document box; it does not call Turnstile.
const turnstileLayoutScript = r'''
(function () {
  function apply() {
    try {
      var head = document.head || document.getElementsByTagName('head')[0];
      if (head && !document.querySelector('meta[name="viewport"]')) {
        var meta = document.createElement('meta');
        meta.setAttribute('name', 'viewport');
        meta.setAttribute('content', 'width=device-width, initial-scale=1');
        head.appendChild(meta);
      }
      var root = document.documentElement;
      if (root) root.style.minHeight = '100%';
      if (document.body) {
        document.body.style.margin = '0';
        document.body.style.minHeight = '100%';
        document.body.style.overflow = 'auto';
      }
      var box = document.getElementById('turnstile-container');
      if (box) {
        box.style.minHeight = '70vh';
        box.style.width = '100%';
      }
    } catch (e) {}
  }
  apply();
  document.addEventListener('DOMContentLoaded', apply);
  window.addEventListener('load', apply);
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

/// Main-frame failures of the verification document should be shown.
/// Custom-scheme handoff (`bangumi://…`) and `about:` frames are not failures:
/// Android reports them while the token is still being read.
bool isTurnstileDocumentFailure(String? url) {
  final uri = url == null || url.trim().isEmpty ? null : Uri.tryParse(url);
  if (uri == null || !uri.hasScheme) return true;
  return uri.scheme == 'http' || uri.scheme == 'https';
}

/// Opens the official challenge on its own page.
///
/// A dialog clips the widget and, on Android, puts the WebView in an overlay
/// that does not deliver taps to the checkbox. A full-screen route gives the
/// challenge a stable viewport after the transition.
Future<String?> showTurnstileDialog(BuildContext context) {
  return Navigator.of(context, rootNavigator: true).push<String>(
    MaterialPageRoute<String>(
      fullscreenDialog: true,
      builder: (context) => const _TurnstilePage(),
    ),
  );
}

class _TurnstilePage extends StatefulWidget {
  const _TurnstilePage();

  @override
  State<_TurnstilePage> createState() => _TurnstilePageState();
}

class _TurnstilePageState extends State<_TurnstilePage> {
  var _key = UniqueKey();

  void _reload() => setState(() => _key = UniqueKey());

  void _close() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('请完成人机验证'),
        leading: IconButton(
          tooltip: '取消',
          onPressed: _close,
          icon: const Icon(Icons.close),
        ),
        actions: [TextButton(onPressed: _reload, child: const Text('重试'))],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              '请勾选验证框。如果接着出现图片或其他步骤，在这个页面里滚动完成即可。通过后会自动继续发送；勾选后没有反应时点「重试」。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: TurnstileView(
              key: _key,
              onToken: (token) {
                if (!mounted) return;
                Navigator.of(context).pop(token);
              },
            ),
          ),
        ],
      ),
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
  bool _loading = true;
  bool _loadStarted = false;
  String? _error;
  Timer? _timeout;
  Timer? _poller;
  Animation<double>? _routeAnimation;
  AnimationStatusListener? _routeListener;

  static final _mobileGestures = <Factory<OneSequenceGestureRecognizer>>{
    Factory<EagerGestureRecognizer>(() => EagerGestureRecognizer()),
  };

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows) {
      unawaited(_initializeWindows());
    } else if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
      _initializeMobile();
    } else {
      _loading = false;
      _error = '当前平台暂不支持 Turnstile 验证';
    }
    _timeout = Timer(const Duration(minutes: 3), () {
      if (!mounted || _accepted) return;
      _setError('验证等待超时，请点「重试」');
    });
  }

  /// Turnstile measures its iframe at load time. Wait until the full-screen
  /// route has finished moving, or the widget is laid out against the dialog
  /// transition and the checkbox misses taps.
  void _scheduleLoad() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _loadStarted || _accepted) return;
      final animation = ModalRoute.of(context)?.animation;
      if (animation == null || animation.status == AnimationStatus.completed) {
        _beginLoad();
        return;
      }
      _routeAnimation = animation;
      _routeListener = (status) {
        if (status == AnimationStatus.completed) _beginLoad();
      };
      animation.addStatusListener(_routeListener!);
    });
  }

  void _beginLoad() {
    if (_loadStarted || !mounted || _accepted) return;
    _loadStarted = true;
    _detachRouteListener();
    unawaited(_loadPage());
  }

  void _detachRouteListener() {
    final listener = _routeListener;
    final animation = _routeAnimation;
    _routeListener = null;
    _routeAnimation = null;
    if (listener != null && animation != null) {
      animation.removeStatusListener(listener);
    }
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
        '$turnstileLayoutScript\n$turnstileBridgeScript',
      );
      _subscriptions.addAll([
        controller.url.listen(_handleWindowsUrl),
        controller.webMessage.listen(_handleWindowsMessage, onError: (_) {}),
        controller.loadingState.listen((state) {
          if (!mounted || _accepted) return;
          final loading = state != windows.LoadingState.navigationCompleted;
          if (loading == _loading) return;
          setState(() => _loading = loading);
        }),
        controller.onLoadError.listen((error) {
          if (_accepted) return;
          // Official page then navigates to bangumi://… WebView2 reports that
          // as a load error and never emits the URL. Read the token in-page.
          unawaited(_readHiddenToken());
        }),
      ]);
      // Belt-and-braces next to the injected bridge: if the page script was
      // blocked or the bridge never ran, keep asking the page for the token
      // until the challenge succeeds or the page is dismissed.
      _poller = Timer.periodic(const Duration(milliseconds: 500), (_) {
        unawaited(_readHiddenToken());
      });
      _ready = true;
      setState(() {});
      _scheduleLoad();
    } catch (error) {
      _setError('无法启动验证组件：$error');
    }
  }

  void _handleWindowsUrl(String url) {
    if (_consumeCallback(url)) {
      final controller = _windowsController;
      if (controller != null) unawaited(controller.stop());
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null || !isTurnstileNavigation(uri)) {
      final controller = _windowsController;
      if (controller != null) {
        unawaited(controller.stop().catchError((Object _) {}));
      }
      _setError('验证页面跳转到不受信任的地址，请重试');
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
      ..setBackgroundColor(Colors.white)
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
            final uri = Uri.tryParse(request.url);
            if (uri == null || !isTurnstileNavigation(uri)) {
              _setError('验证页面跳转到不受信任的地址，请重试');
              return mobile.NavigationDecision.prevent;
            }
            return mobile.NavigationDecision.navigate;
          },
          onPageStarted: (url) {
            _consumeCallback(url);
            if (mounted && isTurnstileDocumentFailure(url)) {
              setState(() => _loading = true);
            }
            unawaited(_injectMobileBridge());
          },
          onPageFinished: (url) {
            _consumeCallback(url);
            unawaited(_injectMobileBridge());
            if (!mounted || _accepted) return;
            final uri = Uri.tryParse(url);
            setState(() {
              _loading = false;
              if (uri != null && uri.host == 'next.bgm.tv') _error = null;
            });
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
            // bangumi:// handoff is how the official page returns the token.
            // Replacing the page with an error here drops a finished challenge.
            if (!isTurnstileDocumentFailure(url)) return;
            if (error.isForMainFrame != true || _accepted) return;
            _setError('验证页面加载失败：${error.description}');
          },
        ),
      );
    _mobileController = controller;
    _ready = true;
    _scheduleLoad();
  }

  Future<void> _loadPage() async {
    if (!mounted || _accepted) return;
    final uri = widget.uri ?? turnstileVerificationUri;
    final background = Theme.of(context).colorScheme.surface;
    try {
      final windowsController = _windowsController;
      if (windowsController != null) {
        await windowsController.setBackgroundColor(background);
        if (!mounted || _accepted) return;
        await windowsController.loadUrl(uri.toString());
        return;
      }
      final mobileController = _mobileController;
      if (mobileController == null) return;
      await mobileController.setBackgroundColor(background);
      await _enableAndroidThirdPartyCookies(mobileController);
      await _configureAndroidWebView(mobileController);
      if (!mounted || _accepted) return;
      await mobileController.loadRequest(uri);
    } catch (error) {
      _setError('无法打开验证页面：$error');
    }
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
      await controller.runJavaScript(turnstileLayoutScript);
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

  /// Wide viewport without a viewport tag lays the page out near 980px and
  /// shrinks the checkbox. Keep the layout at the view width and allow pinch
  /// zoom so an image challenge can be enlarged.
  Future<void> _configureAndroidWebView(
    mobile.WebViewController controller,
  ) async {
    if (!Platform.isAndroid) return;
    try {
      final platform = controller.platform;
      if (platform is! AndroidWebViewController) return;
      await platform.setUseWideViewPort(false);
      await platform.enableZoom(true);
    } catch (_) {}
  }

  void _acceptToken(String token) {
    if (!mounted || _accepted) return;
    final value = token.trim();
    if (!isPlausibleTurnstileToken(value)) {
      _setError('验证结果无效，请点「重试」');
      return;
    }
    _accepted = true;
    _timeout?.cancel();
    _poller?.cancel();
    widget.onToken(value);
  }

  void _setError(String message) {
    if (!mounted || _accepted) return;
    setState(() {
      _error = message;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _detachRouteListener();
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
    if (!_ready) {
      return Center(
        child: _error == null
            ? const CircularProgressIndicator()
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, textAlign: TextAlign.center),
              ),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: Theme.of(context).colorScheme.surface),
        if (Platform.isWindows)
          windows.Webview(_windowsController!)
        else
          _buildMobileView(),
        if (_loading)
          const Align(
            alignment: Alignment.topCenter,
            child: LinearProgressIndicator(),
          ),
        if (_error != null)
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Material(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: const BorderRadius.all(Radius.circular(8)),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Virtual-display WebViews drop taps on the checkbox. Hybrid composition
  /// is limited to this short-lived page so the challenge can be clicked.
  Widget _buildMobileView() {
    final controller = _mobileController!;
    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      return mobile.WebViewWidget.fromPlatformCreationParams(
        params: AndroidWebViewWidgetCreationParams(
          controller: platform,
          displayWithHybridComposition: true,
          gestureRecognizers: _mobileGestures,
        ),
      );
    }
    return mobile.WebViewWidget(
      controller: controller,
      gestureRecognizers: _mobileGestures,
    );
  }
}
