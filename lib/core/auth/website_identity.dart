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
  cleanupRequired,
}

class WebsiteAccessException implements Exception {
  const WebsiteAccessException(this.status, this.message);
  final WebsiteAccessStatus status;
  final String message;
  @override
  String toString() => message;
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
          headers: {'Cookie': snapshot.cookieHeader},
          responseType: ResponseType.plain,
          followRedirects: false,
          validateStatus: (status) => status != null && status < 600,
        ),
      );
      final html = response.data ?? '';
      if (isChallenge(html)) {
        throw const WebsiteAccessException(
          WebsiteAccessStatus.challenge,
          'Bangumi 需要网页验证，请在登录页面完成后继续',
        );
      }
      if (response.statusCode == 401 ||
          response.headers.value('location')?.contains('/login') == true ||
          PmHtmlParser().looksLikeLoginPage(html)) {
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
      final identifier = PmHtmlParser().parseSignedInUser(html);
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
      var id = int.tryParse(identifier);
      if (id == null &&
          identifier.toLowerCase() == expected.username.toLowerCase()) {
        id = expected.id;
      }
      if (id == null) {
        final user = await _dio.get<Map<String, dynamic>>(
          'https://api.bgm.tv/v0/users/${Uri.encodeComponent(identifier)}',
          options: Options(
            responseType: ResponseType.json,
            followRedirects: false,
          ),
        );
        id = (user.data?['id'] as num?)?.toInt();
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
