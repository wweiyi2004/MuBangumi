import 'package:dio/dio.dart';

import '../auth/website_session.dart';
import '../auth/website_identity.dart';
import '../../models/pm_models.dart';
import '../../models/bangumi_models.dart';
import 'bangumi_user_agent.dart';
import 'pm_html_parser.dart';

/// Cookie-authenticated Bangumi website PM client (HTML endpoints).
class PmService {
  PmService({WebsiteSessionStore? sessionStore, Dio? dio, PmHtmlParser? parser})
    : _sessionStore = sessionStore ?? WebsiteSessionStore(),
      _parser = parser ?? PmHtmlParser(),
      _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: 'https://bgm.tv',
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 25),
              responseType: ResponseType.plain,
              followRedirects: true,
              validateStatus: (code) => code != null && code < 500,
              headers: const {
                'User-Agent': muBangumiUserAgent,
                'Accept': 'text/html,application/xhtml+xml',
              },
            ),
          );

  void dispose() => _dio.close(force: true);
  Future<WebsiteSessionSnapshot> Function()? websiteSessionGuard;
  bool Function(WebsiteAccessStatus status, String requestKey)?
  onWebsiteSessionFailure;

  final WebsiteSessionStore _sessionStore;
  final PmHtmlParser _parser;
  final Dio _dio;
  final _formSessions = Expando<String>('PM form website session');

  Future<({int userId, String authenticationKey})> verifyDraftOwner(
    BangumiUser user,
  ) async {
    if (user.id <= 0) throw const PmAuthException('请先登录应用账号');
    final session = await _requireSession();
    if (session.verifiedUserId != null) {
      if (session.verifiedUserId != user.id) {
        throw const PmAuthException('网站登录与应用账号不一致，请登录同一个 Bangumi 账号');
      }
      return (userId: user.id, authenticationKey: session.authenticationKey);
    }
    final html = await _getHtml('/');
    if ((await _requireSession()).authenticationKey !=
        session.authenticationKey) {
      throw const PmAuthException('网站登录已变化，请重新核对');
    }
    final identifier = _parser.parseSignedInUser(html);
    if (identifier == null) {
      throw const PmException('暂时无法识别网站账号，已保留登录，请稍后重试');
    }
    if (identifier != '${user.id}' &&
        identifier.toLowerCase() != user.username.toLowerCase()) {
      throw const PmAuthException('网站登录与应用账号不一致，请登录同一个 Bangumi 账号');
    }
    return (userId: user.id, authenticationKey: session.authenticationKey);
  }

  Future<List<PmConversation>> loadInbox({int page = 1}) =>
      _loadList('/pm/inbox.chii', page: page);

  Future<List<PmConversation>> loadOutbox({int page = 1}) =>
      _loadList('/pm/outbox.chii', page: page);

  Future<List<PmConversation>> _loadList(
    String path, {
    required int page,
  }) async {
    final html = await _getHtml(path, query: {'page': page});
    return _parser.parseConversationList(html);
  }

  Future<PmConversationDetail> loadConversation(
    String conversationId, {
    String? threadId,
  }) async {
    final query = <String, dynamic>{'page': 1};
    if (threadId != null && threadId.isNotEmpty) {
      query['thread'] = threadId;
    }
    String? sessionKey;
    final html = await _getHtml(
      '/pm/conversation/$conversationId.chii',
      onSession: (value) => sessionKey = value,
      query: query,
    );
    final detail = _parser.parseConversationDetail(html);
    _formSessions[detail.form] = sessionKey;
    return detail;
  }

  Future<PmComposeParams> loadComposeParams(String userIdOrUsername) async {
    final encoded = Uri.encodeComponent(userIdOrUsername.trim());
    String? sessionKey;
    final html = await _getHtml(
      '/pm/compose/$encoded.chii',
      onSession: (value) => sessionKey = value,
    );
    final params = _parser.parseComposeParams(html);
    if (!params.isValid) {
      throw const PmException('无法获取发信参数，请确认对方用户存在且已同步网站登录');
    }
    _formSessions[params] = sessionKey;
    return params;
  }

  Future<void> reply({
    required PmReplyForm form,
    required String body,
    String? title,
  }) async {
    if (!form.isValid) {
      throw const PmException('回复表单无效，请刷新会话后重试');
    }
    final text = body.trim();
    if (text.isEmpty) throw const PmException('请输入短信内容');
    final msgTitle = (title ?? form.msgTitle).trim();
    await _postCreate({
      'related': form.related,
      'msg_receivers': form.msgReceivers,
      'current_msg_id': '',
      'formhash': form.formhash,
      'msg_title': msgTitle.isEmpty ? form.msgTitle : msgTitle,
      'msg_body': text,
      if (form.newTopic != null) 'new_topic': form.newTopic,
      'chat': 'on',
      'submit': '回复',
    }, expectedSession: _formSessions[form]);
  }

  Future<void> compose({
    required PmComposeParams params,
    required String title,
    required String body,
  }) async {
    if (!params.isValid) {
      throw const PmException('发信参数无效，请重新打开发信页');
    }
    final t = title.trim();
    final b = body.trim();
    if (t.isEmpty) throw const PmException('请填写标题');
    if (b.isEmpty) throw const PmException('请填写内容');
    await _postCreate({
      'msg_receivers': params.msgReceivers,
      'formhash': params.formhash,
      'msg_title': t,
      'msg_body': b,
      'submit': '发送',
    }, expectedSession: _formSessions[params]);
  }

  Future<void> _postCreate(
    Map<String, dynamic> data, {
    String? expectedSession,
  }) async {
    final session = await _requireSession();
    if (expectedSession != null &&
        session.authenticationKey != expectedSession) {
      throw const PmAuthException('网站登录已变化，请重新打开私信后再发送');
    }
    try {
      final response = await _dio.post<String>(
        '/pm/create.chii',
        data: data,
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {
            ...session.requestHeaders,
            'Referer': 'https://bgm.tv/pm',
            'Origin': 'https://bgm.tv',
          },
        ),
      );
      final body = response.data ?? '';
      if (WebsiteIdentityProbe.isChallenge(
        body,
        cfMitigated: response.headers.value('cf-mitigated'),
      )) {
        _reportFailure(WebsiteAccessStatus.challenge, session, submitted: true);
        throw const PmAuthException('Bangumi 需要网页验证，请补充账号验证后继续');
      }
      if ((response.statusCode ?? 0) >= 500) throw const PmDeliveryUncertain();
      if (_parser.looksLikeLoginPage(body) || response.statusCode == 401) {
        _reportFailure(WebsiteAccessStatus.expired, session, submitted: true);
        throw const PmAuthException();
      }
      final submissionError = _parser.parseSubmissionError(body);
      if (submissionError != null) {
        throw PmException('发送失败：$submissionError');
      }
      if (response.statusCode != null &&
          response.statusCode! >= 400 &&
          response.statusCode != 302) {
        throw PmException('发送失败（HTTP ${response.statusCode}）');
      }
      // A successful send may stay on /pm/create.chii without a redirect, and
      // the compose page always contains the submission form, so the response
      // URL and form presence are not reliable failure signals. Success is
      // decided by the notice parsing and status code above.
    } on DioException catch (error) {
      if (error.response == null || (error.response?.statusCode ?? 0) >= 500) {
        throw const PmDeliveryUncertain();
      }
      throw PmException('发送失败（HTTP ${error.response?.statusCode}）');
    }
  }

  Future<String> _getHtml(
    String path, {
    Map<String, dynamic>? query,
    void Function(String)? onSession,
    bool retriedSession = false,
  }) async {
    final session = await _requireSession();
    onSession?.call(session.authenticationKey);
    try {
      final response = await _dio.get<String>(
        path,
        queryParameters: query,
        options: Options(
          headers: {...session.requestHeaders, 'Referer': 'https://bgm.tv/pm'},
        ),
      );
      final current = await _requireSession();
      if (current.authenticationKey != session.authenticationKey) {
        throw const PmAuthException('网站登录已变化，请重新打开私信');
      }
      if (current.requestKey != session.requestKey) {
        if (retriedSession) {
          throw const PmException('网页登录已更新，请刷新消息后重试');
        }
        // GET is safe to repeat. Never replay a private-message submission.
        return _getHtml(
          path,
          query: query,
          onSession: onSession,
          retriedSession: true,
        );
      }
      final html = response.data ?? '';
      final location = response.realUri.toString();
      if (WebsiteIdentityProbe.isChallenge(
        html,
        cfMitigated: response.headers.value('cf-mitigated'),
      )) {
        _reportFailure(WebsiteAccessStatus.challenge, session);
        throw const PmAuthException('Bangumi 需要网页验证，请补充账号验证后继续');
      }
      if ((response.statusCode ?? 0) >= 500 || response.statusCode == 429) {
        throw PmException('加载失败（HTTP ${response.statusCode}），已保留登录');
      }
      if (response.statusCode == 401 ||
          location.contains('/login') ||
          _parser.looksLikeLoginPage(html)) {
        _reportFailure(WebsiteAccessStatus.expired, session);
        throw const PmAuthException();
      }
      if (response.statusCode != null && response.statusCode! >= 400) {
        throw PmException('加载失败（HTTP ${response.statusCode}）');
      }
      return html;
    } on DioException catch (error) {
      if (error.error is PmAuthException) rethrow;
      throw PmException('加载失败：${error.message ?? error}');
    }
  }

  void _reportFailure(
    WebsiteAccessStatus status,
    WebsiteSessionSnapshot session, {
    bool submitted = false,
  }) {
    if (onWebsiteSessionFailure?.call(status, session.requestKey) == false) {
      if (submitted) throw const PmDeliveryUncertain();
      throw const PmException('网页登录已更新，请刷新消息后重试');
    }
  }

  Future<WebsiteSessionSnapshot> _requireSession() async {
    final guard = websiteSessionGuard;
    if (guard != null) {
      try {
        return await guard();
      } on WebsiteAccessException catch (error) {
        if (!error.status.requiresLogin) {
          throw PmException(error.message);
        }
        throw PmAuthException(error.message);
      }
    }
    final snapshot = await _sessionStore.read();
    final header = snapshot?.cookieHeader.trim() ?? '';
    if (snapshot == null || header.isEmpty || !snapshot.hasSessionCookies) {
      throw const PmAuthException();
    }
    return snapshot;
  }
}
