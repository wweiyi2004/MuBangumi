import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/storage/community_cache.dart';
import '../../models/bangumi_models.dart';
import '../../models/community_models.dart';
import '../auth/website_session.dart';
import 'bangumi_smiles.dart';
import 'bangumi_user_agent.dart';
import 'community_html_parser.dart';
import 'community_p1_parser.dart';
import 'pm_html_parser.dart';

/// Strong signals that a classic website page is actually the login form.
bool looksLikeWebsiteLoginPage(String source) {
  final lower = source.toLowerCase();
  return lower.contains('name="password"') ||
      lower.contains('id="loginform"') ||
      lower.contains('请先登录');
}

/// The P1 server rejected a private-group post/reply claiming the user is not
/// a member. As of 2026-08 the server checks membership with the user/group
/// ids swapped, so even the group owner gets this error.
class PrivateGroupMembershipException implements Exception {
  const PrivateGroupMembershipException(this.groupName);

  final String groupName;

  @override
  String toString() => '「$groupName」是私密小组，需要先加入小组后再回复';
}

class CommunityService {
  CommunityService._({
    Dio? htmlDio,
    Dio? p1Dio,
    WebsiteSessionStore? sessionStore,
  }) : _sessionStore = sessionStore ?? WebsiteSessionStore(),
       _htmlDio =
           htmlDio ??
           Dio(
             BaseOptions(
               baseUrl: 'https://bgm.tv',
               connectTimeout: const Duration(seconds: 12),
               receiveTimeout: const Duration(seconds: 20),
               responseType: ResponseType.plain,
               headers: const {
                 'User-Agent': muBangumiUserAgent,
                 'Accept': 'text/html,application/xhtml+xml',
               },
             ),
           ),
       _p1Dio =
           p1Dio ??
           Dio(
             BaseOptions(
               baseUrl: 'https://next.bgm.tv',
               connectTimeout: const Duration(seconds: 12),
               receiveTimeout: const Duration(seconds: 20),
               responseType: ResponseType.json,
               headers: const {
                 'User-Agent': muBangumiUserAgent,
                 'Accept': 'application/json',
               },
             ),
           );

  static final shared = CommunityService._();

  @visibleForTesting
  CommunityService.test({
    Dio? htmlDio,
    Dio? p1Dio,
    WebsiteSessionStore? sessionStore,
  }) : this._(htmlDio: htmlDio, p1Dio: p1Dio, sessionStore: sessionStore);

  final Dio _htmlDio;
  final Dio _p1Dio;
  final WebsiteSessionStore _sessionStore;
  final CommunityHtmlParser _htmlParser = CommunityHtmlParser();
  final CommunityP1Parser _p1Parser = CommunityP1Parser();
  final CommunityCache _persistentCache = CommunityCache.shared;
  final Map<String, _CachedHtml> _htmlCache = {};
  final Map<String, _CachedJson> _jsonCache = {};
  final Map<String, _CachedFriends> _friendsCache = {};
  String? _currentUsername;
  String _currentNickname = '';
  String _currentAvatarUrl = '';

  /// Called once on HTTP 401; return true if a new token was applied.
  Future<bool> Function()? onUnauthorizedRefresh;

  bool get isAuthenticated =>
      _p1Dio.options.headers['Authorization']?.toString().isNotEmpty == true;

  String? get currentUsername => _currentUsername;

  void setAccessToken(String? token) {
    if (token == null || token.trim().isEmpty) {
      _p1Dio.options.headers.remove('Authorization');
    } else {
      _p1Dio.options.headers['Authorization'] = 'Bearer ${token.trim()}';
    }
    _jsonCache.clear();
    _friendsCache.clear();
  }

  void setCurrentUsername(
    String? username, {
    String nickname = '',
    String avatarUrl = '',
  }) {
    final value = username?.trim() ?? '';
    _currentUsername = value.isEmpty ? null : value;
    _currentNickname = value.isEmpty ? '' : nickname.trim();
    _currentAvatarUrl = value.isEmpty ? '' : avatarUrl.trim();
  }

  Future<void> clearAccountCache() async {
    await _persistentCache.clearAccountData();
    _friendsCache.clear();
  }

  Future<CommunityPageResult<BangumiUser>> loadFriends(
    String username, {
    int limit = 30,
    int offset = 0,
    bool refresh = false,
  }) async {
    final cacheKey = '$username:$limit:$offset';
    if (!refresh) {
      final cached = _friendsCache[cacheKey];
      if (cached != null &&
          DateTime.now().difference(cached.createdAt) <
              const Duration(minutes: 10)) {
        return cached.page;
      }
    }
    final encoded = Uri.encodeComponent(username);
    final json = await _getJson(
      '/users/$encoded/friends',
      query: {'limit': limit, 'offset': offset},
      refresh: refresh,
    );
    final data = json['data'];
    final users = data is List
        ? data
              .whereType<Map>()
              .map(
                (item) => BangumiUser.fromJson(Map<String, dynamic>.from(item)),
              )
              .where((user) => user.username.isNotEmpty)
              .toList()
        : const <BangumiUser>[];
    final total = (json['total'] as num?)?.toInt() ?? users.length;
    final page = CommunityPageResult(data: users, total: total);
    _storeIn(
      _friendsCache,
      cacheKey,
      _CachedFriends(page, DateTime.now()),
      (value) => value.createdAt,
      const Duration(minutes: 2),
    );
    return page;
  }

