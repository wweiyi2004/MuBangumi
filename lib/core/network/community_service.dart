import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/storage/community_cache.dart';
import '../../models/bangumi_models.dart';
import '../../models/community_models.dart';
import '../../models/account_content_preferences.dart';
import '../auth/website_session.dart';
import '../auth/website_identity.dart';
import 'bangumi_smiles.dart';
import 'async_cache.dart';
import 'bangumi_user_agent.dart';
import 'community_html_parser.dart';
import 'community_p1_parser.dart';
import 'pm_html_parser.dart';

/// Strong signals that a classic website page is actually the login form.
bool looksLikeWebsiteLoginPage(String source) {
  return PmHtmlParser().looksLikeLoginPage(source);
}

/// The P1 server rejected a private-group post/reply claiming the user is not
/// a member. As of 2026-08 the server checks membership with the user/group
/// ids swapped, so even the group owner gets this error.
class PrivateGroupMembershipException implements Exception {
  const PrivateGroupMembershipException(this.groupName);

  final String groupName;

  @override
  String toString() => '「$groupName」是私密小组，需要先加入小组后再发帖或回复';
}

class CommunityService {
  /// Hard stop so two large public friend lists cannot walk unbounded P1 pages.
  static const maxFriendPages = 100;
  CommunityService({
    Dio? htmlDio,
    Dio? p1Dio,
    WebsiteSessionStore? sessionStore,
    CommunityCache? cache,
  }) : _sessionStore = sessionStore ?? WebsiteSessionStore(),
       _persistentCache = cache ?? CommunityCache.shared,
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

  Future<WebsiteSessionSnapshot> Function()? websiteSessionGuard;
  void Function(WebsiteAccessStatus status, String authenticationKey)?
  onWebsiteSessionFailure;

  void _websiteFailed(WebsiteAccessStatus status, String cookieHeader) {
    final snapshot = WebsiteSessionSnapshot(
      cookies: WebsiteSessionSnapshot.parseDocumentCookie(cookieHeader),
      syncedAt: DateTime.now(),
    );
    onWebsiteSessionFailure?.call(status, snapshot.authenticationKey);
  }

  @visibleForTesting
  CommunityService.test({
    Dio? htmlDio,
    Dio? p1Dio,
    WebsiteSessionStore? sessionStore,
    CommunityCache? cache,
  }) : this(
         htmlDio: htmlDio,
         p1Dio: p1Dio,
         sessionStore: sessionStore,
         cache: cache,
       );

  void dispose() {
    _identityRevision++;
    _htmlDio.close(force: true);
    _p1Dio.close(force: true);
    _htmlCache.clear();
    _jsonCache.clear();
    _friendsCache.clear();
    _accountChanges.dispose();
    _contentPreferencesChanges.dispose();
  }

  final Dio _htmlDio;
  final Dio _p1Dio;
  final WebsiteSessionStore _sessionStore;
  final CommunityHtmlParser _htmlParser = CommunityHtmlParser();
  final CommunityP1Parser _p1Parser = CommunityP1Parser();
  final CommunityCache _persistentCache;
  final _cacheOwners = <String>{};
  String _cachePrefix(String owner) =>
      'community-v2:${Uri.encodeComponent(owner.toLowerCase())}:';
  String _snapshotKey(String key) =>
      '${_cachePrefix(_currentUsername ?? 'public')}$key';
  Future<Map<String, dynamic>?> _readSnapshot(String key) async {
    if (isAuthenticated && _currentUsername == null) return null;
    final revision = _identityRevision;
    final value = await _persistentCache.readJson(_snapshotKey(key));
    return revision == _identityRevision ? value : null;
  }

  Future<void> _writeSnapshot(
    String key,
    Map<String, dynamic> value, {
    required int identity,
    bool accountScoped = false,
  }) async {
    if (identity != _identityRevision) return;
    if (isAuthenticated && _currentUsername == null) return;
    final scoped = _snapshotKey(key);
    await _persistentCache.writeJson(
      scoped,
      value,
      accountScoped: accountScoped,
    );
    if (identity != _identityRevision) await _persistentCache.remove(scoped);
  }

  final _htmlCache = AsyncCache<String>(
    maxAge: const Duration(minutes: 2),
    maxEntries: 400,
  );
  final _jsonCache = AsyncCache<Object>(
    maxAge: const Duration(minutes: 2),
    maxEntries: 400,
  );
  final Map<String, _CachedFriends> _friendsCache = {};
  String? _currentUsername;
  String _currentNickname = '';
  String _currentAvatarUrl = '';
  final _accountChanges = ValueNotifier<String?>(null);
  int _identityRevision = 0;
  int get identityRevision => _identityRevision;

  ValueListenable<String?> get accountChanges => _accountChanges;
  final _contentPreferencesChanges = ValueNotifier<int>(0);
  int _contentRevision = 0;
  ValueListenable<int> get contentPreferencesChanges =>
      _contentPreferencesChanges;

