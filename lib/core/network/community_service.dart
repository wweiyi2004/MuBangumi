import 'package:dio/dio.dart';

import '../../core/storage/community_cache.dart';
import '../../models/bangumi_models.dart';
import '../../models/community_models.dart';
import 'community_html_parser.dart';
import 'community_p1_parser.dart';

class CommunityService {
  CommunityService._()
    : _htmlDio = Dio(
        BaseOptions(
          baseUrl: 'https://bgm.tv',
          connectTimeout: const Duration(seconds: 12),
          receiveTimeout: const Duration(seconds: 20),
          responseType: ResponseType.plain,
          headers: const {
            'User-Agent': 'MuBangumi/0.4.0 (Flutter; personal Bangumi client)',
            'Accept': 'text/html,application/xhtml+xml',
          },
        ),
      ),
      _p1Dio = Dio(
        BaseOptions(
          baseUrl: 'https://next.bgm.tv',
          connectTimeout: const Duration(seconds: 12),
          receiveTimeout: const Duration(seconds: 20),
          responseType: ResponseType.json,
          headers: const {
            'User-Agent': 'MuBangumi/0.4.0 (Flutter; personal Bangumi client)',
            'Accept': 'application/json',
          },
        ),
      );

  static final shared = CommunityService._();

  final Dio _htmlDio;
  final Dio _p1Dio;
  final CommunityHtmlParser _htmlParser = CommunityHtmlParser();
  final CommunityP1Parser _p1Parser = CommunityP1Parser();
  final CommunityCache _persistentCache = CommunityCache.shared;
  final Map<String, _CachedHtml> _htmlCache = {};
  final Map<String, _CachedJson> _jsonCache = {};
  final Map<String, _CachedFriends> _friendsCache = {};
  String? _currentUsername;

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

  void setCurrentUsername(String? username) {
    final value = username?.trim() ?? '';
    _currentUsername = value.isEmpty ? null : value;
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
              .map((item) => BangumiUser.fromJson(Map<String, dynamic>.from(item)))
              .where((user) => user.username.isNotEmpty)
              .toList()
        : const <BangumiUser>[];
    final total = (json['total'] as num?)?.toInt() ?? users.length;
    final page = CommunityPageResult(data: users, total: total);
    _friendsCache[cacheKey] = _CachedFriends(page, DateTime.now());
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
    return _p1Parser.parseTimeline(data);
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
    return _p1Parser.parseTimeline(data);
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
    await _postJson(
      '/groups/${Uri.encodeComponent(slug)}/topics',
      data: {
        'title': title,
        'content': content,
        'turnstileToken': turnstileToken,
      },
    );
  }

  Future<void> replyToTopic({
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
    if (turnstileToken.trim().isEmpty) {
      throw const FormatException('人机验证未完成，请重试');
    }
    // API: replyTo=0 means top-level reply; otherwise nest under that reply id.
    await _postJson(
      '/$area/-/topics/$id/replies',
      data: {
        'content': trimmed,
        'turnstileToken': turnstileToken.trim(),
        'replyTo': replyTo ?? 0,
      },
    );
    _jsonCache.removeWhere(
      (key, _) => key.contains('/topics/$id') || key.contains('topic'),
    );
  }

  Future<void> postTimeline({
    required String content,
    required String turnstileToken,
  }) async {
    _requireAuthentication();
    await _postJson(
      '/timeline',
      data: {'content': content, 'turnstileToken': turnstileToken},
    );
  }

  Future<void> replyToTimeline({
    required int timelineId,
    required String content,
    required String turnstileToken,
    int? replyTo,
  }) async {
    _requireAuthentication();
    await _postJson(
      '/timeline/$timelineId/replies',
      data: {
        'content': content,
        'turnstileToken': turnstileToken,
        'replyTo': ?replyTo,
      },
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
      _htmlCache[key] = _CachedHtml(html, DateTime.now());
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
        _jsonCache[key] = _CachedJson(json, DateTime.now());
        return json;
      } on DioException catch (error) {
        lastError = error;
        final status = error.response?.statusCode;
        if (!retriedAuth &&
            status == 401 &&
            onUnauthorizedRefresh != null &&
            await onUnauthorizedRefresh!()) {
          return _getJson(
            path,
            query: query,
            refresh: true,
            retriedAuth: true,
          );
        }
        final shouldRetry =
            status == null ||
            status >= 500 ||
            error.type == DioExceptionType.unknown;
        if (!shouldRetry || attempt == 2) break;
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
        _jsonCache[key] = _CachedJson({'data': data}, DateTime.now());
        return data;
      } on DioException catch (error) {
        lastError = error;
        final status = error.response?.statusCode;
        if (!retriedAuth &&
            status == 401 &&
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
      final status = error.response?.statusCode;
      if (!retriedAuth &&
          status == 401 &&
          onUnauthorizedRefresh != null &&
          await onUnauthorizedRefresh!()) {
        await _postJson(path, data: data, retriedAuth: true);
        return;
      }
      throw Exception(_postErrorMessage(error));
    }
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
          return '人机验证失败或已过期，请关闭后重新发送并完成验证';
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

  String _requireCurrentUsername() {
    final username = _currentUsername;
    if (username == null) throw Exception('无法识别当前登录用户');
    return username;
  }

  Map<String, dynamic>? _map(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : null;

  Map<String, String>? _stringQueryParameters(Map<String, dynamic>? query) =>
      query?.map((key, value) => MapEntry(key, value.toString()));
}

class _CachedHtml {
  const _CachedHtml(this.html, this.createdAt);

  final String html;
  final DateTime createdAt;
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
