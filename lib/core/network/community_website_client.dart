import 'dart:convert';
import 'package:dio/dio.dart';
import '../../models/community_topic_submission.dart';
import '../auth/website_session.dart';
import '../auth/website_identity.dart';
import 'community_html_parser.dart';
import 'pm_html_parser.dart';

/// Classic-site transport for private group reads and form submissions.
/// Session ownership stays with CommunityService; callbacks are read at request
/// time so replacing a login or failure reporter cannot leave stale bindings.
class CommunityWebsiteClient {
  CommunityWebsiteClient({
    required Dio dio,
    required this.readIdentity,
    required this.requireSession,
    required this.readFailureReporter,
  }) : _htmlDio = dio;

  final Dio _htmlDio;
  final int Function() readIdentity;
  final Future<WebsiteSessionSnapshot> Function() requireSession;
  final WebsiteSessionFailureReporter? Function() readFailureReporter;
  final _htmlParser = CommunityHtmlParser();

  void _websiteFailed(
    WebsiteAccessStatus status,
    WebsiteSessionSnapshot session, {
    Uri? recoveryUri,
  }) {
    if (readFailureReporter()?.call(
          status,
          session.requestKey,
          recoveryUri: recoveryUri,
        ) ==
        false) {
      throw const FormatException('网页登录已更新，请刷新页面并确认提交结果后重试');
    }
  }