  Future<AccountContentPreferences> loadContentPreferences() async {
    _requireAuthentication();
    final identity = _identityRevision;
    // Account settings must never be inferred from a stale content cache.
    final json = await _fetchJson('/privacy');
    if (identity != _identityRevision || !isAuthenticated) {
      throw const FormatException('登录账号已变化，请重新读取设置');
    }
    return AccountContentPreferences.fromJson(json);
  }

  Future<AccountContentPreferences> setNsfwPreference(bool enabled) async {
    final identity = _identityRevision;
    final response = await _nativeWrite(
      'PATCH',
      '/privacy',
      data: {
        'preferences': {'showNsfwSubject': enabled},
      },
      accountPreferences: true,
    );
    if (identity != _identityRevision || !isAuthenticated) {
      throw const FormatException('登录账号已变化，请重新读取设置');
    }
    await refreshContentAfterPreferenceChange();
    if (identity != _identityRevision || !isAuthenticated) {
      throw const FormatException('登录账号已变化，请重新读取设置');
    }
    if (response is! Map) {
      throw const FormatException('设置提交后未收到完整结果，请重新读取');
    }
    return AccountContentPreferences.fromJson(
      Map<String, dynamic>.from(response),
    );
  }

  /// Also used after the user saves through the official website fallback.
  Future<void> refreshContentAfterPreferenceChange() async {
    _requireAuthentication();
    final identity = _identityRevision;
    _contentRevision++;
    _jsonCache.clear();
    _htmlCache.clear();
    await _removeTimelineSnapshots();
    if (identity == _identityRevision && isAuthenticated) {
      _contentPreferencesChanges.value++;
    }
  }

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
    if ((_currentUsername ?? '') != value) {
      _identityRevision++;
      _jsonCache.clear();
      _htmlCache.clear();
      _friendsCache.clear();
    }
    _currentUsername = value.isEmpty ? null : value;
    if (value.isNotEmpty) _cacheOwners.add(value);
    _currentNickname = value.isEmpty ? '' : nickname.trim();
    _currentAvatarUrl = value.isEmpty ? '' : avatarUrl.trim();
    _accountChanges.value = _currentUsername;
  }

  Future<void> clearAccountCache() async {
    _jsonCache.clear();
    _htmlCache.clear();
    for (final owner in _cacheOwners) {
      await _persistentCache.removePrefix(_cachePrefix(owner));
    }
    _cacheOwners.clear();
    _friendsCache.clear();
  }

  String _monoArea(CommunityTimelineTargetKind kind) => switch (kind) {
    CommunityTimelineTargetKind.character => 'characters',
    CommunityTimelineTargetKind.person => 'persons',
    _ => throw const FormatException('不是人物或角色'),
  };

  Future<CommunityMonoCollection> loadMonoCollection(
    CommunityTimelineTargetKind kind,
    int id, {
    bool refresh = false,
  }) async {
    _requireAuthentication();
    if (id <= 0) throw const FormatException('编号无效');
    final json = await _getJson('/${_monoArea(kind)}/$id', refresh: refresh);
    return CommunityMonoCollection(
      collected: (json['collectedAt'] as num? ?? 0) > 0,
      count: (json['collects'] as num? ?? 0).toInt(),
    );
  }

  Future<void> setMonoCollection(
    CommunityTimelineTargetKind kind,
    int id, {
    required bool collected,
  }) async {
    if (id <= 0) throw const FormatException('编号无效');
    await _nativeWrite(
      collected ? 'PUT' : 'DELETE',
      '/collections/${_monoArea(kind)}/$id',
    );
    _jsonCache.clear();
    await _removeTimelineSnapshots();
  }

  Future<void> updateTimelineReaction(
    CommunityTimelineItem item,
    int? value,
  ) async {
    if (!item.isStatus || item.id <= 0) throw const FormatException('此动态不支持贴贴');
    if (value != null && !BangumiReactions.accepts(value)) {
      throw const FormatException('不支持这个贴贴表情');
    }
    await _nativeWrite(
      value == null ? 'DELETE' : 'PUT',
      '/timeline/${item.id}/like',
      data: value == null ? const {} : {'value': value},
    );
    _jsonCache.clear();
    await _removeTimelineSnapshots();
  }

  bool canDeleteTimeline(CommunityTimelineItem item) =>
      isAuthenticated &&
      _currentUsername != null &&
      item.user.username.toLowerCase() == _currentUsername!.toLowerCase();

  Future<void> deleteTimeline(CommunityTimelineItem item) async {
    if (item.id <= 0 || !canDeleteTimeline(item)) {
      throw const FormatException('只能删除自己的动态');
    }
    await _nativeWrite('DELETE', '/timeline/${item.id}');
    _jsonCache.clear();
    await _removeTimelineSnapshots();
  }

  Future<void> _removeTimelineSnapshots() async {
    for (final mode in CommunityTimelineMode.values) {
      await _persistentCache.remove(_snapshotKey('timeline:${mode.name}'));
    }
  }

  Future<CommunityPageResult<CommunityBlog>> loadUserBlogs(
    String username, {
    int offset = 0,
    int limit = 20,
    bool refresh = false,
  }) async {
    final name = username.trim();
    if (name.isEmpty) throw const FormatException('用户名不能为空');
    final page = await _getJson(
      '/users/${Uri.encodeComponent(name)}/blogs',
      query: {'offset': offset, 'limit': limit.clamp(1, 100)},
      refresh: refresh,
    );
    final rows = page['data'] as List? ?? const [];
    return CommunityPageResult(
      data: rows
          .whereType<Map>()
          .map(
            (row) => _p1Parser.parseBlog(
              Map<String, dynamic>.from(row),
              fallbackUsername: name,
            ),
          )
          .toList(),
      total: _pageTotal(page),
      rawCount: rows.length,
    );
  }

  Future<CommunityBlog> loadBlog(int id, {bool refresh = false}) async {
    if (id <= 0) throw const FormatException('日志编号无效');
    return _p1Parser.parseBlog(await _getJson('/blogs/$id', refresh: refresh));
  }

  bool canEditBlog(CommunityBlog blog) =>
      isAuthenticated &&
      _currentUsername != null &&
      blog.user.username.toLowerCase() == _currentUsername!.toLowerCase();

  Future<void> saveBlog({
    CommunityBlog? original,
    required String title,
    required String content,
    required List<String> tags,
    required bool isPublic,
    String? turnstileToken,
  }) async {
    if (title.trim().isEmpty || title.trim().runes.length > 80) {
      throw const FormatException('标题需为 1 至 80 个字');
    }
    if (content.trim().isEmpty || content.trim().runes.length > 100000) {
      throw const FormatException('正文需为 1 至 100000 个字');
    }
    if (original != null && !canEditBlog(original)) {
      throw const FormatException('只能编辑自己的日志');
    }
    final cleanedTags = tags
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toSet()
        .toList();
    if (cleanedTags.length > 10) throw const FormatException('最多填写 10 个标签');
    final data = <String, dynamic>{
      'title': title.trim(),
      'content': content.trim(),
      'tags': cleanedTags,
      'public': isPublic,
    };
    if (original == null) {
      data['turnstileToken'] = _requireTurnstileToken(turnstileToken ?? '');
    }
    // Omitting subjectIDs preserves existing associations on PATCH.
    await _nativeWrite(
      original == null ? 'POST' : 'PATCH',
      original == null ? '/blogs' : '/blogs/${original.id}',
      data: data,
    );
    _jsonCache.clear();
    await _removeTimelineSnapshots();
  }

  /// Retry only a rejected credential, never a timeout or an uncertain write.
  Future<Object?> _nativeWrite(
    String method,
    String path, {
    Map<String, dynamic> data = const {},
    bool accountPreferences = false,
  }) async {
    _requireAuthentication();
    final identity = _identityRevision;
    for (var attempt = 0; attempt < 2; attempt++) {
      if (identity != _identityRevision || !isAuthenticated) {
        throw const FormatException('登录账号已变化，请重新操作');
      }
      try {
        final response = await _p1Dio.request<Object?>(
          '/p1$path',
          data: method == 'DELETE' ? null : data,
          options: Options(
            method: method,
            contentType: Headers.jsonContentType,
            validateStatus: (status) =>
                status != null && status >= 200 && status < 300,
          ),
        );
        return response.data;
      } on DioException catch (error) {
        if (attempt == 0 &&
            identity == _identityRevision &&
            _isRefreshableAuthFailure(
              error,
              oneShot: data.containsKey('turnstileToken'),
            ) &&
            onUnauthorizedRefresh != null &&
            await onUnauthorizedRefresh!()) {
          continue;
        }
        if (method == 'POST' && error.response == null) {
          throw Exception('提交结果尚未确认，请先查看日志列表，确认没有发布后再重试');
        }
        if (accountPreferences) {
          throw AccountContentPreferencesException(error.response?.statusCode);
        }
        throw Exception(_postErrorMessage(error));
      }
    }
    throw const FormatException('未能完成请求，请重新操作');
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
          DateTime.now().difference(cached.createdAt) < _friendsCacheTtl) {
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
      _friendsCacheTtl,
    );
    return page;
  }

  /// Loads every public friend page for [username].
  Future<List<BangumiUser>> loadAllFriends(
    String username, {
    bool refresh = false,
    int pageSize = 30,
  }) async {
    final friends = <BangumiUser>[];
    final known = <String>{};
    var offset = 0;
    var total = 0;
    var pages = 0;
    do {
      final page = await loadFriends(
        username,
        limit: pageSize,
        offset: offset,
        refresh: refresh,
      );
      for (final friend in page.data) {
        final key = friend.username.trim().toLowerCase();
        if (key.isNotEmpty && known.add(key)) friends.add(friend);
      }
      total = page.total;
      pages++;
      if (page.data.isEmpty || pages >= maxFriendPages) break;
      offset += page.data.length;
    } while (offset < total);
    return friends;
  }

  Future<CommunityPageResult<CommunityTopic>?> readCachedTopics(
    RakuenMode mode,
  ) async {
    final json = await _readSnapshot(_topicCacheKey(mode));
    if (json == null) return null;
    if (mode.aggregateType != null) return _aggregatePage(json, 0, 20);
    return _parseTopicPage(mode, json);
  }

  Future<CommunityPageResult<CommunityTopic>> loadTopicPage(
    RakuenMode mode, {
    int limit = 20,
    int offset = 0,
    bool refresh = false,
  }) async {
    final identity = _identityRevision;
    if (mode.aggregateType case final type?) {
      // This API has a limit but no offset. Keep a fixed recent window and
      // paginate that snapshot locally rather than repeatedly fetching page 1.
      final json = await _getJson(
        '/rakuen/topics',
        query: {'type': type, 'limit': 200},
        refresh: refresh,
      );
      if (offset == 0) {
        await _writeSnapshot(
          _topicCacheKey(mode),
          json,
          identity: identity,
          accountScoped: true,
        );
      }
      return _aggregatePage(json, offset, limit);
    }
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
      await _writeSnapshot(
        _topicCacheKey(mode),
        json,
        identity: identity,
        accountScoped: mode.requiresLogin,
      );
    }
    return _parseTopicPage(mode, json);
  }

  CommunityPageResult<CommunityTopic> _aggregatePage(
    Map<String, dynamic> json,
    int offset,
    int limit,
  ) {
    final topics = _p1Parser.parseRakuenTopics(json);
    return CommunityPageResult(
      data: topics.skip(offset).take(limit).toList(),
      total: topics.length,
    );
  }

  Future<CommunityPageResult<CommunityGroup>?> readCachedGroups(
    CommunityGroupMode mode,
    CommunityGroupSort sort,
  ) async {
    final json = await _readSnapshot(_groupCacheKey(mode, sort));
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
    final identity = _identityRevision;
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
      await _writeSnapshot(
        _groupCacheKey(mode, sort),
        json,
        identity: identity,
        accountScoped: mode.requiresLogin,
      );
    }
    return CommunityPageResult(
      data: _p1Parser.parseGroups(json),
      total: _pageTotal(json),
    );
  }

  Future<CommunityGroupDetail?> readCachedGroupDetail(String slug) async {
    final bundle = await _readSnapshot('group:$slug');
    if (bundle == null) return null;
    return _parseGroupBundle(bundle);
  }

  Future<CommunityGroupDetail> loadGroupPreview(String slug) async =>
      _p1Parser.parseGroupDetail(
        await _getJson('/groups/${Uri.encodeComponent(slug)}', refresh: true),
      );

  Future<CommunityPageResult<CommunityTopic>> loadGroupTopics(
    String slug, {
    int offset = 0,
    int limit = 20,
    bool refresh = false,
  }) async {
    final page = await _getJson(
      '/groups/${Uri.encodeComponent(slug)}/topics',
      query: {'limit': limit.clamp(1, 100), 'offset': offset},
      refresh: refresh,
    );
    return CommunityPageResult(
      data: _p1Parser.parseGroupTopics(page),
      total: _pageTotal(page),
      rawCount: (page['data'] as List?)?.length ?? 0,
    );
  }

  Future<CommunityPageResult<CommunityUser>> loadGroupMembers(
    String slug, {
    int offset = 0,
    int limit = 20,
    int? role,
    bool refresh = false,
  }) async {
    final page = await _getJson(
      '/groups/${Uri.encodeComponent(slug)}/members',
      query: {'limit': limit.clamp(1, 100), 'offset': offset, 'role': ?role},
      refresh: refresh,
    );
    return CommunityPageResult(
      data: _p1Parser.parseMembers(page),
      total: _pageTotal(page),
      rawCount: (page['data'] as List?)?.length ?? 0,
    );
  }

  Future<void> createSubjectTopic({
    required int subjectId,
    required String title,
    required String content,
    required String turnstileToken,
  }) async {
    _requireAuthentication();
    if (subjectId <= 0 || title.trim().isEmpty || content.trim().isEmpty) {
      throw const FormatException('请填写标题和正文');
    }
    await _postJson(
      '/subjects/$subjectId/topics',
      data: {
        'title': title.trim(),
        'content': content.trim(),
        'turnstileToken': _requireTurnstileToken(turnstileToken),
      },
    );
    _jsonCache.removeWhere((key) => key.contains('/topics'));
  }

  bool canManagePost(CommunityTopic topic, CommunityPost post) {
    final username = _currentUsername;
    final author = Uri.tryParse(post.userUrl)?.pathSegments;
    return isAuthenticated &&
        username != null &&
        post.canEdit &&
        topic.kind.apiArea != null &&
        author != null &&
        author.length == 2 &&
        author.first == 'user' &&
        author.last.toLowerCase() == username.toLowerCase();
  }

  Future<void> editPost({
    required CommunityTopic topic,
    required CommunityPost post,
    required String content,
    String? title,
  }) async {
    _requireAuthentication();
    if (!canManagePost(topic, post)) throw const FormatException('只能编辑自己的内容');
    if (content.trim().isEmpty) throw const FormatException('正文不能为空');
    final area = topic.kind.apiArea!;
    if (post.isOriginal && topic.kind.isDiscussion) {
      final id = resolveTopicId(topic);
      if (id == null || title == null || title.trim().isEmpty) {
        throw const FormatException('请填写话题标题');
      }
      await _putJson(
        '/$area/-/topics/$id',
        data: {'title': title.trim(), 'content': content.trim()},
      );
    } else {
      final id = parseReplyId(post.id);
      if (id == null) throw const FormatException('无法识别回复编号');
      final resource = topic.kind.isDiscussion ? 'posts' : 'comments';
      await _putJson(
        '/$area/-/$resource/$id',
        data: {'content': content.trim()},
      );
    }
    _invalidateThread(topic);
  }

  Future<void> deletePost({
    required CommunityTopic topic,
    required CommunityPost post,
  }) async {
    _requireAuthentication();
    if (!canManagePost(topic, post)) throw const FormatException('只能删除自己的回复');
    // Deleting a topic's first post does not delete the topic itself.
    if (post.isOriginal) throw const FormatException('请在官网删除整个话题');
    final id = parseReplyId(post.id);
    if (id == null) throw const FormatException('无法识别回复编号');
    final resource = topic.kind.isDiscussion ? 'posts' : 'comments';
    await _deleteJson('/${topic.kind.apiArea}/-/$resource/$id');
    _invalidateThread(topic);
  }

  void _invalidateThread(CommunityTopic topic) {
    _jsonCache.clear();
    _htmlCache.removeWhere(
      (key) => key.contains(topic.webUrl) || key.contains('/topic/'),
    );
  }

  Future<CommunityGroupDetail> loadGroupDetail(
    String slug, {
    bool refresh = false,
  }) async {
    final identity = _identityRevision;
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
    await _writeSnapshot(
      'group:$slug',
      bundle,
      identity: identity,
      accountScoped: true,
    );
    return _parseGroupBundle(bundle);
  }

  Future<List<CommunityTimelineItem>?> readCachedTimeline(
    CommunityTimelineMode mode,
  ) async {
    final json = await _readSnapshot('timeline:${mode.name}');
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
    final identity = _identityRevision;
    final contentRevision = _contentRevision;
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
    if (identity != _identityRevision || contentRevision != _contentRevision) {
      throw const FormatException('账号或内容偏好已变化，请刷新动态');
    }
    if (until == null) {
      await _writeSnapshot(
        'timeline:${mode.name}',
        {'data': data},
        identity: identity,
        accountScoped: mode != CommunityTimelineMode.all,
      );
      if (identity != _identityRevision ||
          contentRevision != _contentRevision) {
        await _removeTimelineSnapshots();
        throw const FormatException('账号或内容偏好已变化，请刷新动态');
      }
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
    final identity = _identityRevision;
    final contentRevision = _contentRevision;
    final value = username.trim();
    if (value.isEmpty) return const [];
    final data = await _getJsonList(
      '/users/${Uri.encodeComponent(value)}/timeline',
      query: {'limit': limit.clamp(1, 30), 'until': ?until},
      refresh: refresh,
    );
    if (identity != _identityRevision || contentRevision != _contentRevision) {
      throw const FormatException('账号或内容偏好已变化，请刷新动态');
    }
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
    final identity = _identityRevision;
    final trimmedTitle = title.trim();
    final trimmedContent = content.trim();
    if (trimmedTitle.isEmpty) {
      throw const FormatException('标题不能为空');
    }
    if (trimmedContent.isEmpty) {
      throw const FormatException('正文不能为空');
    }
    final token = _requireTurnstileToken(turnstileToken);
    final encoded = Uri.encodeComponent(slug);
    try {
      await _postJson(
        '/groups/$encoded/topics',
        data: {
          'title': trimmedTitle,
          'content': trimmedContent,
          'turnstileToken': token,
        },
      );
    } on PrivateGroupMembershipException {
      if (identity != _identityRevision) {
        throw const FormatException('账号已变化，请重新发起讨论');
      }
      // Same P1 membership-id swap as replies: the official create-topic
      // endpoint rejects even the group owner. The classic website form
      // checks membership correctly.
      await _createGroupTopicViaWebsite(
        slug: slug,
        title: trimmedTitle,
        content: trimmedContent,
      );
    }
    _jsonCache.removeWhere(
      (key) => key.contains('/groups/$encoded') || key.contains('/topics'),
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
    if (!topic.kind.supportsReactions) {
      throw const FormatException('此类讨论暂不支持贴贴');
    }
    final area = topic.kind.apiArea!;
    final postId = parseReplyId(post.id);
    if (postId == null) throw const FormatException('无法识别回复编号');
    if (value != null && !BangumiReactions.accepts(value)) {
      throw const FormatException('不支持这个贴贴表情');
    }
    final resource = topic.kind.isDiscussion ? 'posts' : 'comments';
    final path = '/$area/-/$resource/$postId/like';
    if (value == null) {
      await _deleteJson(path);
    } else {
      await _putJson(path, data: {'value': value});
    }
    _invalidateThread(topic);
  }

  Future<void> _replyToTopicViaP1({
    required CommunityTopic topic,
    required String content,
    required String turnstileToken,
    int? replyTo,
  }) async {
    _requireAuthentication();
    final identity = _identityRevision;
    final area = topic.kind.apiArea;
    if (area == null) throw const FormatException('请在官网回复此类话题');
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
        topic.kind.isDiscussion
            ? '/$area/-/topics/$id/replies'
            : '/$area/$id/comments',
        data: {
          'content': trimmed,
          'turnstileToken': token,
          'replyTo': replyTo ?? 0,
        },
      );
    } on PrivateGroupMembershipException {
      if (identity != _identityRevision) {
        throw const FormatException('账号已变化，请重新回复');
      }
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
    _invalidateThread(topic);
  }

  /// Creates a group topic through the classic website form
  /// (`/group/{slug}/new_topic`) using the stored website session.
  Future<void> _createGroupTopicViaWebsite({
    required String slug,
    required String title,
    required String content,
  }) async {
    final identity = _identityRevision;
    final session = await _requireWebsiteSession();
    final cookie = session.cookieHeader;
    final path = '/group/${Uri.encodeComponent(slug)}/new_topic';
    final formhash = await _loadWebsiteFormhash(path, session);
    await _verifyWebsiteWriteContext(identity, session.authenticationKey);
    final response = await _htmlDio.post<String>(
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
        validateStatus: (status) => status != null && status < 500,
      ),
    );
    final status = response.statusCode ?? 0;
    final location = response.headers.value('location') ?? '';
    if (status >= 300 && status < 400 && location.contains('/group/topic/')) {
      return;
    }
    final body = response.data ?? '';
    _throwIfWebsiteChallenge(
      body,
      cookie,
      cfMitigated: response.headers.value('cf-mitigated'),
    );
    if (status >= 500 || status == 429) {
      throw FormatException('网站暂时无法响应（HTTP $status），请刷新确认发帖结果');
    }
    _throwIfWebsiteLoginPage(body, cookie);
    if (status == 401 || looksLikeWebsiteLoginPage(body)) {
      _websiteFailed(WebsiteAccessStatus.expired, cookie);
      throw const FormatException('网页版登录已过期，请重新登录网页版后再发帖');
    }
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      decoded = null;
    }
    if (decoded is Map) {
      if (decoded['id'] != null ||
          decoded.containsKey('topic') ||
          decoded['status'] == 'ok') {
        return;
      }
      final detail = decoded['error'] ?? decoded['message'];
      if (detail != null && detail.toString().trim().isNotEmpty) {
        throw FormatException('发帖失败：${detail.toString().trim()}');
      }
    }
    final notice = PmHtmlParser().parseSubmissionError(body);
    if (notice != null) throw FormatException('发帖失败：$notice');
    if (status >= 400) {
      throw FormatException('发帖失败（HTTP $status）');
    }
    throw const FormatException('发帖结果未知，请刷新小组页确认是否已发出');
  }

  /// Posts a group topic reply through the classic website form
  /// (`/group/topic/{id}/new_reply`) using the stored website session.
  Future<void> _replyToGroupTopicViaWebsite({
    required int topicId,
    required String content,
    int? replyTo,
  }) async {
    final identity = _identityRevision;
    final session = await _requireWebsiteSession();
    final cookie = session.cookieHeader;
    final topicPath = '/group/topic/$topicId';
    // The topic page carries the session-wide formhash the form needs; the
    // GET also proves the website session can actually see the group.
    final formhash = await _loadWebsiteFormhash(topicPath, session);
    await _verifyWebsiteWriteContext(identity, session.authenticationKey);
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
          ...session.requestHeaders,
          'Referer': 'https://bgm.tv$topicPath',
          'Origin': 'https://bgm.tv',
          'X-Requested-With': 'XMLHttpRequest',
        },
        validateStatus: (status) => status != null && status < 500,
      ),
    );
    final body = response.data ?? '';
    _throwIfWebsiteChallenge(
      body,
      cookie,
      cfMitigated: response.headers.value('cf-mitigated'),
    );
    if ((response.statusCode ?? 0) >= 500 || response.statusCode == 429) {
      throw FormatException('网站暂时无法响应（HTTP ${response.statusCode}），请刷新确认回复结果');
    }
    _throwIfWebsiteLoginPage(body, cookie);
    if (response.statusCode == 401 || looksLikeWebsiteLoginPage(body)) {
      _websiteFailed(WebsiteAccessStatus.expired, cookie);
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

  Future<String> _loadWebsiteFormhash(
    String path,
    WebsiteSessionSnapshot session,
  ) async {
    final cookie = session.cookieHeader;
    final html = await _fetchWebsiteHtml(path, session);
    _throwIfWebsiteLoginPage(html, cookie);
    final fromPage = _htmlParser.parseFormhash(html);
    if (fromPage != null) return fromPage;
    // Private-group / permission pages omit the reply form. The homepage
    // still carries the session formhash on the logout link when cookies
    // actually authenticated.
    if (path != '/') {
      final home = await _fetchWebsiteHtml('/', session);
      _throwIfWebsiteLoginPage(home, cookie);
      final fromHome = _htmlParser.parseFormhash(home);
      if (fromHome != null) return fromHome;
    }
    throw const FormatException('暂时无法获取网页操作参数，请刷新后重试');
  }

  Future<void> _verifyWebsiteWriteContext(
    int identity,
    String authenticationKey,
  ) async {
    if (identity != _identityRevision) {
      throw const FormatException('账号已变化，请重新操作');
    }
    final current = await _requireWebsiteSession();
    if (identity != _identityRevision ||
        current.authenticationKey != authenticationKey) {
      throw const FormatException('网页登录已变化，请刷新页面后再提交');
    }
  }

  Future<String> _fetchWebsiteHtml(
    String path,
    WebsiteSessionSnapshot session,
  ) async {
    final response = await _htmlDio.get<String>(
      path,
      options: Options(
        headers: {...session.requestHeaders, 'Referer': 'https://bgm.tv/'},
        validateStatus: (status) => status != null && status < 600,
      ),
    );
    _throwIfWebsiteChallenge(
      response.data ?? '',
      session.cookieHeader,
      cfMitigated: response.headers.value('cf-mitigated'),
    );
    if ((response.statusCode ?? 0) >= 500 || response.statusCode == 429) {
      throw FormatException('网站暂时无法响应（HTTP ${response.statusCode}），已保留登录');
    }
    if (response.statusCode == 401) {
      _websiteFailed(WebsiteAccessStatus.expired, session.cookieHeader);
      throw const FormatException('网页版登录已过期，请重新登录网页版后再试');
    }
    return response.data ?? '';
  }

  void _throwIfWebsiteChallenge(
    String html,
    String cookie, {
    String? cfMitigated,
  }) {
    if (WebsiteIdentityProbe.isChallenge(html, cfMitigated: cfMitigated)) {
      _websiteFailed(WebsiteAccessStatus.challenge, cookie);
      throw const WebsiteAccessException(
        WebsiteAccessStatus.challenge,
        'Bangumi 需要网页验证，请补充账号验证后继续',
      );
    }
  }

  void _throwIfWebsiteLoginPage(String html, String cookie) {
    _throwIfWebsiteChallenge(html, cookie);
    if (looksLikeWebsiteLoginPage(html)) {
      _websiteFailed(WebsiteAccessStatus.expired, cookie);
      throw const FormatException('网页版登录已过期，请重新登录网页版后再试');
    }
  }

  Future<WebsiteSessionSnapshot> _requireWebsiteSession() async {
    if (websiteSessionGuard case final guard?) {
      return await guard();
    }
    final snapshot = await _sessionStore.read();
    final header = snapshot?.cookieHeader.trim() ?? '';
    if (snapshot == null || header.isEmpty || !snapshot.hasSessionCookies) {
      throw const FormatException(
        '该小组为私密小组，需要走网站通道发帖或回复：请先在「我的 → 设置 → Bangumi 账号」中完成登录后重试',
      );
    }
    return snapshot;
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
    if (!topic.kind.isDiscussion && topic.kind.apiArea != null) {
      final id = resolveTopicId(topic);
      if (id == null) throw const FormatException('无法识别讨论编号');
      final comments = await _getJsonList(
        '/${topic.kind.apiArea}/$id/comments',
        refresh: refresh,
      );
      final thread = _p1Parser.parseCommentThread(comments, topic);
      if (topic.kind == CommunityTopicKind.blog) {
        final blog = await _getJson('/blogs/$id', refresh: refresh);
        final user = blog['user'] is Map ? blog['user'] as Map : const {};
        final username = user['username']?.toString() ?? '';
        return CommunityTopicDetail(
          title: blog['title']?.toString() ?? topic.title,
          posts: [
            CommunityPost(
              id: 'entry',
              author: user['nickname']?.toString() ?? topic.author,
              userUrl: username.isEmpty
                  ? ''
                  : 'https://bgm.tv/user/${Uri.encodeComponent(username)}',
              body: blog['content']?.toString() ?? '',
              rawBody: blog['content']?.toString() ?? '',
              isOriginal: true,
            ),
            ...thread.posts,
          ],
        );
      }
      return thread;
    }
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
    return await _htmlCache.get(
      '$uri',
      () => _fetchHtml(path, query: query),
      refresh: refresh,
    );
  }

  Future<String> _fetchHtml(String path, {Map<String, dynamic>? query}) async {
    try {
      final response = await _htmlDio.get<String>(path, queryParameters: query);
      final html = response.data ?? '';
      if (html.isEmpty) throw const FormatException('Bangumi 返回了空页面');
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
  }) async {
    final uri = Uri.parse(
      path,
    ).replace(queryParameters: _stringQueryParameters(query));
    return await _jsonCache.get(
          '$uri',
          () => _fetchJson(path, query: query),
          refresh: refresh,
        )
        as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _fetchJson(
    String path, {
    Map<String, dynamic>? query,
    bool retriedAuth = false,
  }) async {
    DioException? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final response = await _p1Dio.get<Map<String, dynamic>>(
          '/p1$path',
          queryParameters: query,
        );
        final json = response.data;
        if (json == null) throw const FormatException('Bangumi 返回了空数据');
        return json;
      } on DioException catch (error) {
        lastError = error;
        if (!retriedAuth &&
            _isRefreshableAuthFailure(error) &&
            onUnauthorizedRefresh != null &&
            await onUnauthorizedRefresh!()) {
          return _fetchJson(path, query: query, retriedAuth: true);
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
  }) async {
    final uri = Uri.parse(
      path,
    ).replace(queryParameters: _stringQueryParameters(query));
    return await _jsonCache.get(
          'list:$uri',
          () => _fetchJsonList(path, query: query),
          refresh: refresh,
        )
        as List<dynamic>;
  }

  Future<List<dynamic>> _fetchJsonList(
    String path, {
    Map<String, dynamic>? query,
    bool retriedAuth = false,
  }) async {
    DioException? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final response = await _p1Dio.get<List<dynamic>>(
          '/p1$path',
          queryParameters: query,
        );
        final data = response.data;
        if (data == null) throw const FormatException('Bangumi 返回了空数据');
        return data;
      } on DioException catch (error) {
        lastError = error;
        if (!retriedAuth &&
            _isRefreshableAuthFailure(error) &&
            onUnauthorizedRefresh != null &&
            await onUnauthorizedRefresh!()) {
          return _fetchJsonList(path, query: query, retriedAuth: true);
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
    _jsonCache.removeWhere((key) => key.contains('/notify'));
  }

  Future<void> addFriend(String username) async {
    _requireAuthentication();
    final value = username.trim();
    if (value.isEmpty) throw Exception('用户名无效');
    final encoded = Uri.encodeComponent(value);
    await _putJson('/friends/$encoded', data: const {});
    _friendsCache.clear();
    _jsonCache.removeWhere(
      (key) => key.contains('/users/$encoded') || key.contains('/notify'),
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
    _jsonCache.removeWhere((key) => key.contains('/users/$encoded'));
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
    final identity = _identityRevision;
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
          _isRefreshableAuthFailure(
            error,
            oneShot: data.containsKey('turnstileToken'),
          ) &&
          onUnauthorizedRefresh != null &&
          await onUnauthorizedRefresh!()) {
        if (identity != _identityRevision || !isAuthenticated) {
          throw const FormatException('登录账号已变化，请重新操作');
        }
        await _postJson(path, data: data, retriedAuth: true);
        return;
      }
      final privateGroup = _privateGroupName(error.response?.data);
      final responseData = error.response?.data;
      final joinGroupFirst =
          error.response?.statusCode == 403 &&
          path.startsWith('/groups/') &&
          responseData is Map &&
          responseData['code'] == 'NOT_ALLOWED' &&
          (responseData['message']?.toString().toLowerCase().contains(
                'join group first',
              ) ??
              false);
      if (privateGroup != null || joinGroupFirst) {
        throw PrivateGroupMembershipException(privateGroup ?? '');
      }
      if (error.response == null || (error.response?.statusCode ?? 0) >= 500) {
        throw Exception('提交结果暂未确认，请先刷新页面确认，避免重复发送');
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
  bool _isRefreshableAuthFailure(DioException error, {bool oneShot = false}) {
    if (error.response?.statusCode != 401) return false;
    final data = error.response?.data;
    if (data is! Map) return !oneShot;
    final code = data['code']?.toString();
    return (code == null && !oneShot) ||
        code == 'TOKEN_INVALID' ||
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

  /// Read check and write-time purge must agree: [_storeIn] evicts anything
  /// older than the TTL it is handed, so a shorter write TTL silently caps the
  /// window the read check believes it has.
  static const Duration _friendsCacheTtl = Duration(minutes: 10);

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

class _NoticeTopicBatch {
  _NoticeTopicBatch({required this.topic, required this.notices});

  final CommunityTopic topic;
  final List<BangumiNotice> notices;
}

class _CachedFriends {
  const _CachedFriends(this.page, this.createdAt);

  final CommunityPageResult<BangumiUser> page;
  final DateTime createdAt;
}