  Future<CommunityPageResult<CommunityTopic>?> readCachedTopics(
    RakuenMode mode,
  ) async {
    final json = await _persistentCache.readJson(_topicCacheKey(mode));
    if (json == null) return null;
    return _parseTopicPage(mode, json);
  }

  Future<CommunityPageResult<CommunityTopic>> loadTopicPage(
    RakuenMode mode, {
    int limit = 20,
    int offset = 0,
    bool refresh = false,
  }) async {
    final path = switch (mode) {
      RakuenMode.subjectTrending => '/trending/subjects/topics',
      RakuenMode.subjectLatest => '/subjects/-/topics',
      _ => '/groups/-/topics',
    };
    final query = <String, dynamic>{
      if (!mode.isSubject) 'mode': mode.apiMode,
      'limit': limit,
      'offset': offset,
    };
    final json = await _getJson(path, query: query, refresh: refresh);
    if (offset == 0) {
      await _persistentCache.writeJson(
        _topicCacheKey(mode),
        json,
        accountScoped: mode.requiresLogin,
      );
    }
    return _parseTopicPage(mode, json);
  }

  Future<CommunityPageResult<CommunityGroup>?> readCachedGroups(
    CommunityGroupMode mode,
    CommunityGroupSort sort,
  ) async {
    final json = await _persistentCache.readJson(_groupCacheKey(mode, sort));
    if (json == null) return null;
    return CommunityPageResult(
      data: _p1Parser.parseGroups(json),
      total: _pageTotal(json),
    );
  }

  Future<CommunityPageResult<CommunityGroup>> loadGroupPage({
    CommunityGroupMode mode = CommunityGroupMode.all,
    CommunityGroupSort sort = CommunityGroupSort.members,
    int limit = 20,
    int offset = 0,
    bool refresh = false,
  }) async {
    final json = await _getJson(
      '/groups',
      query: {
        'mode': mode.name,
        'sort': sort.name,
        'limit': limit,
        'offset': offset,
      },
      refresh: refresh,
    );
    if (offset == 0) {
      await _persistentCache.writeJson(
        _groupCacheKey(mode, sort),
        json,
        accountScoped: mode.requiresLogin,
      );
    }
    return CommunityPageResult(
      data: _p1Parser.parseGroups(json),
      total: _pageTotal(json),
    );
  }

  Future<CommunityGroupDetail?> readCachedGroupDetail(String slug) async {
    final bundle = await _persistentCache.readJson('group:$slug');
    if (bundle == null) return null;
    return _parseGroupBundle(bundle);
  }

  Future<CommunityGroupDetail> loadGroupDetail(
    String slug, {
    bool refresh = false,
  }) async {
    final encoded = Uri.encodeComponent(slug);
    final values = await Future.wait([
      _getJson('/groups/$encoded', refresh: refresh),
      _getJson(
        '/groups/$encoded/members',
        query: const {'role': 0, 'limit': 20, 'offset': 0},
        refresh: refresh,
      ),
      _getJson(
        '/groups/$encoded/members',
        query: const {'role': 1, 'limit': 10, 'offset': 0},
        refresh: refresh,
      ),
      _getJson(
        '/groups/$encoded/topics',
        query: const {'limit': 20, 'offset': 0},
        refresh: refresh,
      ),
    ]);
    final bundle = <String, dynamic>{
      'group': values[0],
      'members': values[1],
      'moderators': values[2],
      'topics': values[3],
    };
    await _persistentCache.writeJson(
      'group:$slug',
      bundle,
      accountScoped: true,
    );
    return _parseGroupBundle(bundle);
  }

  Future<List<CommunityTimelineItem>?> readCachedTimeline(
    CommunityTimelineMode mode,
  ) async {
    final json = await _persistentCache.readJson('timeline:${mode.name}');
    final data = json?['data'];
    if (data is! List) return null;
    return decodeCachedTimeline(mode, data);
  }

  /// Cached own-timeline rows omit `user`; rebuild identity the same way
  /// [loadTimeline] does for a live `/users/{username}/timeline` response.
  @visibleForTesting
  List<CommunityTimelineItem> decodeCachedTimeline(
    CommunityTimelineMode mode,
    List<dynamic> data,
  ) {
    return _p1Parser.parseTimeline(
      data,
      fallbackUsername: mode == CommunityTimelineMode.me
          ? _currentUsername
          : null,
      fallbackNickname: mode == CommunityTimelineMode.me
          ? _currentNickname
          : null,
      fallbackAvatarUrl: mode == CommunityTimelineMode.me
          ? _currentAvatarUrl
          : null,
    );
  }

