import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:url_launcher/url_launcher.dart';

import '../network/bangumi_user_agent.dart';

typedef OAuthAuthorizationLauncher =
    Future<bool> Function(Uri authorizationUri, Future<Uri> callback);

const oauthAppReturnUri = 'mubangumi://oauth/complete';

class OAuthConfig {
  const OAuthConfig({required this.clientId, required this.clientSecret});

  static const redirectUri = 'http://127.0.0.1:43927/oauth/callback';

  final String clientId;
  final String clientSecret;

  bool get isValid =>
      clientId.trim().isNotEmpty && clientSecret.trim().isNotEmpty;
}

class OAuthTokenBundle {
  const OAuthTokenBundle({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
}

class BangumiOAuthException implements Exception {
  const BangumiOAuthException(
    this.message, {
    this.invalidatesSession = false,
    this.isCancelled = false,
  });

  final String message;
  final bool invalidatesSession;
  final bool isCancelled;

  @override
  String toString() => message;
}

class BangumiOAuth {
  BangumiOAuth({
    Dio? dio,
    Future<void> Function()? closeInAppBrowser,
    bool? closeInAppBrowserOnCallback,
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               baseUrl: 'https://bgm.tv',
               connectTimeout: const Duration(seconds: 15),
               receiveTimeout: const Duration(seconds: 20),
               headers: const {
                 'Accept': 'application/json',
                 'User-Agent': muBangumiUserAgent,
               },
             ),
           ),
       _closeInAppBrowser = closeInAppBrowser ?? closeInAppWebView,
       _closeInAppBrowserOnCallback =
           closeInAppBrowserOnCallback ??
           (Platform.isAndroid || Platform.isIOS);

  final Dio _dio;
  final Future<void> Function() _closeInAppBrowser;
  final bool _closeInAppBrowserOnCallback;
  Completer<Uri>? _authorizationCancel;
  HttpServer? _activeAuthServer;
  Future<HttpServer>? _openingAuthServer;
  CancelToken? _authorizationRequest;
  int _cancelGeneration = 0;

  /// Abort an in-flight [authorize] wait (e.g. user closed the browser tab).
  Future<void> cancelAuthorization() async {
    _cancelGeneration++;
    _authorizationRequest?.cancel('authorization cancelled');
    final cancel = _authorizationCancel;
    if (cancel != null && !cancel.isCompleted) {
      cancel.completeError(
        const BangumiOAuthException('已取消 Bangumi 授权', isCancelled: true),
      );
    }
    final opening = _openingAuthServer;
    HttpServer? server = _activeAuthServer;
    if (server == null && opening != null) {
      try {
        server = await opening;
      } catch (_) {}
    }
    if (server != null) {
      await server.close(force: true);
      if (identical(_activeAuthServer, server)) _activeAuthServer = null;
    }
  }

  Future<OAuthTokenBundle> authorize(
    OAuthConfig config, {
    OAuthAuthorizationLauncher? launchAuthorization,
  }) async {
    if (!config.isValid) throw const BangumiOAuthException('OAuth 配置不完整');
    if (_openingAuthServer != null || _activeAuthServer != null) {
      throw const BangumiOAuthException('已有授权正在进行，请先取消再重试');
    }
    final generation = _cancelGeneration;

    HttpServer server;
    final opening = HttpServer.bind(InternetAddress.loopbackIPv4, 43927);
    _openingAuthServer = opening;
    try {
      server = await opening;
    } on SocketException {
      throw const BangumiOAuthException('无法启动本地授权回调，请关闭占用 43927 端口的程序后重试');
    } finally {
      if (identical(_openingAuthServer, opening)) _openingAuthServer = null;
    }
    if (generation != _cancelGeneration) {
      await server.close(force: true);
      throw const BangumiOAuthException('已取消 Bangumi 授权', isCancelled: true);
    }

    final state = _createState();
    final authorizeUri = Uri.https('bgm.tv', '/oauth/authorize', {
      'client_id': config.clientId.trim(),
      'response_type': 'code',
      'redirect_uri': OAuthConfig.redirectUri,
      'state': state,
    });

    final cancel = Completer<Uri>();
    _authorizationCancel = cancel;
    _activeAuthServer = server;
    final requestCancel = CancelToken();
    _authorizationRequest = requestCancel;
    try {
      final callback = Future.any([_waitForCallback(server), cancel.future])
          .timeout(
            const Duration(minutes: 3),
            onTimeout: () => throw const BangumiOAuthException('授权等待超时，请重新登录'),
          );
      // The launcher may wait for user interaction. Attach an error handler
      // immediately so cancellation/timeouts never escape as unhandled errors.
      unawaited(
        callback.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      );
      final opened = launchAuthorization == null
          ? await launchUrl(
              authorizeUri,
              mode: LaunchMode.inAppBrowserView,
              browserConfiguration: const BrowserConfiguration(showTitle: true),
            )
          : await launchAuthorization(authorizeUri, callback);
      if (!opened) {
        // Prefer a completed success callback over cancel if the race lands
        // after the provider already redirected with a code.
        final raced = await _takeCompletedCallback(callback);
        if (raced != null) {
          final code = parseOAuthAuthorizationCallback(
            raced,
            expectedState: state,
          );
          return await _exchangeCode(config, code, state, requestCancel);
        }
        unawaited(
          callback.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
        );
        throw const BangumiOAuthException('已取消 Bangumi 授权', isCancelled: true);
      }

      final code = parseOAuthAuthorizationCallback(
        await callback,
        expectedState: state,
      );
      return await _exchangeCode(config, code, state, requestCancel);
    } finally {
      if (identical(_authorizationRequest, requestCancel)) {
        _authorizationRequest = null;
      }
      if (identical(_authorizationCancel, cancel)) {
        _authorizationCancel = null;
      }
      if (identical(_activeAuthServer, server)) {
        _activeAuthServer = null;
      }
      await server.close(force: true);
    }
  }

  /// If [callback] already completed successfully, return its value; else null.
  Future<Uri?> _takeCompletedCallback(Future<Uri> callback) async {
    Uri? value;
    Object? error;
    var settled = false;
    // ignore: unawaited_futures
    callback.then<void>(
      (uri) {
        value = uri;
        settled = true;
      },
      onError: (Object err, StackTrace _) {
        error = err;
        settled = true;
      },
    );
    // Yield once so already-completed futures attach their handlers.
    await Future<void>.delayed(Duration.zero);
    if (!settled || error != null) return null;
    return value;
  }

  Future<OAuthTokenBundle> refresh(
    OAuthConfig config,
    String refreshToken,
  ) async {
    final tokens = await _requestToken({
      'grant_type': 'refresh_token',
      'client_id': config.clientId.trim(),
      'client_secret': config.clientSecret.trim(),
      'refresh_token': refreshToken,
      'redirect_uri': OAuthConfig.redirectUri,
    });
    // Some refresh responses omit refresh_token; keep the previous one.
    if (tokens.refreshToken.isNotEmpty) return tokens;
    return OAuthTokenBundle(
      accessToken: tokens.accessToken,
      refreshToken: refreshToken,
      expiresAt: tokens.expiresAt,
    );
  }

  Future<OAuthTokenBundle> _exchangeCode(
    OAuthConfig config,
    String code,
    String state,
    CancelToken cancelToken,
  ) => _requestToken({
    'grant_type': 'authorization_code',
    'client_id': config.clientId.trim(),
    'client_secret': config.clientSecret.trim(),
    'code': code,
    'redirect_uri': OAuthConfig.redirectUri,
    'state': state,
  }, cancelToken: cancelToken);

  Future<OAuthTokenBundle> _requestToken(
    Map<String, dynamic> data, {
    CancelToken? cancelToken,
  }) async {
    DioException? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final response = await _dio.post<Map<String, dynamic>>(
          '/oauth/access_token',
          data: data,
          options: Options(contentType: Headers.formUrlEncodedContentType),
          cancelToken: cancelToken,
        );
        final json = response.data ?? const <String, dynamic>{};
        final accessToken = json['access_token']?.toString() ?? '';
        if (accessToken.isEmpty) {
          throw const BangumiOAuthException('Bangumi 没有返回 Access Token');
        }
        final seconds = (json['expires_in'] as num?)?.toInt() ?? 604800;
        return OAuthTokenBundle(
          accessToken: accessToken,
          refreshToken: json['refresh_token']?.toString() ?? '',
          expiresAt: DateTime.now().add(Duration(seconds: seconds)),
        );
      } on DioException catch (error) {
        if (CancelToken.isCancel(error)) {
          throw const BangumiOAuthException(
            '已取消 Bangumi 授权',
            isCancelled: true,
          );
        }
        lastError = error;
        if ((error.response?.statusCode ?? 0) < 500 || attempt == 1) break;
        await Future<void>.delayed(const Duration(milliseconds: 450));
      }
    }
    final errorData = lastError?.response?.data;
    if (errorData is Map) {
      final errorCode = errorData['error']?.toString() ?? '';
      throw BangumiOAuthException(
        (errorData['error_description'] ?? errorData['error'] ?? 'Bangumi 授权失败')
            .toString(),
        invalidatesSession: const {
          'invalid_grant',
          'invalid_client',
          'unauthorized_client',
        }.contains(errorCode),
      );
    }
    throw const BangumiOAuthException('连接 Bangumi 授权服务器失败');
  }

