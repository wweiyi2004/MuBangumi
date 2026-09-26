import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/storage/community_cache.dart';
import '../../models/bangumi_models.dart';
import '../../models/community_models.dart';
import '../../models/community_topic_submission.dart';
import '../../models/account_content_preferences.dart';
import '../auth/website_session.dart';
import '../auth/website_identity.dart';
import 'bangumi_smiles.dart';
import 'async_cache.dart';
import 'bangumi_user_agent.dart';
import 'community_html_parser.dart';
import 'community_p1_parser.dart';
import 'pm_html_parser.dart';
import '../diagnostics/account_diagnostics.dart';
import 'account_diagnostics_interceptor.dart';
import 'community_write_client.dart';
import 'community_website_client.dart';

/// Strong signals that a classic website page is actually the login form.
bool looksLikeWebsiteLoginPage(String source) {
  return PmHtmlParser().looksLikeLoginPage(source);
}

/// An explicit P1 membership rejection. Some server versions disagree with the
/// classic website's membership check; only this refusal permits its fallback.
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
    AccountDiagnostics? diagnostics,
  }) : _diagnostics = diagnostics ?? AccountDiagnostics(),
       _sessionStore = sessionStore ?? WebsiteSessionStore(),
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
           ) {
    _htmlDio.interceptors.add(
      AccountDiagnosticsInterceptor(_diagnostics, AccountArea.communityWebsite),
    );
    _p1Dio.interceptors.add(
      AccountDiagnosticsInterceptor(_diagnostics, AccountArea.communityApi),
    );
  }

  Future<WebsiteSessionSnapshot> Function()? websiteSessionGuard;
  WebsiteSessionFailureReporter? onWebsiteSessionFailure;

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
  final AccountDiagnostics _diagnostics;
  late final _writes = CommunityWriteClient(
    dio: _p1Dio,
    readIdentity: () => _identityRevision,
    isAuthenticated: () => isAuthenticated,
    refresh: () async => await onUnauthorizedRefresh?.call() ?? false,
    diagnostics: _diagnostics,
  );
  late final _website = CommunityWebsiteClient(
    dio: _htmlDio,
    readIdentity: () => _identityRevision,
    requireSession: _requireWebsiteSession,
    readFailureReporter: () => onWebsiteSessionFailure,
  );
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
  int _friendRevision = 0;
  int _groupMembershipRevision = 0;

  void _checkIdentity(int identity) {
    if (identity != _identityRevision) {
      throw const FormatException('登录账号已变化，请重新操作');
    }
  }

  (int, int) get _friendContext => (_identityRevision, _friendRevision);
  void _checkFriendContext((int, int) context) {
    if (context != _friendContext) {
      throw const FormatException('账号或好友关系已变化，请刷新好友列表');
    }
  }

  void _invalidateFriendRelations() {
    _friendRevision++;
    _friendsCache.clear();
    _jsonCache.removeWhere(
      (key) =>
          key.contains('/users/') ||
          key.contains('/notify') ||
          key.startsWith('list:/timeline'),
    );
  }

  (int, int, int) get _groupContext =>
      (_identityRevision, _groupMembershipRevision, _contentRevision);
  void _checkGroupContext((int, int, int) context) {
    if (context != _groupContext) {
      throw const FormatException('账号或小组状态已变化，请刷新小组');
    }
  }

  /// A website membership operation must not reuse a pre-operation API read.
  void invalidateGroupMembership() {
    _groupMembershipRevision++;
    _jsonCache.removeWhere((key) => key.startsWith('/groups'));
    _htmlCache.removeWhere((key) => key.contains('/group'));
  }

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
    final wasAuthenticated = isAuthenticated;
    if (token == null || token.trim().isEmpty) {
      _p1Dio.options.headers.remove('Authorization');
    } else {
      _p1Dio.options.headers['Authorization'] = 'Bearer ${token.trim()}';
    }
    if (wasAuthenticated != isAuthenticated) _identityRevision++;
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

  /// Business error mapping stays here; the client owns account guards and retry.
  Future<Object?> _nativeWrite(
    String method,
    String path, {
    Map<String, dynamic> data = const {},
    bool accountPreferences = false,
  }) async {
    _requireAuthentication();
    try {
      return await _writes.send(method, path, data: data);
    } on DioException catch (error) {
      if (method == 'POST' && error.response == null) {
        throw Exception('提交结果尚未确认，请先查看日志列表，确认没有发布后再重试');
      }
      if (accountPreferences) {
        throw AccountContentPreferencesException(error.response?.statusCode);
      }
      throw Exception(_postErrorMessage(error));
    }
  }

  Future<CommunityPageResult<BangumiUser>> loadFriends(
    String username, {
    int limit = 30,
    int offset = 0,
    bool refresh = false,
  }) async {
    final context = _friendContext;
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
    _checkFriendContext(context);
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
    final rawCount = data is List ? data.length : 0;
    final total = (json['total'] as num?)?.toInt() ?? rawCount;
    final page = CommunityPageResult(
      data: users,
      total: total,
      rawCount: rawCount,
    );
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
    final context = _friendContext;
    final friends = <BangumiUser>[];
    final known = <String>{};
    var offset = 0;
    var total = 0;
    var pages = 0;
    do {
      final page = await loadFriends(
        username,
        limit: pageSize.clamp(1, 100),
        offset: offset,
        refresh: refresh,
      );
      _checkFriendContext(context);
      for (final friend in page.data) {
        final key = friend.username.trim().toLowerCase();
        if (key.isNotEmpty && known.add(key)) friends.add(friend);
      }
      total = page.total;
      pages++;
      final consumed = page.rawCount ?? page.data.length;
      if (consumed == 0 || pages >= maxFriendPages) break;
      offset += consumed;
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
    if (mode.requiresLogin && !isAuthenticated) return null;
    final context = _groupContext;
    final json = await _readSnapshot(_groupCacheKey(mode, sort));
    if (json == null ||
        context != _groupContext ||
        (mode.requiresLogin && !isAuthenticated)) {
      return null;
    }
    return CommunityPageResult(
      data: _p1Parser.parseGroups(json),
      total: _pageTotal(json),
      rawCount: (json['data'] as List?)?.length ?? 0,
    );
  }

  Future<CommunityPageResult<CommunityGroup>> loadGroupPage({
    CommunityGroupMode mode = CommunityGroupMode.all,
    CommunityGroupSort sort = CommunityGroupSort.members,
    int limit = 20,
    int offset = 0,
    bool refresh = false,
  }) async {
    if (mode.requiresLogin) _requireAuthentication();
    final identity = _identityRevision;
    final context = _groupContext;
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
    _checkGroupContext(context);
    if (mode.requiresLogin) _requireAuthentication();
    if (offset == 0) {
      await _writeSnapshot(
        _groupCacheKey(mode, sort),
        json,
        identity: identity,
        accountScoped: mode.requiresLogin,
      );
    }
    _checkGroupContext(context);
    if (mode.requiresLogin) _requireAuthentication();
    return CommunityPageResult(
      data: _p1Parser.parseGroups(json),
      total: _pageTotal(json),
      rawCount: (json['data'] as List?)?.length ?? 0,
    );
  }

  Future<CommunityGroupDetail?> readCachedGroupDetail(String slug) async {
    final context = _groupContext;
    final bundle = await _readSnapshot('group:$slug');
    if (bundle == null || context != _groupContext) return null;
    return _parseGroupBundle(bundle);
  }

  Future<CommunityGroupDetail> loadGroupPreview(String slug) async {
    final context = _groupContext;
    final json = await _getJson(
      '/groups/${Uri.encodeComponent(slug)}',
      refresh: true,
    );
    _checkGroupContext(context);
    return _p1Parser.parseGroupDetail(json);
  }

  Future<CommunityPageResult<CommunityTopic>> loadGroupTopics(
    String slug, {
    int offset = 0,
    int limit = 20,
    bool refresh = false,
  }) async {
    final context = _groupContext;
    final page = await _getJson(
      '/groups/${Uri.encodeComponent(slug)}/topics',
      query: {'limit': limit.clamp(1, 100), 'offset': offset},
      refresh: refresh,
    );
    _checkGroupContext(context);
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
    final context = _groupContext;
    final page = await _getJson(
      '/groups/${Uri.encodeComponent(slug)}/members',
      query: {'limit': limit.clamp(1, 100), 'offset': offset, 'role': ?role},
      refresh: refresh,
    );
    _checkGroupContext(context);
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
    final context = _groupContext;
    final encoded = Uri.encodeComponent(slug);
    Future<Map<String, dynamic>?> optionalPage(
      String path,
      Map<String, dynamic> query,
    ) async {
      try {
        final page = await _getJson(
          path,
          query: query,
          refresh: refresh,
        ).timeout(const Duration(seconds: 12));
        if (page['data'] is! List) return null;
        return page;
      } catch (_) {
        return null;
      }
    }

    final values = await Future.wait([
      _getJson('/groups/$encoded', refresh: refresh),
      optionalPage('/groups/$encoded/members', {
        'role': CommunityGroupRole.member.value,
        'limit': 20,
        'offset': 0,
      }),
      optionalPage('/groups/$encoded/members', {
        'role': CommunityGroupRole.creator.value,
        'limit': 10,
        'offset': 0,
      }),
      optionalPage('/groups/$encoded/members', {
        'role': CommunityGroupRole.moderator.value,
        'limit': 10,
        'offset': 0,
      }),
      optionalPage('/groups/$encoded/topics', const {'limit': 20, 'offset': 0}),
    ]);
    _checkGroupContext(context);
    final managementRows = <dynamic>[
      ...(values[2]?['data'] as List? ?? const []),
      ...(values[3]?['data'] as List? ?? const []),
    ];
    final bundle = <String, dynamic>{
      'group': values[0],
      'members': values[1],
      'moderators': {'data': managementRows},
      'topics': values[4],
      'unavailable_sections': [
        if (values[1] == null) CommunityGroupSection.members.name,
        if (values[2] == null || values[3] == null)
          CommunityGroupSection.moderators.name,
        if (values[4] == null) CommunityGroupSection.topics.name,
      ],
    };
    await _writeSnapshot(
      'group:$slug',
      bundle,
      identity: identity,
      accountScoped: true,
    );
    _checkGroupContext(context);
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

  Future<CommunityTopic> createGroupTopic({
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
    int? topicId;
    try {
      final result = await _postJson(
        '/groups/$encoded/topics',
        data: {
          'title': trimmedTitle,
          'content': trimmedContent,
          'turnstileToken': token,
        },
      );
      topicId = parseCreatedCommunityTopicId(result);
      if (topicId == null) throw const CommunitySubmissionUncertain();
    } on PrivateGroupMembershipException {
      if (identity != _identityRevision) {
        throw const FormatException('账号已变化，请重新发起讨论');
      }
      // The API explicitly refused the write. A website membership check can
      // recover compatibility; an uncertain POST never takes this fallback.
      topicId = await _website.createGroupTopic(
        slug: slug,
        title: trimmedTitle,
        content: trimmedContent,
      );
    }
    _jsonCache.removeWhere(
      (key) => key.contains('/groups/$encoded') || key.contains('/topics'),
    );
    return createdGroupTopic(slug: slug, title: trimmedTitle, id: topicId);
  }

  CommunityTopic createdGroupTopic({
    required String slug,
    required String title,
    required int id,
  }) => CommunityTopic(
    id: id,
    kind: CommunityTopicKind.group,
    title: title,
    url: 'https://bgm.tv/rakuen/topic/group/$id',
    webUrl: 'https://bgm.tv/group/topic/$id',
    sourceUrl: 'https://bgm.tv/group/${Uri.encodeComponent(slug)}',
  );

  /// Read-only reconciliation. A missing match is inconclusive (moderation,
  /// indexing delay, or an older page), never permission to replay the POST.
  Future<CommunityTopic?> findSubmittedGroupTopic({
    required String slug,
    required String title,
    required String content,
    required DateTime? attemptedAt,
  }) async {
    _requireAuthentication();
    final identity = _identityRevision;
    final username = _currentUsername;
    if (username == null) throw const FormatException('请先确认当前账号');
    void guard() {
      if (identity != _identityRevision ||
          !isAuthenticated ||
          username != _currentUsername) {
        throw const FormatException('账号已变化，请返回原账号核对发帖结果');
      }
    }

    String normalize(String value) => value.replaceAll('\r\n', '\n').trim();
    final now = DateTime.now().toUtc();
    final lower =
        attemptedAt?.subtract(const Duration(seconds: 5)) ??
        now.subtract(const Duration(hours: 24));
    final upper = attemptedAt?.add(const Duration(minutes: 5)) ?? now;
    bool matches(Map value) {
      final creator = value['creator'];
      final seconds = value['createdAt'];
      final created = seconds is num
          ? DateTime.fromMillisecondsSinceEpoch(
              (seconds * 1000).round(),
              isUtc: true,
            )
          : null;
      return creator is Map &&
          creator['username']?.toString().toLowerCase() ==
              username.toLowerCase() &&
          value['title'] == title.trim() &&
          created != null &&
          !created.isBefore(lower) &&
          !created.isAfter(upper);
    }

    final found = <int>{};
    var inspected = 0;
    for (var offset = 0; offset < 100; offset += 50) {
      guard();
      final page = await _getJson(
        '/groups/-/topics',
        query: {'mode': 'created', 'limit': 50, 'offset': offset},
        refresh: true,
      );
      guard();
      final rows = page['data'];
      if (rows is! List) throw const FormatException('无法读取已发表话题，请稍后核对');
      for (final row in rows.whereType<Map>()) {
        final id = parseCreatedCommunityTopicId(row);
        if (id == null || !matches(row)) continue;
        if (++inspected > 5) return null;
        final detail = await _getJson('/groups/-/topics/$id', refresh: true);
        guard();
        final group = detail['group'];
        final replies = detail['replies'];
        if (!matches(detail) ||
            group is! Map ||
            group['name'] != slug ||
            replies is! List ||
            replies.isEmpty ||
            replies.first is! Map) {
          continue;
        }
        final original = replies.first as Map;
        final author = original['creator'];
        if (author is Map &&
            author['username']?.toString().toLowerCase() ==
                username.toLowerCase() &&
            original['content'] is String &&
            normalize(original['content'] as String) == normalize(content)) {
          found.add(id);
        }
      }
      if (rows.length < 50) break;
    }
    guard();
    return found.length == 1
        ? createdGroupTopic(slug: slug, title: title.trim(), id: found.single)
        : null;
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
      // Only an explicit private-group refusal can fall back to the classic
      // website's independent membership check.
      await _website.replyToGroupTopic(
        topicId: id,
        content: trimmed,
        replyTo: replyTo,
      );
    }
    _invalidateThread(topic);
  }

  Future<WebsiteSessionSnapshot> _requireWebsiteSession() async {
    if (websiteSessionGuard case final guard?) {
      return await guard();
    }
    final snapshot = await _sessionStore.read();
    final header = snapshot?.cookieHeader.trim() ?? '';
    if (snapshot == null || header.isEmpty || !snapshot.hasSessionCookies) {
      throw const WebsiteAccessException(
        WebsiteAccessStatus.missing,
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
      unavailableSections: {
        for (final section in CommunityGroupSection.values)
          if ((bundle['unavailable_sections'] as List?)?.contains(
                section.name,
              ) ==
              true)
            section,
      },
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
    if (topic.kind == CommunityTopicKind.group) {
      return _loadGroupTopic(topic, refresh: refresh);
    }
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

  Future<CommunityTopicDetail> _loadGroupTopic(
    CommunityTopic topic, {
    required bool refresh,
  }) async {
    final context = _groupContext;
    final id = resolveTopicId(topic);
    if (id == null) throw const FormatException('无法识别话题编号');
    try {
      final json = await _getJson('/groups/-/topics/$id', refresh: refresh);
      _checkGroupContext(context);
      if (json['replies'] is! List) throw const FormatException('话题数据不完整');
      final detail = _p1Parser.parseTopicDetail(json, topic);
      if (detail.posts.isEmpty) throw const FormatException('话题正文暂时不可见');
      return detail;
    } catch (_) {
      _checkGroupContext(context);
    }
    // Public content can still be read without a website login. Never send
    // website cookies to a URL supplied by a feed or to an unrelated host.
    final path = '/group/topic/$id';
    try {
      final html = await _getHtml(path, refresh: refresh);
      _checkGroupContext(context);
      final detail = _htmlParser.parseTopicDetail(html, topic);
      if (!looksLikeWebsiteLoginPage(html) &&
          !WebsiteIdentityProbe.isChallenge(html) &&
          detail.posts.isNotEmpty) {
        return detail;
      }
    } catch (_) {
      _checkGroupContext(context);
    }
    if (!isAuthenticated) throw const FormatException('话题暂时不可见，请登录后重试或在官网核对');
    final session = await _requireWebsiteSession();
    _checkGroupContext(context);
    final html = await _website.fetchHtml(path, session);
    _checkGroupContext(context);
    _website.checkLoginPage(html, session);
    final current = await _requireWebsiteSession();
    _checkGroupContext(context);
    if (current.authenticationKey != session.authenticationKey) {
      throw const FormatException('网页登录已变化，请重新打开话题');
    }
    final detail = _htmlParser.parseTopicDetail(html, topic);
    if (detail.posts.isEmpty) {
      throw const FormatException('暂时无法读取话题正文，请在官网核对小组权限或稍后重试');
    }
    return detail;
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
    final identity = _identityRevision;
    final uri = Uri.parse(
      path,
    ).replace(queryParameters: _stringQueryParameters(query));
    final result =
        await _jsonCache.get(
              '$uri',
              () => _fetchJson(path, query: query),
              refresh: refresh,
            )
            as Map<String, dynamic>;
    _checkIdentity(identity);
    return result;
  }

  Future<Map<String, dynamic>> _fetchJson(
    String path, {
    Map<String, dynamic>? query,
  }) => _fetchP1<Map<String, dynamic>>(path, query: query);

  Future<T> _fetchP1<T>(
    String path, {
    Map<String, dynamic>? query,
    bool retriedAuth = false,
    int? identity,
  }) async {
    identity ??= _identityRevision;
    DioException? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      _checkIdentity(identity);
      try {
        final response = await _p1Dio.get<T>(
          '/p1$path',
          queryParameters: query,
        );
        _checkIdentity(identity);
        final json = response.data;
        if (json == null) throw const FormatException('Bangumi 返回了空数据');
        return json;
      } on DioException catch (error) {
        _checkIdentity(identity);
        lastError = error;
        if (!retriedAuth &&
            _isRefreshableAuthFailure(error) &&
            onUnauthorizedRefresh != null) {
          final refreshed = await onUnauthorizedRefresh!();
          _checkIdentity(identity);
          if (refreshed) {
            return _fetchP1<T>(
              path,
              query: query,
              retriedAuth: true,
              identity: identity,
            );
          }
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
    final identity = _identityRevision;
    final uri = Uri.parse(
      path,
    ).replace(queryParameters: _stringQueryParameters(query));
    final result =
        await _jsonCache.get(
              'list:$uri',
              () => _fetchJsonList(path, query: query),
              refresh: refresh,
            )
            as List<dynamic>;
    _checkIdentity(identity);
    return result;
  }

  Future<List<dynamic>> _fetchJsonList(
    String path, {
    Map<String, dynamic>? query,
  }) => _fetchP1<List<dynamic>>(path, query: query);

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
    _invalidateFriendRelations();
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
    _invalidateFriendRelations();
  }

  /// Returns whether [username] is already a friend.
  ///
  /// Uses `GET /p1/users/{username}` (`isFriend`) so it matches the same
  /// username lookup as [addFriend], instead of walking a possibly nested
  /// friends list.
  Future<bool> isFriend(String username) async {
    _requireAuthentication();
    final context = _friendContext;
    final value = username.trim();
    if (value.isEmpty) return false;
    final me = _currentUsername;
    if (me != null && value.toLowerCase() == me.toLowerCase()) return false;
    final json = await _getJson('/users/${Uri.encodeComponent(value)}');
    _checkFriendContext(context);
    return json['isFriend'] == true;
  }

  Future<Object?> _postJson(
    String path, {
    Map<String, dynamic> data = const {},
  }) async {
    try {
      return await _writes.send('POST', path, data: data);
    } on DioException catch (error) {
      final privateGroup = _privateGroupName(error.response?.data);
      final responseData = error.response?.data;
      final joinGroupFirst =
          const [401, 403].contains(error.response?.statusCode) &&
          path.startsWith('/groups/') &&
          responseData is Map &&
          responseData['code'] == 'NOT_ALLOWED' &&
          (responseData['message']?.toString().toLowerCase().contains(
                'join group first',
              ) ??
              false);
      if ((privateGroup != null &&
              const [401, 403].contains(error.response?.statusCode)) ||
          joinGroupFirst) {
        throw PrivateGroupMembershipException(privateGroup ?? '');
      }
      if (error.response == null || (error.response?.statusCode ?? 0) >= 500) {
        throw const CommunitySubmissionUncertain('提交结果暂未确认，请先核对结果，避免重复发送');
      }
      throw CommunitySubmissionRejected(_postErrorMessage(error));
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
  }) async {
    try {
      await _writes.send('PUT', path, data: data);
    } on DioException catch (error) {
      throw Exception(_postErrorMessage(error));
    }
  }

  Future<void> _deleteJson(String path) async {
    try {
      await _writes.send('DELETE', path);
    } on DioException catch (error) {
      throw Exception(_postErrorMessage(error));
    }
  }

  bool _isRefreshableAuthFailure(DioException error, {bool oneShot = false}) =>
      CommunityWriteClient.isCredentialFailure(error, oneShot: oneShot);

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