  Future<List<CommunityTimelineItem>> loadTimeline(
    CommunityTimelineMode mode, {
    int limit = 20,
    int? until,
    bool refresh = false,
  }) async {
    final path = mode == CommunityTimelineMode.me
        ? '/users/${Uri.encodeComponent(_requireCurrentUsername())}/timeline'
        : '/timeline';
    final data = await _getJsonList(
      path,
      query: {
        if (mode != CommunityTimelineMode.me) 'mode': mode.name,
        'limit': limit,
        'until': ?until,
      },
      refresh: refresh,
    );
    if (until == null) {
      await _persistentCache.writeJson('timeline:${mode.name}', {
        'data': data,
      }, accountScoped: mode != CommunityTimelineMode.all);
    }
    return decodeCachedTimeline(mode, data);
  }

  /// Public timeline for any username (user profile surface).
  Future<List<CommunityTimelineItem>> loadUserTimeline(
    String username, {
    int limit = 12,
    int? until,
    bool refresh = false,
    String? fallbackAvatarUrl,
    String? fallbackNickname,
  }) async {
    final value = username.trim();
    if (value.isEmpty) return const [];
    final data = await _getJsonList(
      '/users/${Uri.encodeComponent(value)}/timeline',
      query: {'limit': limit.clamp(1, 30), 'until': ?until},
      refresh: refresh,
    );
    // Same shape as the own-timeline endpoint: no `user` object per item.
    return _p1Parser.parseTimeline(
      data,
      fallbackUsername: value,
      fallbackNickname: fallbackNickname,
      fallbackAvatarUrl: fallbackAvatarUrl,
    );
  }

  Future<List<CommunityTimelineReply>> loadTimelineReplies(
    int timelineId, {
    bool refresh = false,
  }) async {
    final data = await _getJsonList(
      '/timeline/$timelineId/replies',
      refresh: refresh,
    );
    return _p1Parser.parseTimelineReplies(data);
  }

  Future<void> createGroupTopic({
    required String slug,
    required String title,
    required String content,
    required String turnstileToken,
  }) async {
    _requireAuthentication();
    final token = _requireTurnstileToken(turnstileToken);
    await _postJson(
      '/groups/${Uri.encodeComponent(slug)}/topics',
      data: {'title': title, 'content': content, 'turnstileToken': token},
    );
  }

  Future<void> replyToTopic({
    required CommunityTopic topic,
    required String content,
    required String turnstileToken,
    int? replyTo,
  }) => _replyToTopicViaP1(
    topic: topic,
    content: content,
    turnstileToken: turnstileToken,
    replyTo: replyTo,
  );

  /// Adds, changes, or removes the signed-in user's reaction on a reply.
  Future<void> updatePostReaction({
    required CommunityTopic topic,
    required CommunityPost post,
    required int? value,
  }) async {
    _requireAuthentication();
    final area = switch (topic.kind) {
      CommunityTopicKind.group => 'groups',
      CommunityTopicKind.subject => 'subjects',
      _ => throw const FormatException('暂不支持给此类话题贴贴'),
    };
    final postId = parseReplyId(post.id);
    if (postId == null) throw const FormatException('无法识别回复编号');
    if (value != null && !BangumiReactions.accepts(value)) {
      throw const FormatException('不支持这个贴贴表情');
    }
    final path = '/$area/-/posts/$postId/like';
    if (value == null) {
      await _deleteJson(path);
    } else {
      await _putJson(path, data: {'value': value});
    }
    final topicId = resolveTopicId(topic);
    if (topicId != null) {
      _jsonCache.removeWhere(
        (key, _) => key.contains('/$area/-/topics/$topicId'),
      );
    }
  }