  /// Creates a group topic through the classic website form
  /// (`/group/{slug}/new_topic`) using the stored website session.
  Future<int> createGroupTopic({
    required String slug,
    required String title,
    required String content,
  }) async {
    final identity = readIdentity();
    final session = await requireSession();
    final path = '/group/${Uri.encodeComponent(slug)}/new_topic';
    final formhash = await _loadWebsiteFormhash(path, session);
    await _verifyWebsiteWriteContext(identity, session.authenticationKey);
    final Response<String> response;
    try {
      response = await _htmlDio.post<String>(
        path,
        data: {
          'formhash': formhash,
          'title': title,
          'subject': title,
          'content': content,
          'submit': 'submit',
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          followRedirects: false,
          headers: {
            ...session.requestHeaders,
            'Referer': 'https://bgm.tv$path',
            'Origin': 'https://bgm.tv',
          },
          validateStatus: (status) => status != null && status < 600,
        ),
      );
    } on DioException {
      throw const CommunitySubmissionUncertain();
    }
    await _verifyWebsiteWriteContext(
      identity,
      session.authenticationKey,
      submitted: true,
    );
    final status = response.statusCode ?? 0;
    final location = response.headers.value('location') ?? '';
    final redirect = Uri.parse('https://bgm.tv$path').resolve(location);
    final topicPath = RegExp(
      r'^/group/topic/([1-9][0-9]*)/?$',
    ).firstMatch(redirect.path);
    if (const [302, 303].contains(status) &&
        redirect.scheme == 'https' &&
        redirect.userInfo.isEmpty &&
        redirect.port == 443 &&
        const ['bgm.tv', 'bangumi.tv', 'chii.in'].contains(redirect.host) &&
        topicPath != null) {
      return int.parse(topicPath.group(1)!);
    }
    final body = response.data ?? '';
    _throwIfWebsiteChallenge(
      body,
      session,
      cfMitigated: response.headers.value('cf-mitigated'),
      recoveryUri: Uri.parse('https://bgm.tv$path'),
    );
    if (status >= 500 || status == 429) {
      throw const CommunitySubmissionUncertain();
    }
    checkLoginPage(body, session);
    if (status == 401 || isWebsiteLoginRedirect(status, location)) {
      _websiteFailed(WebsiteAccessStatus.expired, session);
      throw const WebsiteAccessException(
        WebsiteAccessStatus.expired,
        '网页版登录已过期，请重新登录网页版后再发帖',
      );
    }
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      decoded = null;
    }
    if (decoded is Map) {
      final id =
          parseCreatedCommunityTopicId(decoded) ??
          parseCreatedCommunityTopicId(decoded['topic']);
      if (id != null && status >= 200 && status < 300) return id;
      final detail = decoded['error'] ?? decoded['message'];
      if (detail != null && detail.toString().trim().isNotEmpty) {
        throw CommunitySubmissionRejected('发帖失败：${detail.toString().trim()}');
      }
    }
    final notice = PmHtmlParser().parseSubmissionError(body);
    if (notice != null) throw CommunitySubmissionRejected('发帖失败：$notice');
    if (status >= 400) {
      throw CommunitySubmissionRejected('发帖失败（HTTP $status）');
    }
    throw const CommunitySubmissionUncertain();
  }

  /// Posts a group topic reply through the classic website form
  /// (`/group/topic/{id}/new_reply`) using the stored website session.
  Future<void> replyToGroupTopic({
    required int topicId,
    required String content,
    int? replyTo,
  }) async {
    final identity = readIdentity();
    final session = await requireSession();
    final topicPath = '/group/topic/$topicId';
    // The topic page carries the session-wide formhash the form needs; the
    // GET also proves the website session can actually see the group.
    final formhash = await _loadWebsiteFormhash(topicPath, session);
    await _verifyWebsiteWriteContext(identity, session.authenticationKey);
    final Response<String> response;
    try {
      response = await _htmlDio.post<String>(
        '$topicPath/new_reply?ajax=1',
        data: {
          'lastview': '',
          'formhash': formhash,
          'content': content,
          'submit': 'submit',
          if (replyTo != null && replyTo > 0) ...{
            'topic_id': '$topicId',
            'related': '$replyTo',
          },
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          followRedirects: false,
          headers: {
            ...session.requestHeaders,
            'Referer': 'https://bgm.tv$topicPath',
            'Origin': 'https://bgm.tv',
            'X-Requested-With': 'XMLHttpRequest',
          },
          validateStatus: (status) => status != null && status < 600,
        ),
      );
    } on DioException {
      throw const CommunitySubmissionUncertain('回复结果未知，请刷新话题确认，避免重复发送');
    }
    await _verifyWebsiteWriteContext(
      identity,
      session.authenticationKey,
      submitted: true,
    );
    final body = response.data ?? '';
    _throwIfWebsiteChallenge(
      body,
      session,
      cfMitigated: response.headers.value('cf-mitigated'),
      recoveryUri: Uri.parse('https://bgm.tv$topicPath'),
    );
    if ((response.statusCode ?? 0) >= 500 || response.statusCode == 429) {
      throw FormatException('网站暂时无法响应（HTTP ${response.statusCode}），请刷新确认回复结果');
    }
    checkLoginPage(body, session);
    if (response.statusCode == 401 ||
        isWebsiteLoginRedirect(
          response.statusCode,
          response.headers.value('location'),
        )) {
      _websiteFailed(WebsiteAccessStatus.expired, session);
      throw const WebsiteAccessException(
        WebsiteAccessStatus.expired,
        '网页版登录已过期，请重新登录网页版后再回复',
      );
    }
    // With ?ajax=1 the classic site answers JSON: {"posts": …} on success.
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      decoded = null;
    }
    if (decoded is Map) {
      final detail = decoded['error'] ?? decoded['message'];
      if (detail != null && detail.toString().trim().isNotEmpty) {
        throw FormatException('回复失败：${detail.toString().trim()}');
      }
      final status = response.statusCode ?? 0;
      final posts = decoded['posts'];
      final hasPosts = switch (posts) {
        String value => value.trim().isNotEmpty,
        Map value => value.isNotEmpty,
        List value => value.isNotEmpty,
        _ => false,
      };
      if (status >= 200 &&
          status < 300 &&
          (hasPosts || decoded['status'] == 'ok')) {
        return;
      }
    }
    final notice = PmHtmlParser().parseSubmissionError(body);
    if (notice != null) throw FormatException('回复失败：$notice');
    final status = response.statusCode;
    if (status != null && status >= 400) {
      throw FormatException('回复失败（HTTP $status）');
    }
    throw const FormatException('回复结果未知，请刷新话题页确认是否已发出');
  }

  Future<String> _loadWebsiteFormhash(
    String path,
    WebsiteSessionSnapshot session,
  ) async {
    final html = await fetchHtml(path, session);
    checkLoginPage(html, session);
    final fromPage = _htmlParser.parseFormhash(html);
    if (fromPage != null) return fromPage;
    // Private-group / permission pages omit the reply form. The homepage
    // still carries the session formhash on the logout link when cookies
    // actually authenticated.
    if (path != '/') {
      final home = await fetchHtml('/', session);
      checkLoginPage(home, session);
      final fromHome = _htmlParser.parseFormhash(home);
      if (fromHome != null) return fromHome;
    }
    throw const FormatException('暂时无法获取网页操作参数，请刷新后重试');
  }

  Future<void> _verifyWebsiteWriteContext(
    int identity,
    String authenticationKey, {
    bool submitted = false,
  }) async {
    try {
      if (identity != readIdentity()) {
        throw const FormatException('账号已变化，请重新操作');
      }
      final current = await requireSession();
      if (identity != readIdentity() ||
          current.authenticationKey != authenticationKey) {
        throw const FormatException('网页登录已变化，请刷新页面后再提交');
      }
    } catch (_) {
      if (submitted) {
        throw const CommunitySubmissionUncertain('登录已变化，请返回原账号核对提交结果，避免重复发送');
      }
      rethrow;
    }
  }

  Future<String> fetchHtml(String path, WebsiteSessionSnapshot session) async {
    final response = await _htmlDio.get<String>(
      path,
      options: Options(
        headers: {...session.requestHeaders, 'Referer': 'https://bgm.tv/'},
        followRedirects: false,
        validateStatus: (status) => status != null && status < 600,
      ),
    );
    _throwIfWebsiteChallenge(
      response.data ?? '',
      session,
      cfMitigated: response.headers.value('cf-mitigated'),
      recoveryUri: response.requestOptions.uri,
    );
    if ((response.statusCode ?? 0) >= 500 || response.statusCode == 429) {
      throw FormatException('网站暂时无法响应（HTTP ${response.statusCode}），已保留登录');
    }
    if (response.statusCode == 401 ||
        isWebsiteLoginRedirect(
          response.statusCode,
          response.headers.value('location'),
        )) {
      _websiteFailed(WebsiteAccessStatus.expired, session);
      throw const WebsiteAccessException(
        WebsiteAccessStatus.expired,
        '网页版登录已过期，请重新登录网页版后再试',
      );
    }
    if (response.statusCode == null ||
        response.statusCode! < 200 ||
        response.statusCode! >= 300) {
      throw FormatException('网页内容暂时不可用（HTTP ${response.statusCode}），已保留登录');
    }
    return response.data ?? '';
  }

  void _throwIfWebsiteChallenge(
    String html,
    WebsiteSessionSnapshot session, {
    String? cfMitigated,
    Uri? recoveryUri,
  }) {
    if (WebsiteIdentityProbe.isChallenge(html, cfMitigated: cfMitigated)) {
      _websiteFailed(
        WebsiteAccessStatus.challenge,
        session,
        recoveryUri: recoveryUri,
      );
      throw const WebsiteAccessException(
        WebsiteAccessStatus.challenge,
        'Bangumi 需要网页验证，请补充账号验证后继续',
      );
    }
  }

  void checkLoginPage(String html, WebsiteSessionSnapshot session) {
    _throwIfWebsiteChallenge(html, session);
    if (PmHtmlParser().looksLikeLoginPage(html)) {
      _websiteFailed(WebsiteAccessStatus.expired, session);
      throw const WebsiteAccessException(
        WebsiteAccessStatus.expired,
        '网页版登录已过期，请重新登录网页版后再试',
      );
    }
  }
}

/// Reads a confirmed positive topic ID from either JSON submission receipt.
int? parseCreatedCommunityTopicId(Object? result) {
  if (result is! Map) return null;
  final value = result['id'];
  return value is int && value > 0 ? value : null;
}