  Future<Uri> _waitForCallback(HttpServer server) async {
    await for (final request in server) {
      if (request.uri.path != '/oauth/callback') {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        continue;
      }
      final hasCode = request.uri.queryParameters['code']?.isNotEmpty == true;
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.html
        ..write(
          hasCode
              ? (Platform.isAndroid ? _androidSuccessHtml : _successHtml)
              : (Platform.isAndroid ? _androidFailureHtml : _failureHtml),
        );
      await request.response.close();
      await _dismissMobileBrowser();
      return request.uri;
    }
    throw const BangumiOAuthException('本地授权回调已关闭');
  }

  Future<void> _dismissMobileBrowser() async {
    if (!_closeInAppBrowserOnCallback) return;
    try {
      await _closeInAppBrowser();
    } catch (_) {
      // Closing Custom Tabs is best-effort; token exchange can still continue.
    }
  }

  String _createState() {
    final random = Random.secure();
    final bytes = List<int>.generate(24, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  static const _successHtml = '''
<!DOCTYPE html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>MuBangumi 授权完成</title><style>body{margin:0;font-family:system-ui;background:#f7f7fa;color:#1d2433;display:grid;place-items:center;min-height:100vh}.card{background:white;padding:48px;border-radius:24px;text-align:center;box-shadow:0 12px 40px #1d243312}.mark{width:64px;height:64px;border-radius:20px;background:#e95383;color:white;display:grid;place-items:center;font-size:36px;margin:auto}h1{margin:24px 0 8px;font-size:24px}p{color:#6d707f;margin:0}</style></head><body><div class="card"><div class="mark">✓</div><h1>授权成功</h1><p>可以关闭浏览器，回到 MuBangumi 了。</p></div></body></html>
''';
  static const _androidSuccessHtml =
      '''
<!DOCTYPE html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width"><meta http-equiv="refresh" content="0;url=$oauthAppReturnUri"><title>MuBangumi 授权完成</title><style>body{margin:0;font-family:system-ui;background:#f7f7fa;color:#1d2433;display:grid;place-items:center;min-height:100vh}.card{background:white;padding:48px;border-radius:24px;text-align:center;box-shadow:0 12px 40px #1d243312}.mark{width:64px;height:64px;border-radius:20px;background:#e95383;color:white;display:grid;place-items:center;font-size:36px;margin:auto}h1{margin:24px 0 8px;font-size:24px}p{color:#6d707f;margin:0 0 22px}a{display:inline-block;padding:12px 20px;border-radius:999px;background:#e95383;color:white;text-decoration:none;font-weight:600}</style></head><body><div class="card"><div class="mark">✓</div><h1>授权成功</h1><p>正在返回 MuBangumi…</p><a href="$oauthAppReturnUri">返回 MuBangumi</a></div><script>setTimeout(function(){location.replace('$oauthAppReturnUri')},120)</script></body></html>
''';
  static const _failureHtml = '''
<!DOCTYPE html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>MuBangumi 授权失败</title></head><body style="font-family:system-ui;text-align:center;padding:60px"><h1>授权未完成</h1><p>请返回 MuBangumi 再试一次。</p></body></html>
''';
  static const _androidFailureHtml =
      '''
<!DOCTYPE html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width"><meta http-equiv="refresh" content="0;url=$oauthAppReturnUri"><title>MuBangumi 授权失败</title><style>body{margin:0;font-family:system-ui;background:#f7f7fa;color:#1d2433;display:grid;place-items:center;min-height:100vh}.card{background:white;padding:48px;border-radius:24px;text-align:center;box-shadow:0 12px 40px #1d243312}.mark{width:64px;height:64px;border-radius:20px;background:#8a93a8;color:white;display:grid;place-items:center;font-size:36px;margin:auto}h1{margin:24px 0 8px;font-size:24px}p{color:#6d707f;margin:0 0 22px}a{display:inline-block;padding:12px 20px;border-radius:999px;background:#e95383;color:white;text-decoration:none;font-weight:600}</style></head><body><div class="card"><div class="mark">!</div><h1>授权未完成</h1><p>正在返回 MuBangumi…</p><a href="$oauthAppReturnUri">返回 MuBangumi</a></div><script>setTimeout(function(){location.replace('$oauthAppReturnUri')},120)</script></body></html>
''';
}

String parseOAuthAuthorizationCallback(
  Uri callback, {
  required String expectedState,
}) {
  final returnedState = callback.queryParameters['state'];
  if (returnedState != expectedState) {
    throw const BangumiOAuthException('授权状态校验失败，请重新登录');
  }
  final error = callback.queryParameters['error'];
  if (error != null) {
    throw BangumiOAuthException(
      callback.queryParameters['error_description'] ?? 'Bangumi 拒绝了授权请求',
      isCancelled: error == 'access_denied',
    );
  }
  final code = callback.queryParameters['code'];
  if (code == null || code.isEmpty) {
    throw const BangumiOAuthException('授权回调中没有 code');
  }
  return code;
}
