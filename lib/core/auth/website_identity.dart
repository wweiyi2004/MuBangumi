import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import '../../models/bangumi_models.dart';
import '../network/bangumi_user_agent.dart';
import '../network/pm_html_parser.dart';
import '../diagnostics/account_diagnostics.dart';
import '../network/account_diagnostics_interceptor.dart';
import 'website_session.dart';

enum WebsiteAccessStatus {
  missing,
  unverified,
  checking,
  available,
  expired,
  mismatch,
  challenge,
  unavailable,
  cleanupRequired;

  bool get requiresLogin => const {
    WebsiteAccessStatus.missing,
    WebsiteAccessStatus.expired,
    WebsiteAccessStatus.mismatch,
    WebsiteAccessStatus.challenge,
    WebsiteAccessStatus.cleanupRequired,
  }.contains(this);
}

class WebsiteAccessException implements Exception {
  const WebsiteAccessException(this.status, this.message);
  final WebsiteAccessStatus status;
  final String message;
  @override
  String toString() => message;
}

typedef WebsiteSessionFailureReporter =
    bool Function(
      WebsiteAccessStatus status,
      String requestKey, {
      Uri? recoveryUri,
    });

/// Inspect a redirect without following a credential-bearing request or POST.
bool isWebsiteLoginRedirect(int? statusCode, String? location) {
  if (statusCode == null ||
      statusCode < 300 ||
      statusCode >= 400 ||
      location == null) {
    return false;
  }
  final target = Uri.tryParse(location);
  if (target == null) return false;
  final uri = Uri.parse('https://bgm.tv/').resolveUri(target);
  return uri.scheme == 'https' &&
      uri.host == 'bgm.tv' &&
      uri.port == 443 &&
      uri.userInfo.isEmpty &&
      const ['/login', '/login/'].contains(uri.path);
}

/// Recovery carries no credentials and must stay on the classic website.
Uri? websiteRecoveryUri(Uri? uri) =>
    uri != null &&
        uri.scheme == 'https' &&
        uri.host == 'bgm.tv' &&
        uri.port == 443 &&
        uri.userInfo.isEmpty &&
        !uri.path.startsWith('/logout')
    ? uri.replace(fragment: '')
    : null;

/// Evidence read from the active app-owned WebView, tied to a stable cookie
/// capture. Only official page chrome is provided, never message/topic content.
class WebsiteBrowserIdentity {
  const WebsiteBrowserIdentity({
    required this.url,
    required this.html,
    required this.authenticationKey,
    this.userAgent,
  });
  final String url, html, authenticationKey;
  final String? userAgent;

  static const captureScript = '''
JSON.stringify({url: location.href, readyState: document.readyState, userAgent: navigator.userAgent,
  html: ['#headerNeue2', '#badgeUserPanel', '#dock'].map(function(selector) {
    var node = document.querySelector(selector);
    return node ? node.outerHTML : '';
  }).join('')})
''';

  static Future<WebsiteBrowserIdentity?> capture({
    required List<WebsiteCookie> cookies,
    required Future<Object?> Function(String) evaluate,
    required Future<List<WebsiteCookie>> Function() recapture,
    required bool Function() isCurrent,
    String? expectedUrl,
  }) async {
    try {
      Object? result = await evaluate(captureScript);
      for (var i = 0; i < 2 && result is String; i++) {
        result = jsonDecode(result);
      }
      if (!isCurrent() ||
          result is! Map ||
          !const ['interactive', 'complete'].contains(result['readyState']) ||
          (expectedUrl != null &&
              Uri.tryParse(result['url']?.toString() ?? '') !=
                  Uri.tryParse(expectedUrl))) {
        return null;
      }
      final before = WebsiteSessionSnapshot(
        cookies: cookies,
        syncedAt: DateTime.now(),
      );
      final after = WebsiteSessionSnapshot(
        cookies: await recapture(),
        syncedAt: DateTime.now(),
      );
      if (!isCurrent() || before.authenticationKey != after.authenticationKey) {
        return null;
      }
      final identity = WebsiteBrowserIdentity(
        url: result['url']?.toString() ?? '',
        html: result['html']?.toString() ?? '',
        userAgent: result['userAgent']?.toString(),
        authenticationKey: before.authenticationKey,
      );
      return identity.matches(before) ? identity : null;
    } catch (_) {
      return null;
    }
  }

