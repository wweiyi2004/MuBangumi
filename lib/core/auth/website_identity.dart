import 'package:dio/dio.dart';
import '../../models/bangumi_models.dart';
import '../network/bangumi_user_agent.dart';
import '../network/pm_html_parser.dart';
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
  WebsiteIdentityProbe({Dio? dio})
    : _dio =
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
  }
  final Dio _dio;

  static bool isChallenge(String html) {
    final text = html.toLowerCase();
    return text.contains('cf-chl-') ||
        text.contains('/cdn-cgi/challenge-platform/') ||
        (text.contains('just a moment') && text.contains('cloudflare'));
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
      final response = await _dio.get<String>(
        'https://bgm.tv/',
        options: Options(
          headers: snapshot.requestHeaders,
          responseType: ResponseType.plain,
          followRedirects: false,
          validateStatus: (status) => status != null && status < 600,
        ),
      );
      final html = response.data ?? '';
      if ((response.statusCode ?? 0) >= 500 || response.statusCode == 429) {
        throw const WebsiteAccessException(
          WebsiteAccessStatus.unavailable,
          '网站暂时无法响应，已保留登录，请稍后重试',
        );
      }
      final identifier = PmHtmlParser().parseSignedInUser(html);
      if (isChallenge(html)) {
        throw const WebsiteAccessException(
          WebsiteAccessStatus.challenge,
          'Bangumi 需要网页验证，请在登录页面完成后继续',
        );
      }
      if (response.statusCode == 401 ||
          (response.statusCode != null &&
              response.statusCode! >= 300 &&
              response.statusCode! < 400 &&
              Uri.tryParse(response.headers.value('location') ?? '')?.path ==
                  '/login') ||
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
