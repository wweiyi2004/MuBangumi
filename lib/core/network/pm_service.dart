import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../auth/website_session.dart';
import '../auth/website_identity.dart';
import '../../models/pm_models.dart';
import '../../models/bangumi_models.dart';
import 'bangumi_user_agent.dart';
import 'pm_html_parser.dart';
import '../diagnostics/account_diagnostics.dart';
import 'account_diagnostics_interceptor.dart';

/// Cookie-authenticated Bangumi website PM client (HTML endpoints).
class PmService {
  PmService({
    WebsiteSessionStore? sessionStore,
    Dio? dio,
    PmHtmlParser? parser,
    Future<void> Function(Duration)? retryDelay,
    DateTime Function()? now,
    AccountDiagnostics? diagnostics,
  }) : _sessionStore = sessionStore ?? WebsiteSessionStore(),
       _parser = parser ?? PmHtmlParser(),
       _retryDelay = retryDelay ?? Future<void>.delayed,
       _now = now ?? DateTime.now,
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
           ) {
    if (_dio.options.baseUrl.isEmpty) _dio.options.baseUrl = 'https://bgm.tv';
    _dio.interceptors.add(
      AccountDiagnosticsInterceptor(
        diagnostics ?? AccountDiagnostics(),
        AccountArea.privateMessages,
      ),
    );
  }

  void dispose() => _dio.close(force: true);
  Future<WebsiteSessionSnapshot> Function()? websiteSessionGuard;
  WebsiteSessionFailureReporter? onWebsiteSessionFailure;
  WebsiteResponseCookieReceiver? onWebsiteResponseCookies;

  final WebsiteSessionStore _sessionStore;
  final PmHtmlParser _parser;
  final Dio _dio;
  final _formSessions = Expando<String>('PM form website session');
  final _reads = <String, Future<String>>{};
  final Future<void> Function(Duration) _retryDelay;
  final DateTime Function() _now;
  String? _cooldownKey;
  DateTime? _retryAt;
  int _activeHtmlRequests = 0;
  final _htmlWaiters = Queue<Completer<void>>();

  Future<T> _withHtmlSlot<T>(Future<T> Function() request) async {
    if (_activeHtmlRequests >= 2) {
      final waiter = Completer<void>();
      _htmlWaiters.add(waiter);
      await waiter.future;
    } else {
      _activeHtmlRequests++;
    }
    try {
      return await request();
    } finally {
      if (_htmlWaiters.isNotEmpty) {
        _htmlWaiters.removeFirst().complete();
      } else {
        _activeHtmlRequests--;
      }
    }
  }

  Future<WebsiteSessionSnapshot> _absorbCookies(
    Response<String> response,
    WebsiteSessionSnapshot session,
  ) async {
    final cookies = parseWebsiteResponseCookies(
      response.headers['set-cookie'],
      response.requestOptions.uri,
    );
    if (cookies.isEmpty || onWebsiteResponseCookies == null) return session;
    return await onWebsiteResponseCookies!(session.requestKey, cookies) ??
        session;
  }

  Future<({int userId, String authenticationKey, String requestKey})>
  verifyDraftOwner(BangumiUser user) async {
    if (user.id <= 0) throw const PmAuthException('请先登录应用账号');
    final session = await _requireSession();
    if (session.verificationVersion == 2 && session.verifiedUserId != null) {
      if (session.verifiedUserId != user.id) {
        throw const PmAuthException('网站登录与应用账号不一致，请登录同一个 Bangumi 账号');
      }
      if (session.isVerifiedFor(user.id, DateTime.now())) {
        return (
          userId: user.id,
          authenticationKey: session.authenticationKey,
          requestKey: session.requestKey,
        );
      }
    }
    final html = await _getHtml('/');
    final current = await _requireSession();
    if (current.authenticationKey != session.authenticationKey) {
      throw const PmAuthException('网站登录已变化，请重新核对');
    }
    if (current.requestKey != session.requestKey) {
      throw const PmException('验证期间网站会话已更新，请重试核对');
    }
    final identifier = _parser.parseSignedInUser(html);
    if (identifier == null) {
      throw const PmException('暂时无法识别网站账号，已保留登录，请稍后重试');
    }
    if (identifier != '${user.id}' &&
        identifier.toLowerCase() != user.username.toLowerCase()) {
      throw const PmAuthException('网站登录与应用账号不一致，请登录同一个 Bangumi 账号');
    }
    return (
      userId: user.id,
      authenticationKey: session.authenticationKey,
      requestKey: session.requestKey,
    );
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
    final items = _parser.parseConversationList(html);
    if (items.isEmpty && !_parser.hasMailboxLayout(html)) {
      throw const PmException('未能识别返回的消息列表，已保留当前记录，请稍后重试');
    }
    return items;
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
    if (detail.messages.isEmpty && !detail.form.isValid) {
      throw const PmException('未能读取会话内容，已保留当前记录，请稍后重试');
    }
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
    late WebsiteSessionSnapshot session;
    try {
      session = await _requireSession();
      _throwIfCoolingDown(session);
      if (expectedSession != null &&
          session.authenticationKey != expectedSession) {
        throw const PmAuthException('网站登录已变化，请重新打开私信后再发送');
      }
    } on PmAuthException catch (error) {
      throw PmPreflightAuthException(error.message);
    }
    try {
      final response = await _withHtmlSlot(() async {
        late final WebsiteSessionSnapshot current;
        try {
          current = await _requireSession();
        } on PmAuthException catch (error) {
          throw PmPreflightAuthException(error.message);
        }
        if (current.authenticationKey != session.authenticationKey) {
          throw const PmPreflightAuthException('网站登录已变化，请重新打开私信后再发送');
        }
        session = current;
        _throwIfCoolingDown(session);
        return _dio.post<String>(
          '/pm/create.chii',
          data: data,
          options: Options(
            contentType: Headers.formUrlEncodedContentType,
            responseType: ResponseType.plain,
            followRedirects: false,
            validateStatus: (code) => code != null && code < 600,
            headers: {
              ...session.requestHeaders,
              'Referer': 'https://bgm.tv/pm',
              'Origin': 'https://bgm.tv',
            },
          ),
        );
      });
      session = await _absorbCookies(response, session);
      final body = response.data ?? '';
      if (WebsiteIdentityProbe.isChallenge(
        body,
        cfMitigated: response.headers.value('cf-mitigated'),
      )) {
        _reportFailure(
          WebsiteAccessStatus.challenge,
          session,
          submitted: true,
          recoveryUri: Uri.parse('https://bgm.tv/pm'),
        );
        throw const PmAuthException('Bangumi 需要网页验证，请补充账号验证后继续');
      }
      if ((response.statusCode ?? 0) >= 500) throw const PmDeliveryUncertain();
      if (response.statusCode == 429) {
        _recordCooldown(response, session);
        _throwIfCoolingDown(session);
      }
      if (_parser.looksLikeLoginPage(body) ||
          response.statusCode == 401 ||
          isWebsiteLoginRedirect(
            response.statusCode,
            response.headers.value('location'),
          )) {
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
      if (!_parser.hasSubmissionSuccess(body) &&
          !_hasSubmissionRedirect(response)) {
        // An HTTP 200/form alone is not an acknowledgement of a write. Keep
        // the command for confirmation instead of silently discarding it.
        throw const PmDeliveryUncertain();
      }
    } on DioException catch (error) {
      if (error.response == null || (error.response?.statusCode ?? 0) >= 500) {
        throw const PmDeliveryUncertain();
      }
      throw PmException('发送失败（HTTP ${error.response?.statusCode}）');
    } finally {
      // A post may change the mailbox even if its response was lost. A later
      // refresh must not join a read that started before this submission.
      _reads.clear();
    }
  }

  bool _hasSubmissionRedirect(Response<String> response) {
    final status = response.statusCode ?? 0;
    final location = response.headers.value('location');
    final destination = const [302, 303].contains(status) && location != null
        ? Uri.parse('https://bgm.tv/pm/create.chii').resolve(location)
        : response.redirects.isNotEmpty
        ? response.realUri
        : null;
    if (destination == null ||
        destination.scheme != 'https' ||
        destination.host != 'bgm.tv' ||
        destination.port != 443 ||
        destination.userInfo.isNotEmpty) {
      return false;
    }
    return const [
          '/pm',
          '/pm/inbox.chii',
          '/pm/outbox.chii',
        ].contains(destination.path) ||
        RegExp(
          r'^/pm/conversation/\d+(?:\.chii)?/?$',
        ).hasMatch(destination.path);
  }

  Future<String> _getHtml(
    String path, {
    Map<String, dynamic>? query,
    void Function(String)? onSession,
  }) async {
    final session = await _requireSession();
    _throwIfCoolingDown(session);
    onSession?.call(session.authenticationKey);
    final key = jsonEncode([session.requestKey, path, query]);
    final active = _reads[key];
    if (active != null) return active;
    final future = _readHtml(path, session, query: query);
    _reads[key] = future;
    try {
      return await future;
    } finally {
      if (identical(_reads[key], future)) _reads.remove(key);
    }
  }

  Future<String> _readHtml(
    String path,
    WebsiteSessionSnapshot session, {
    Map<String, dynamic>? query,
    bool retriedSession = false,
    bool retriedNetwork = false,
    bool retriedChallenge = false,
  }) async {
    try {
      final response = await _withHtmlSlot(() async {
        final current = await _requireSession();
        if (current.authenticationKey != session.authenticationKey) {
          throw const PmAuthException('网站登录已变化，请重新打开私信');
        }
        // Preserve stale-response detection for renewals while waiting in the gate.
        session = current;
        _throwIfCoolingDown(session);
        return _dio.get<String>(
          path,
          queryParameters: query,
          options: Options(
            responseType: ResponseType.plain,
            followRedirects: false,
            validateStatus: (code) => code != null && code < 600,
            headers: {
              ...session.requestHeaders,
              'Referer': 'https://bgm.tv/pm',
            },
          ),
        );
      });
      session = await _absorbCookies(response, session);
      final current = await _requireSession();
      if (current.authenticationKey != session.authenticationKey) {
        throw const PmAuthException('网站登录已变化，请重新打开私信');
      }
      if (current.requestKey != session.requestKey) {
        if (retriedSession) {
          throw const PmException('网页登录已更新，请刷新消息后重试');
        }
        // GET is safe to repeat. Never replay a private-message submission.
        return _readHtml(
          path,
          current,
          query: query,
          retriedSession: true,
          retriedNetwork: retriedNetwork,
          retriedChallenge: retriedChallenge,
        );
      }
      final html = response.data ?? '';
      final location = response.realUri.toString();
      if (WebsiteIdentityProbe.isChallenge(
        html,
        cfMitigated: response.headers.value('cf-mitigated'),
      )) {
        if (!retriedChallenge) {
          await _retryDelay(const Duration(seconds: 2));
          final renewed = await _requireSession();
          if (renewed.authenticationKey != session.authenticationKey) {
            throw const PmAuthException('网站登录已变化，请重新打开私信');
          }
          _throwIfCoolingDown(renewed);
          return _readHtml(
            path,
            renewed,
            query: query,
            retriedSession: retriedSession,
            retriedNetwork: retriedNetwork,
            retriedChallenge: true,
          );
        }
        _reportFailure(
          WebsiteAccessStatus.challenge,
          session,
          recoveryUri: response.requestOptions.uri,
        );
        throw const PmAuthException('Bangumi 需要网页验证，请补充账号验证后继续');
      }
      if ((response.statusCode ?? 0) >= 500 || response.statusCode == 429) {
        _recordCooldown(response, session);
        _throwIfCoolingDown(session);
        if (!retriedNetwork && _transientStatus(response.statusCode)) {
          return _retryRead(
            path,
            session,
            query,
            retriedSession,
            retriedChallenge,
          );
        }
        throw PmException('加载失败（HTTP ${response.statusCode}），已保留登录');
      }
      if (response.statusCode == 401 ||
          location.contains('/login') ||
          isWebsiteLoginRedirect(
            response.statusCode,
            response.headers.value('location'),
          ) ||
          _parser.looksLikeLoginPage(html)) {
        _reportFailure(WebsiteAccessStatus.expired, session);
        throw const PmAuthException();
      }
      if (response.statusCode != null && response.statusCode! >= 400) {
        throw PmException('加载失败（HTTP ${response.statusCode}）');
      }
      return html;
    } on DioException catch (error) {
      if (!retriedNetwork &&
          const {
            DioExceptionType.connectionTimeout,
            DioExceptionType.receiveTimeout,
            DioExceptionType.connectionError,
          }.contains(error.type)) {
        return _retryRead(
          path,
          session,
          query,
          retriedSession,
          retriedChallenge,
        );
      }
      throw const PmException('消息连接暂时失败，已保留登录和当前记录，请稍后重试');
    }
  }

  Future<String> _retryRead(
    String path,
    WebsiteSessionSnapshot session,
    Map<String, dynamic>? query,
    bool retriedSession,
    bool retriedChallenge,
  ) async {
    await _retryDelay(const Duration(milliseconds: 600));
    final current = await _requireSession();
    if (current.authenticationKey != session.authenticationKey) {
      throw const PmAuthException('网站登录已变化，请重新打开私信');
    }
    _throwIfCoolingDown(current);
    return _readHtml(
      path,
      current,
      query: query,
      retriedSession: retriedSession,
      retriedNetwork: true,
      retriedChallenge: retriedChallenge,
    );
  }

  bool _transientStatus(int? status) =>
      const [500, 502, 503, 504, 520, 521, 522, 523, 524].contains(status);

  void _recordCooldown(
    Response<String> response,
    WebsiteSessionSnapshot session,
  ) {
    final raw = response.headers.value('retry-after');
    DateTime? until;
    final seconds = int.tryParse(raw ?? '');
    if (seconds != null && seconds > 0) {
      until = _now().add(Duration(seconds: seconds));
    } else if (raw != null) {
      try {
        until = HttpDate.parse(raw);
      } on HttpException {
        // An invalid Retry-After date must not replace the actual HTTP error.
      }
    }
    if (response.statusCode == 429 &&
        (until == null || !until.isAfter(_now()))) {
      until = _now().add(const Duration(seconds: 30));
    }
    if (until != null && until.isAfter(_now())) {
      if (_cooldownKey != session.authenticationKey ||
          _retryAt == null ||
          until.isAfter(_retryAt!)) {
        _cooldownKey = session.authenticationKey;
        _retryAt = until;
      }
    }
  }

  void _throwIfCoolingDown(WebsiteSessionSnapshot session) {
    if (_cooldownKey == session.authenticationKey &&
        _retryAt?.isAfter(_now()) == true) {
      final seconds = (_retryAt!.difference(_now()).inMilliseconds / 1000)
          .ceil();
      throw PmException('消息服务暂时繁忙，请在 $seconds 秒后重试，已保留登录和当前记录');
    }
  }

  void _reportFailure(
    WebsiteAccessStatus status,
    WebsiteSessionSnapshot session, {
    bool submitted = false,
    Uri? recoveryUri,
  }) {
    if (onWebsiteSessionFailure?.call(
          status,
          session.requestKey,
          recoveryUri: recoveryUri,
        ) ==
        false) {
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