  bool matches(WebsiteSessionSnapshot snapshot) {
    final uri = Uri.tryParse(url);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host == 'bgm.tv' &&
        uri.port == 443 &&
        uri.userInfo.isEmpty &&
        !uri.path.startsWith('/logout') &&
        authenticationKey.isNotEmpty &&
        authenticationKey == snapshot.authenticationKey;
  }

  String? identifierFor(WebsiteSessionSnapshot snapshot) =>
      matches(snapshot) ? PmHtmlParser().parseSignedInUser(html) : null;
}

/// A Cookie-only probe. API Authorization must never stand in for website identity.
class WebsiteIdentityProbe {
  WebsiteIdentityProbe({
    Dio? dio,
    AccountDiagnostics? diagnostics,
    Future<void> Function(Duration)? retryDelay,
  }) : _retryDelay = retryDelay ?? Future<void>.delayed,
       _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 12),
               receiveTimeout: const Duration(seconds: 15),
               headers: const {'User-Agent': muBangumiUserAgent},
             ),
           ) {
    _dio.options.headers.removeWhere(
      (key, _) => key.toLowerCase() == 'authorization',
    );
    _dio.interceptors.add(
      AccountDiagnosticsInterceptor(
        diagnostics ?? AccountDiagnostics(),
        AccountArea.website,
      ),
    );
  }
  final Dio _dio;
  final Future<void> Function(Duration) _retryDelay;
  WebsiteResponseCookieReceiver? onWebsiteResponseCookies;

  Future<WebsiteSessionSnapshot?> _absorbCookies(
    Response<String> response,
    WebsiteSessionSnapshot snapshot,
  ) async {
    final cookies = parseWebsiteResponseCookies(
      response.headers['set-cookie'],
      response.requestOptions.uri,
    );
    if (cookies.isEmpty || onWebsiteResponseCookies == null) return snapshot;
    final current = await onWebsiteResponseCookies!(
      snapshot.requestKey,
      cookies,
    );
    if (current == null) {
      throw const WebsiteAccessException(
        WebsiteAccessStatus.unavailable,
        '网站会话已更新，请重试核验',
      );
    }
    return current;
  }

  static bool isChallenge(String html, {String? cfMitigated}) {
    // Cloudflare also injects challenge-platform/scripts/jsd into ordinary,
    // successful pages. A script URL alone does not revoke a website login.
    if (cfMitigated?.trim().toLowerCase() == 'challenge') return true;
    final text = html.toLowerCase();
    if (!text.contains('cloudflare') &&
        !text.contains('cf-chl-') &&
        !text.contains('challenge-platform') &&
        !text.contains('_cf_chl_opt') &&
        !text.contains('challenge-form')) {
      return false;
    }
    if (PmHtmlParser().parseSignedInUser(html) != null) return false;
    final document = html_parser.parse(html);
    final title = document.querySelector('title')?.text.toLowerCase() ?? '';
    final challengeTitle =
        title.contains('just a moment') ||
        title.contains('checking your browser') ||
        title.contains('attention required');
    final challengeForm =
        document.querySelector(
          '#challenge-form, #cf-challenge-running, #cf-challenge-error',
        ) !=
        null;
    final scripts = document.querySelectorAll('script');
    final orchestration = scripts.any(
      (script) =>
          RegExp(r'\b(?:window\.)?_cf_chl_opt\s*=').hasMatch(script.text),
    );
    final challengeScript = scripts.any((script) {
      final src = (script.attributes['src'] ?? '').toLowerCase();
      return src.contains('/cdn-cgi/challenge-platform/') &&
          !src.contains('/scripts/jsd/');
    });
    return challengeForm ||
        (challengeTitle &&
            (orchestration || challengeScript || text.contains('cloudflare')));
  }

  Future<int> verify(
    WebsiteSessionSnapshot snapshot,
    BangumiUser expected,
  ) async {
    if (expected.id <= 0) {
      throw const WebsiteAccessException(
        WebsiteAccessStatus.missing,
        '请先验证应用账号',
      );
    }
    if (!snapshot.hasSessionCookies) {
      throw const WebsiteAccessException(
        WebsiteAccessStatus.missing,
        '请补充 Bangumi 登录验证',
      );
    }
    try {
      _dio.options.headers.removeWhere(
        (key, _) => key.toLowerCase() == 'authorization',
      );
      var response = await _dio.get<String>(
        'https://bgm.tv/',
        options: Options(
          headers: snapshot.requestHeaders,
          responseType: ResponseType.plain,
          followRedirects: false,
          validateStatus: (status) => status != null && status < 600,
        ),
      );
      var current = await _absorbCookies(response, snapshot) ?? snapshot;
      if (isChallenge(
        response.data ?? '',
        cfMitigated: response.headers.value('cf-mitigated'),
      )) {
        await _retryDelay(const Duration(seconds: 2));
        response = await _dio.get<String>(
          'https://bgm.tv/',
          options: Options(
            headers: current.requestHeaders,
            responseType: ResponseType.plain,
            followRedirects: false,
            validateStatus: (status) => status != null && status < 600,
          ),
        );
        current = await _absorbCookies(response, current) ?? current;
      }
      final html = response.data ?? '';
      if (isChallenge(
        html,
        cfMitigated: response.headers.value('cf-mitigated'),
      )) {
        throw const WebsiteAccessException(
          WebsiteAccessStatus.challenge,
          'Bangumi 需要网页验证，请在登录页面完成后继续',
        );
      }
      if ((response.statusCode ?? 0) >= 500 || response.statusCode == 429) {
        throw const WebsiteAccessException(
          WebsiteAccessStatus.unavailable,
          '网站暂时无法响应，已保留登录，请稍后重试',
        );
      }
      final identifier = PmHtmlParser().parseSignedInUser(html);
      if (response.statusCode == 401 ||
          isWebsiteLoginRedirect(
            response.statusCode,
            response.headers.value('location'),
          ) ||
          (identifier == null && PmHtmlParser().looksLikeLoginPage(html))) {
        throw const WebsiteAccessException(
          WebsiteAccessStatus.expired,
          '网页登录已过期，请补充验证',
        );
      }
      if (response.statusCode != 200) {
        throw const WebsiteAccessException(
          WebsiteAccessStatus.unavailable,
          '暂时无法核验网站登录，已保留应用登录',
        );
      }
      if (identifier == null) {
        if (RegExp(r'''class=["']guest(?:\s|["'])''').hasMatch(html)) {
          throw const WebsiteAccessException(
            WebsiteAccessStatus.expired,
            '网页登录已过期，请补充验证',
          );
        }
        throw const WebsiteAccessException(
          WebsiteAccessStatus.unavailable,
          '暂时无法识别网站账号，请稍后重试核验',
        );
      }
      return await verifyIdentifier(identifier, expected);
    } on WebsiteAccessException {
      rethrow;
    } on DioException {
      throw const WebsiteAccessException(
        WebsiteAccessStatus.unavailable,
        '暂时无法连接 Bangumi，已保留应用登录，请稍后重试核验',
      );
    }
  }

  Future<int> verifyIdentifier(String identifier, BangumiUser expected) async {
    if (expected.id <= 0 || identifier.isEmpty) {
      throw const WebsiteAccessException(
        WebsiteAccessStatus.unavailable,
        '暂时无法识别网站账号',
      );
    }
    // A username may be numeric. Compare the known canonical username before
    // interpreting a numeric profile link as a different user's ID.
    if (identifier.toLowerCase() == expected.username.toLowerCase() ||
        identifier == '${expected.id}') {
      return expected.id;
    }
    try {
      var id = int.tryParse(identifier);
      if (id == null) {
        final user = await _dio.get<Map<String, dynamic>>(
          'https://api.bgm.tv/v0/users/${Uri.encodeComponent(identifier)}',
          options: Options(
            responseType: ResponseType.json,
            followRedirects: false,
            headers: {'Cookie': null, 'Authorization': null},
          ),
        );
        id = (user.data?['id'] as num?)?.toInt();
      }
      if (id == null || id <= 0) {
        throw const WebsiteAccessException(
          WebsiteAccessStatus.unavailable,
          '暂时无法识别网站账号，请稍后重试核验',
        );
      }
      if (id != expected.id) {
        throw const WebsiteAccessException(
          WebsiteAccessStatus.mismatch,
          '网页账号与当前账号不一致，请登录同一个 Bangumi 账号',
        );
      }
      return expected.id;
    } on WebsiteAccessException {
      rethrow;
    } on DioException {
      throw const WebsiteAccessException(
        WebsiteAccessStatus.unavailable,
        '暂时无法连接 Bangumi，已保留应用登录，请稍后重试核验',
      );
    }
  }
}