  Future<void> _replyToTopicViaP1({
    required CommunityTopic topic,
    required String content,
    required String turnstileToken,
    int? replyTo,
  }) async {
    _requireAuthentication();
    final area = switch (topic.kind) {
      CommunityTopicKind.group => 'groups',
      CommunityTopicKind.subject => 'subjects',
      _ => throw const FormatException('暂不支持回复此类话题'),
    };
    final id = resolveTopicId(topic);
    if (id == null) {
      throw const FormatException('无法识别话题编号，请从话题列表重新打开后再试');
    }
    final trimmed = content.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('回复内容不能为空');
    }
    final token = _requireTurnstileToken(turnstileToken);
    try {
      await _postJson(
        '/$area/-/topics/$id/replies',
        data: {
          'content': trimmed,
          'turnstileToken': token,
          'replyTo': replyTo ?? 0,
        },
      );
    } on PrivateGroupMembershipException {
      // The P1 server currently checks private-group membership with the
      // user/group ids swapped, so even the group owner is rejected. Fall
      // back to the classic website form, which validates membership
      // correctly. Only group topics can raise this error.
      await _replyToGroupTopicViaWebsite(
        topicId: id,
        content: trimmed,
        replyTo: replyTo,
      );
    }
    _jsonCache.removeWhere(
      (key, _) => key.contains('/topics/$id') || key.contains('topic'),
    );
    _htmlCache.removeWhere((key, _) => key.contains('/group/topic/$id'));
  }

  /// Posts a group topic reply through the classic website form
  /// (`/group/topic/{id}/new_reply`) using the stored website session.
  Future<void> _replyToGroupTopicViaWebsite({
    required int topicId,
    required String content,
    int? replyTo,
  }) async {
    final cookie = await _requireWebsiteCookieHeader();
    final topicPath = '/group/topic/$topicId';
    // The topic page carries the session-wide formhash the form needs; the
    // GET also proves the website session can actually see the group.
    final formhash = await _loadWebsiteFormhash(topicPath, cookie);
    final response = await _htmlDio.post<String>(
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
        headers: {
          'Cookie': cookie,
          'Referer': 'https://bgm.tv$topicPath',
          'Origin': 'https://bgm.tv',
          'X-Requested-With': 'XMLHttpRequest',
        },
        validateStatus: (status) => status != null && status < 500,
      ),
    );
    final body = response.data ?? '';
    if (response.statusCode == 401 || looksLikeWebsiteLoginPage(body)) {
      throw const FormatException('网页版登录已过期，请重新登录网页版后再回复');
    }
    // With ?ajax=1 the classic site answers JSON: {"posts": …} on success.
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      decoded = null;
    }
    if (decoded is Map) {
      if (decoded.containsKey('posts') || decoded['status'] == 'ok') return;
      final detail = decoded['error'] ?? decoded['message'];
      if (detail != null && detail.toString().trim().isNotEmpty) {
        throw FormatException('回复失败：${detail.toString().trim()}');
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

  Future<String> _loadWebsiteFormhash(String topicPath, String cookie) async {
    final response = await _htmlDio.get<String>(
      topicPath,
      options: Options(headers: {'Cookie': cookie}),
    );
    final html = response.data ?? '';
    if (response.statusCode == 401 || looksLikeWebsiteLoginPage(html)) {
      throw const FormatException('网页版登录已过期，请重新登录网页版后再回复');
    }
    final formhash = _htmlParser.parseFormhash(html);
    if (formhash == null) {
      throw const FormatException('无法获取网页版表单参数，请稍后重试');
    }
    return formhash;
  }

  Future<String> _requireWebsiteCookieHeader() async {
    final snapshot = await _sessionStore.read();
    final header = snapshot?.cookieHeader.trim() ?? '';
    if (snapshot == null || header.isEmpty || !snapshot.hasSessionCookies) {
      throw const FormatException(
        '该小组为私密小组，需要走网站通道回复：请先在「我的」→「同步网站登录」中完成登录后重试',
      );
    }
    return header;
  }

  Future<void> postTimeline({
    required String content,
    required String turnstileToken,
  }) async {
    _requireAuthentication();
    final token = _requireTurnstileToken(turnstileToken);
    await _postJson(
      '/timeline',
      data: {'content': content, 'turnstileToken': token},
    );
  }

  Future<void> replyToTimeline({
    required int timelineId,
    required String content,
    required String turnstileToken,
    int? replyTo,
  }) async {
    _requireAuthentication();
    final token = _requireTurnstileToken(turnstileToken);
    await _postJson(
      '/timeline/$timelineId/replies',
      data: {'content': content, 'turnstileToken': token, 'replyTo': ?replyTo},
    );
  }

  CommunityPageResult<CommunityTopic> _parseTopicPage(
    RakuenMode mode,
    Map<String, dynamic> json,
  ) => CommunityPageResult(
    data: mode.isSubject
        ? _p1Parser.parseSubjectTopics(json)
        : _p1Parser.parseGroupTopics(json),
    total: _pageTotal(json),
  );

  CommunityGroupDetail _parseGroupBundle(Map<String, dynamic> bundle) {
    final group = _map(bundle['group']);
    if (group == null) throw const FormatException('小组缓存损坏');
    return _p1Parser.parseGroupDetail(
      group,
      membersPage: _map(bundle['members']),
      moderatorsPage: _map(bundle['moderators']),
      topicsPage: _map(bundle['topics']),
    );
  }

  int _pageTotal(Map<String, dynamic> page) =>
      (page['total'] as num?)?.toInt() ?? 0;

  String _topicCacheKey(RakuenMode mode) => 'topics:${mode.name}';

  String _groupCacheKey(CommunityGroupMode mode, CommunityGroupSort sort) =>
      'groups:${mode.name}:${sort.name}';

  Future<List<CommunityTopic>> loadRakuen({
    String type = '',
    bool refresh = false,
  }) async {
    if (type == 'group') return _loadGroupTopics(refresh: refresh);
    if (type == 'subject') return _loadSubjectTopics(refresh: refresh);
    if (type.isEmpty) {
      try {
        final pages = await Future.wait([
          _getJson(
            '/groups/-/topics',
            query: const {'mode': 'all', 'limit': 30, 'offset': 0},
            refresh: refresh,
          ),
          _getJson(
            '/subjects/-/topics',
            query: const {'limit': 30, 'offset': 0},
            refresh: refresh,
          ),
        ]);
        final topics = [
          ..._p1Parser.parseGroupTopics(pages[0]),
          ..._p1Parser.parseSubjectTopics(pages[1]),
        ]..sort(_newestTopicFirst);
        return topics.take(50).toList();
      } catch (_) {
        return _loadRakuenHtml(type: type, refresh: refresh);
      }
    }
    return _loadRakuenHtml(type: type, refresh: refresh);
  }

  Future<CommunityLanding> loadGroups({bool refresh = false}) async {
    try {
      final pages = await Future.wait([
        _getJson(
          '/groups',
          query: const {
            'mode': 'all',
            'sort': 'members',
            'limit': 20,
            'offset': 0,
          },
          refresh: refresh,
        ),
        _getJson(
          '/groups/-/topics',
          query: const {'mode': 'all', 'limit': 40, 'offset': 0},
          refresh: refresh,
        ),
      ]);
      return CommunityLanding(
        groups: _p1Parser.parseGroups(pages[0]),
        topics: _p1Parser.parseGroupTopics(pages[1]),
      );
    } catch (_) {
      final html = await _getHtml('/group', refresh: refresh);
      return _htmlParser.parseGroupLanding(html);
    }
  }

  Future<CommunityLanding> discoverGroups({bool refresh = false}) async {
    try {
      final page = await _getJson(
        '/groups',
        query: const {
          'mode': 'all',
          'sort': 'updated',
          'limit': 60,
          'offset': 0,
        },
        refresh: refresh,
      );
      return CommunityLanding(groups: _p1Parser.parseGroups(page));
    } catch (_) {
      final html = await _getHtml('/group/all', refresh: refresh);
      return _htmlParser.parseGroupLanding(html);
    }
  }

  Future<CommunityTopicDetail> loadTopic(
    CommunityTopic topic, {
    bool refresh = false,
  }) async {
    if (topic.kind == CommunityTopicKind.group ||
        topic.kind == CommunityTopicKind.subject) {
      try {
        final id = resolveTopicId(topic);
        if (id == null) throw const FormatException('无法识别话题编号');
        final area = topic.kind == CommunityTopicKind.group
            ? 'groups'
            : 'subjects';
        final json = await _getJson('/$area/-/topics/$id', refresh: refresh);
        return _p1Parser.parseTopicDetail(json, topic);
      } catch (_) {
        // The private API has no compatibility guarantee. The public page
        // parser remains a transparent fallback if its schema changes.
      }
    }
    final html = await _getHtml(topic.webUrl, refresh: refresh);
    return _htmlParser.parseTopicDetail(html, topic);
  }

  Future<List<CommunityTopic>> _loadGroupTopics({required bool refresh}) async {
    try {
      final page = await _getJson(
        '/groups/-/topics',
        query: const {'mode': 'all', 'limit': 50, 'offset': 0},
        refresh: refresh,
      );
      return _p1Parser.parseGroupTopics(page);
    } catch (_) {
      return _loadRakuenHtml(type: 'group', refresh: refresh);
    }
  }

  Future<List<CommunityTopic>> _loadSubjectTopics({
    required bool refresh,
  }) async {
    try {
      final page = await _getJson(
        '/subjects/-/topics',
        query: const {'limit': 50, 'offset': 0},
        refresh: refresh,
      );
      return _p1Parser.parseSubjectTopics(page);
    } catch (_) {
      return _loadRakuenHtml(type: 'subject', refresh: refresh);
    }
  }

  /// Topics under a single subject (条目讨论).
  Future<List<CommunityTopic>> loadTopicsForSubject(
    int subjectId, {
    int limit = 20,
    int offset = 0,
    bool refresh = false,
  }) async {
    if (subjectId <= 0) return const [];
    try {
      final page = await _getJson(
        '/subjects/$subjectId/topics',
        query: {'limit': limit, 'offset': offset},
        refresh: refresh,
      );
      return _p1Parser.parseSubjectTopics(page);
    } catch (_) {
      return const [];
    }
  }

  Future<List<CommunityTopic>> _loadRakuenHtml({
    required String type,
    required bool refresh,
  }) async {
    final query = type.isEmpty ? null : {'type': type};
    final html = await _getHtml(
      '/rakuen/topiclist',
      query: query,
      refresh: refresh,
    );
    return _htmlParser.parseRakuen(html);
  }

  int _newestTopicFirst(CommunityTopic a, CommunityTopic b) {
    final aTime = a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bTime = b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    return bTime.compareTo(aTime);
  }

  /// Prefer the numeric topic id; fall back to parsing web/rakuen URLs.
  int? resolveTopicId(CommunityTopic topic) {
    if (topic.id > 0) return topic.id;
    for (final raw in [topic.webUrl, topic.url]) {
      final id = _topicIdFromUrl(raw);
      if (id != null) return id;
    }
    return null;
  }

  int? _topicIdFromUrl(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || uri.pathSegments.isEmpty) return null;
    for (var index = uri.pathSegments.length - 1; index >= 0; index--) {
      final value = int.tryParse(uri.pathSegments[index]);
      if (value != null && value > 0) return value;
    }
    return null;
  }

  /// HTML posts use ids like `post_3999409`; P1 uses bare integers.
  static int? parseReplyId(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    final direct = int.tryParse(value);
    if (direct != null && direct > 0) return direct;
    final match = RegExp(r'(\d+)').firstMatch(value);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  Future<String> _getHtml(
    String path, {
    Map<String, dynamic>? query,
    bool refresh = false,
  }) async {
    final uri = Uri.parse(
      path,
    ).replace(queryParameters: _stringQueryParameters(query));
    final key = uri.toString();
    final cached = _htmlCache[key];
    if (!refresh &&
        cached != null &&
        DateTime.now().difference(cached.createdAt) <
            const Duration(minutes: 2)) {
      return cached.html;
    }
    try {
      final response = await _htmlDio.get<String>(path, queryParameters: query);
      final html = response.data ?? '';
      if (html.isEmpty) throw const FormatException('Bangumi 返回了空页面');
      _storeIn(
        _htmlCache,
        key,
        _CachedHtml(html, DateTime.now()),
        (value) => value.createdAt,
        const Duration(minutes: 2),
      );
      return html;
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      throw Exception(
        status == null ? '无法连接 Bangumi 社区' : 'Bangumi 社区请求失败（$status）',
      );
    }
  }

  Future<Map<String, dynamic>> _getJson(
    String path, {
    Map<String, dynamic>? query,
    bool refresh = false,
    bool retriedAuth = false,
  }) async {
    final uri = Uri.parse(
      path,
    ).replace(queryParameters: _stringQueryParameters(query));
    final key = uri.toString();
    final cached = _jsonCache[key];
    if (!refresh &&
        cached != null &&
        DateTime.now().difference(cached.createdAt) <
            const Duration(minutes: 2)) {
      return cached.json;
    }
    DioException? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final response = await _p1Dio.get<Map<String, dynamic>>(
          '/p1$path',
          queryParameters: query,
        );
        final json = response.data;
        if (json == null) throw const FormatException('Bangumi 返回了空数据');
        _storeIn(
          _jsonCache,
          key,
          _CachedJson(json, DateTime.now()),
          (value) => value.createdAt,
          const Duration(minutes: 2),
        );
        return json;
      } on DioException catch (error) {
        lastError = error;
        if (!retriedAuth &&
            _isRefreshableAuthFailure(error) &&
            onUnauthorizedRefresh != null &&
            await onUnauthorizedRefresh!()) {
          return _getJson(path, query: query, refresh: true, retriedAuth: true);
        }
        if (!_shouldRetry(error, attempt)) break;
        await Future<void>.delayed(Duration(milliseconds: 250 * (attempt + 1)));
      }
    }
    final status = lastError?.response?.statusCode;
    throw Exception(_errorMessage(status));
  }

  Future<List<dynamic>> _getJsonList(
    String path, {
    Map<String, dynamic>? query,
    bool refresh = false,
    bool retriedAuth = false,
  }) async {
    final uri = Uri.parse(
      path,
    ).replace(queryParameters: _stringQueryParameters(query));
    final key = 'list:$uri';
    final cached = _jsonCache[key];
    if (!refresh &&
        cached != null &&
        DateTime.now().difference(cached.createdAt) <
            const Duration(minutes: 2)) {
      final data = cached.json['data'];
      if (data is List) return data;
    }
    DioException? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final response = await _p1Dio.get<List<dynamic>>(
          '/p1$path',
          queryParameters: query,
        );
        final data = response.data;
        if (data == null) throw const FormatException('Bangumi 返回了空数据');
        _storeIn(
          _jsonCache,
          key,
          _CachedJson({'data': data}, DateTime.now()),
          (value) => value.createdAt,
          const Duration(minutes: 2),
        );
        return data;
      } on DioException catch (error) {
        lastError = error;
        if (!retriedAuth &&
            _isRefreshableAuthFailure(error) &&
            onUnauthorizedRefresh != null &&
            await onUnauthorizedRefresh!()) {
          return _getJsonList(
            path,
            query: query,
            refresh: true,
            retriedAuth: true,
          );
        }
        if (!_shouldRetry(error, attempt)) break;
        await Future<void>.delayed(Duration(milliseconds: 250 * (attempt + 1)));
      }
    }
    throw Exception(_errorMessage(lastError?.response?.statusCode));
  }

  /// 电波提醒（P1 OAuth，无需网站 Cookie）。
  Future<CommunityPageResult<BangumiNotice>> loadNotices({
    int limit = 40,
    bool unreadOnly = false,
    bool refresh = false,
  }) async {
    _requireAuthentication();
    final page = await _getJson(
      '/notify',
      query: {'limit': limit.clamp(1, 40), if (unreadOnly) 'unread': true},
      refresh: refresh,
    );
    return CommunityPageResult(
      data: _p1Parser.parseNotices(page),
      total: _pageTotal(page),
    );
  }

  /// Loads the reply excerpts referenced by a page of notices.
  ///
  /// Notices for the same topic share one request. Unsupported notice types,
  /// deleted replies without visible content, and transient failures are
  /// omitted so the notification list itself remains usable.
  Future<Map<int, String>> loadNoticeContents(
    Iterable<BangumiNotice> notices, {
    bool refresh = false,
  }) async {
    final batches = <String, _NoticeTopicBatch>{};
    for (final notice in notices) {
      final topic = notice.nativeTopic;
      if (topic == null || !notice.canLoadReplyContent) continue;
      final key = '${topic.kind.name}:${notice.mainId}';
      final batch = batches.putIfAbsent(
        key,
        () => _NoticeTopicBatch(topic: topic, notices: []),
      );
      batch.notices.add(notice);
    }

    final contents = <int, String>{};
    final pending = batches.values.toList();
    const concurrency = 4;
    for (var index = 0; index < pending.length; index += concurrency) {
      final end = (index + concurrency).clamp(0, pending.length);
      await Future.wait(
        pending.sublist(index, end).map((batch) async {
          try {
            final detail = await loadTopic(batch.topic, refresh: refresh);
            final postsById = <int, CommunityPost>{};
            for (final post in detail.posts) {
              final id = parseReplyId(post.id);
              if (id != null) postsById[id] = post;
            }
            for (final notice in batch.notices) {
              final post = postsById[notice.relatedId];
              if (post == null) continue;
              final body = post.body.trim();
              if (body.isNotEmpty) {
                contents[notice.id] = body;
              } else if (post.images.isNotEmpty) {
                contents[notice.id] = '（图片回复）';
              }
            }
          } catch (_) {
            // A detail failure must not hide or fail the parent notice list.
          }
        }),
      );
    }
    return contents;
  }

  /// Mark notices read. Empty [ids] clears all unread.
  Future<void> clearNotices({List<int> ids = const []}) async {
    _requireAuthentication();
    await _postJson('/clear-notify', data: {if (ids.isNotEmpty) 'id': ids});
    _jsonCache.removeWhere((key, _) => key.contains('/notify'));
  }

  Future<void> addFriend(String username) async {
    _requireAuthentication();
    final value = username.trim();
    if (value.isEmpty) throw Exception('用户名无效');
    final encoded = Uri.encodeComponent(value);
    await _putJson('/friends/$encoded', data: const {});
    _friendsCache.clear();
    _jsonCache.removeWhere(
      (key, _) => key.contains('/users/$encoded') || key.contains('/notify'),
    );
  }

  /// Accepts exactly the user carried by a P1 friend-request notice.
  Future<void> acceptFriendRequest(BangumiNotice notice) async {
    final sender = notice.sender;
    if (!notice.isFriendRequest || sender == null) {
      throw const FormatException('这不是可接受的好友申请');
    }
    await addFriend(sender.username);
  }

  Future<void> removeFriend(String username) async {
    _requireAuthentication();
    final value = username.trim();
    if (value.isEmpty) throw Exception('用户名无效');
    final encoded = Uri.encodeComponent(value);
    await _deleteJson('/friends/$encoded');
    _friendsCache.clear();
    _jsonCache.removeWhere((key, _) => key.contains('/users/$encoded'));
  }

  /// Returns whether [username] is already a friend.
  ///
  /// Uses `GET /p1/users/{username}` (`isFriend`) so it matches the same
  /// username lookup as [addFriend], instead of walking a possibly nested
  /// friends list.
  Future<bool> isFriend(String username) async {
    _requireAuthentication();
    final value = username.trim();
    if (value.isEmpty) return false;
    final me = _currentUsername;
    if (me != null && value.toLowerCase() == me.toLowerCase()) return false;
    final json = await _getJson('/users/${Uri.encodeComponent(value)}');
    return json['isFriend'] == true;
  }

  Future<void> _postJson(
    String path, {
    Map<String, dynamic> data = const {},
    bool retriedAuth = false,
  }) async {
    try {
      await _p1Dio.post<Object?>(
        '/p1$path',
        data: data,
        options: Options(
          contentType: Headers.jsonContentType,
          headers: const {'Accept': 'application/json'},
          validateStatus: (status) =>
              status != null && status >= 200 && status < 300,
        ),
      );
    } on DioException catch (error) {
      if (!retriedAuth &&
          _isRefreshableAuthFailure(error) &&
          onUnauthorizedRefresh != null &&
          await onUnauthorizedRefresh!()) {
        await _postJson(path, data: data, retriedAuth: true);
        return;
      }
      final privateGroup = _privateGroupName(error.response?.data);
      if (privateGroup != null) {
        throw PrivateGroupMembershipException(privateGroup);
      }
      throw Exception(_postErrorMessage(error));
    }
  }

  /// Extracts the group name from a NOT_JOIN_PRIVATE_GROUP_ERROR response,
  /// or null for any other error.
  static String? _privateGroupName(Object? data) {
    if (data is! Map || data['code'] != 'NOT_JOIN_PRIVATE_GROUP_ERROR') {
      return null;
    }
    final message = data['message']?.toString() ?? '';
    return RegExp(r"'([^']+)'").firstMatch(message)?.group(1) ?? '';
  }

  Future<void> _putJson(
    String path, {
    Map<String, dynamic> data = const {},
    bool retriedAuth = false,
  }) async {
    try {
      await _p1Dio.put<Object?>(
        '/p1$path',
        data: data,
        options: Options(
          contentType: Headers.jsonContentType,
          headers: const {'Accept': 'application/json'},
          validateStatus: (status) =>
              status != null && status >= 200 && status < 300,
        ),
      );
    } on DioException catch (error) {
      if (!retriedAuth &&
          _isRefreshableAuthFailure(error) &&
          onUnauthorizedRefresh != null &&
          await onUnauthorizedRefresh!()) {
        await _putJson(path, data: data, retriedAuth: true);
        return;
      }
      throw Exception(_postErrorMessage(error));
    }
  }

  Future<void> _deleteJson(String path, {bool retriedAuth = false}) async {
    try {
      await _p1Dio.delete<Object?>(
        '/p1$path',
        options: Options(
          headers: const {'Accept': 'application/json'},
          validateStatus: (status) =>
              status != null && status >= 200 && status < 300,
        ),
      );
    } on DioException catch (error) {
      if (!retriedAuth &&
          _isRefreshableAuthFailure(error) &&
          onUnauthorizedRefresh != null &&
          await onUnauthorizedRefresh!()) {
        await _deleteJson(path, retriedAuth: true);
        return;
      }
      throw Exception(_postErrorMessage(error));
    }
  }

  /// Only credential 401s justify an OAuth refresh + retry. Domain 401s such
  /// as CAPTCHA_ERROR or NOT_JOIN_PRIVATE_GROUP_ERROR must not be retried:
  /// the one-shot Turnstile token is already consumed by then, so a blind
  /// retry fails with a bogus captcha error that masks the real cause.
  bool _isRefreshableAuthFailure(DioException error) {
    if (error.response?.statusCode != 401) return false;
    final data = error.response?.data;
    if (data is! Map) return true;
    final code = data['code']?.toString();
    return code == null ||
        code == 'NEED_LOGIN' ||
        code == 'AUTHORIZATION_INVALID';
  }

  String _postErrorMessage(DioException error) {
    final status = error.response?.statusCode;
    final response = error.response?.data;
    if (response is Map) {
      final detail =
          response['message'] ??
          response['error'] ??
          response['description'] ??
          response['title'];
      if (detail != null && detail.toString().trim().isNotEmpty) {
        final text = detail.toString().trim();
        // Turnstile failures are otherwise opaque.
        if (text.toLowerCase().contains('turnstile') ||
            text.toLowerCase().contains('captcha')) {
          // Debug builds surface the raw server response so token-rejection
          // reports can distinguish expired/duplicate/malformed failures.
          if (kDebugMode) {
            return '人机验证失败或已过期，请重新点击发送并完成验证'
                '（HTTP $status: ${jsonEncode(response)}）';
          }
          return '人机验证失败或已过期，请重新点击发送并完成验证';
        }
        return text;
      }
    }
    if (response is String && response.trim().isNotEmpty) {
      return response.trim();
    }
    return _errorMessage(status);
  }

  bool _shouldRetry(DioException error, int attempt) {
    if (attempt >= 2) return false;
    final status = error.response?.statusCode;
    return status == null ||
        status == 429 ||
        status >= 500 ||
        error.type == DioExceptionType.unknown;
  }

  String _errorMessage(int? status) => switch (status) {
    401 => '社区授权已过期，请重新登录',
    403 => '当前账号没有执行此操作的权限',
    404 => 'Bangumi 社区内容不存在或不可见',
    429 => '请求过于频繁，请稍后再试',
    null => '无法连接 Bangumi 社区',
    _ => 'Bangumi 社区请求失败（$status）',
  };

  void _requireAuthentication() {
    if (!isAuthenticated) throw Exception('请先登录 Bangumi');
  }

  String _requireTurnstileToken(String token) {
    final value = token.trim();
    if (value.isEmpty) {
      throw const FormatException('人机验证未完成，请重新点击发送');
    }
    return value;
  }

  String _requireCurrentUsername() {
    final username = _currentUsername;
    if (username == null) throw Exception('无法识别当前登录用户');
    return username;
  }

  Map<String, dynamic>? _map(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : null;

  Map<String, String>? _stringQueryParameters(Map<String, dynamic>? query) =>
      query?.map((key, value) => MapEntry(key, value.toString()));

  /// Bounds the in-memory caches: purge expired entries and cap total size
  /// (Dart maps keep insertion order, so the oldest entries go first).
  static const int _cacheMaxEntries = 400;

  static void _storeIn<T>(
    Map<String, T> cache,
    String key,
    T entry,
    DateTime Function(T value) createdAtOf,
    Duration ttl,
  ) {
    cache[key] = entry;
    final cutoff = DateTime.now().subtract(ttl);
    cache.removeWhere((_, value) => createdAtOf(value).isBefore(cutoff));
    if (cache.length > _cacheMaxEntries) {
      final excess = cache.length - _cacheMaxEntries;
      for (final old in cache.keys.take(excess).toList()) {
        cache.remove(old);
      }
    }
  }
}

class _CachedHtml {
  const _CachedHtml(this.html, this.createdAt);

  final String html;
  final DateTime createdAt;
}

class _NoticeTopicBatch {
  _NoticeTopicBatch({required this.topic, required this.notices});

  final CommunityTopic topic;
  final List<BangumiNotice> notices;
}

class _CachedJson {
  const _CachedJson(this.json, this.createdAt);

  final Map<String, dynamic> json;
  final DateTime createdAt;
}

class _CachedFriends {
  const _CachedFriends(this.page, this.createdAt);

  final CommunityPageResult<BangumiUser> page;
  final DateTime createdAt;
}
