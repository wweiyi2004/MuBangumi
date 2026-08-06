import 'package:dio/dio.dart';

import '../../models/bangumi_models.dart';
import 'bangumi_endpoints.dart';
import 'bangumi_support.dart';

class BangumiApiException implements Exception {
  const BangumiApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class BangumiApi {
  BangumiApi()
    : _dio = Dio(
        BaseOptions(
          baseUrl: BangumiNetworkRoute.official.apiBaseUrl,
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 25),
          headers: const {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            'User-Agent': 'MuBangumi/1.0.0 (Flutter; personal Bangumi client)',
          },
        ),
      ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onError: (error, handler) {
          final data = error.response?.data;
          var message = '连接 Bangumi 失败，请稍后重试';
          if (data is Map) {
            message =
                (data['description'] ??
                        data['title'] ??
                        data['message'] ??
                        message)
                    .toString();
          } else if (error.type == DioExceptionType.connectionTimeout ||
              error.type == DioExceptionType.receiveTimeout) {
            message = '请求超时，请检查网络连接';
          } else if (error.response?.statusCode == 401) {
            message = 'Access Token 无效或已过期';
          } else if (error.response?.statusCode == 429) {
            message = '请求太频繁了，稍后再试';
          }
          handler.reject(
            DioException(
              requestOptions: error.requestOptions,
              response: error.response,
              type: error.type,
              error: BangumiApiException(
                message,
                statusCode: error.response?.statusCode,
              ),
            ),
          );
        },
      ),
    );
  }

  final Dio _dio;

  /// Called before authenticated requests to refresh near-expiry tokens.
  Future<void> Function()? ensureFreshToken;

  /// Called once on HTTP 401; return true if a new token was applied.
  Future<bool> Function()? onUnauthorizedRefresh;

  void setNetworkRoute(BangumiNetworkRoute route) {
    _dio.options.baseUrl = route.apiBaseUrl;
  }

  void setAccessToken(String? token) {
    if (token == null || token.isEmpty) {
      _dio.options.headers.remove('Authorization');
    } else {
      _dio.options.headers['Authorization'] = 'Bearer $token';
    }
  }

  Future<BangumiUser> getMe() async {
    final response = await _request(
      () => _dio.get<Map<String, dynamic>>('/me'),
    );
    return BangumiUser.fromJson(response.data ?? const {});
  }

  Future<BangumiUser> getUser(String username) async {
    final response = await _request(
      () => _dio.get<Map<String, dynamic>>(
        '/users/${Uri.encodeComponent(username)}',
      ),
    );
    return BangumiUser.fromJson(response.data ?? const {});
  }

  /// Lightweight total for one collection bucket (uses API `total`, limit=1).
  Future<int> getUserCollectionTotal(
    String username, {
    SubjectType? subjectType,
    CollectionType? collectionType,
  }) async {
    final response = await _request(
      () => _dio.get<Map<String, dynamic>>(
        '/users/${Uri.encodeComponent(username)}/collections',
        queryParameters: {
          if (subjectType != null) 'subject_type': subjectType.value,
          if (collectionType != null) 'type': collectionType.value,
          'limit': 1,
          'offset': 0,
        },
      ),
    );
    final json = response.data ?? const <String, dynamic>{};
    final data = json['data'];
    final pageLength = data is List ? data.length : 0;
    return (json['total'] as num?)?.toInt() ?? pageLength;
  }

  Future<Map<CollectionType, int>> getUserCollectionCounts(
    String username, {
    SubjectType subjectType = SubjectType.anime,
  }) async {
    final totals = await Future.wait([
      for (final type in CollectionType.values)
        getUserCollectionTotal(
          username,
          subjectType: subjectType,
          collectionType: type,
        ),
    ]);
    return {
      for (var index = 0; index < CollectionType.values.length; index++)
        CollectionType.values[index]: totals[index],
    };
  }

  Future<List<UserCollection>> getUserCollections(
    String username, {
    SubjectType? subjectType,
    CollectionType? collectionType,
    int? maxItems,
  }) async {
    // Larger pages cut request count for big libraries.
    const limit = 100;
    var offset = 0;
    var total = 0;
    final result = <UserCollection>[];
    final pageSize = maxItems == null
        ? limit
        : maxItems < limit
        ? maxItems
        : limit;

    do {
      final response = await _request(
        () => _dio.get<Map<String, dynamic>>(
          '/users/${Uri.encodeComponent(username)}/collections',
          queryParameters: {
            if (subjectType != null) 'subject_type': subjectType.value,
            if (collectionType != null) 'type': collectionType.value,
            'limit': pageSize,
            'offset': offset,
          },
        ),
      );
      final json = response.data ?? const <String, dynamic>{};
      final page = (json['data'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (item) => UserCollection.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList();
      total = (json['total'] as num?)?.toInt() ?? page.length;
      result.addAll(page);
      offset += page.length;
      if (page.isEmpty) break;
      if (maxItems != null && result.length >= maxItems) {
        return result.take(maxItems).toList();
      }
    } while (offset < total);

    result.sort((a, b) {
      final aTime = a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime);
    });
    return result;
  }

  /// Backward-compatible alias for anime-only collections.
  Future<List<UserCollection>> getAnimeCollections(String username) =>
      getUserCollections(username, subjectType: SubjectType.anime);

  Future<List<Subject>> searchSubjects(
    String keyword, {
    int limit = 24,
    int offset = 0,
    String sort = 'match',
    int minimumRating = 0,
    int startYear = 0,
    List<String> tags = const [],
    SubjectType subjectType = SubjectType.anime,
  }) async {
    final filter = <String, dynamic>{
      'type': [subjectType.value],
      'nsfw': false,
      if (minimumRating > 0) 'rating': ['>=$minimumRating'],
      // air_date covers broadcast / publish / release date across types.
      if (startYear > 0) 'air_date': ['>=$startYear-01-01'],
      if (tags.isNotEmpty) 'tag': tags,
    };
    final response = await _request(
      () => _dio.post<Map<String, dynamic>>(
        '/search/subjects',
        queryParameters: BangumiSupport.pageQuery(limit: limit, offset: offset),
        data: {'keyword': keyword, 'sort': sort, 'filter': filter},
      ),
    );
    return _subjectsFromPage(response.data);
  }

  Future<List<CharacterDetail>> searchCharacters(
    String keyword, {
    int limit = 24,
    int offset = 0,
  }) async {
    final response = await _request(
      () => _dio.post<Map<String, dynamic>>(
        '/search/characters',
        queryParameters: BangumiSupport.pageQuery(limit: limit, offset: offset),
        data: {
          'keyword': keyword,
          'filter': {'nsfw': false},
        },
      ),
      checkToken: false,
    );
    final data = response.data?['data'];
    if (data is! List) return const [];
    return [
      for (final item in data)
        if (item is Map)
          BangumiSupport.parseCharacterDetail(Map<String, dynamic>.from(item)),
    ];
  }

  Future<List<PersonDetail>> searchPersons(
    String keyword, {
    int limit = 24,
    int offset = 0,
  }) async {
    final response = await _request(
      () => _dio.post<Map<String, dynamic>>(
        '/search/persons',
        queryParameters: BangumiSupport.pageQuery(limit: limit, offset: offset),
        data: {
          'keyword': keyword,
          'filter': {'nsfw': false},
        },
      ),
      checkToken: false,
    );
    final data = response.data?['data'];
    if (data is! List) return const [];
    return [
      for (final item in data)
        if (item is Map)
          BangumiSupport.parsePersonDetail(Map<String, dynamic>.from(item)),
    ];
  }

  Future<List<Subject>> browseSeason({
    required int year,
    required int month,
  }) => browseSubjects(
    type: SubjectType.anime,
    year: year,
    month: month,
    sort: 'rank',
  );

  /// Browse ranked subjects by type. Month is mainly useful for TV seasons.
  Future<List<Subject>> browseSubjects({
    required SubjectType type,
    int? year,
    int? month,
    String sort = 'rank',
    int limit = 24,
    int offset = 0,
  }) async {
    final response = await _request(
      () => _dio.get<Map<String, dynamic>>(
        '/subjects',
        queryParameters: {
          'type': type.value,
          'sort': sort,
          'year': ?year,
          'month': ?month,
          ...BangumiSupport.pageQuery(limit: limit, offset: offset),
        },
      ),
    );
    return _subjectsFromPage(response.data);
  }

  Future<Subject> getSubject(int subjectId) async {
    final response = await _request(
      () => _dio.get<Map<String, dynamic>>('/subjects/$subjectId'),
    );
    return Subject.fromJson(response.data ?? const {});
  }

  Future<List<SubjectCharacter>> getSubjectCharacters(int subjectId) async {
    final response = await _request(
      () => _dio.get<List<dynamic>>('/subjects/$subjectId/characters'),
      checkToken: false,
    );
    return BangumiSupport.parseCharacters(response.data);
  }

  Future<List<SubjectPerson>> getSubjectPersons(int subjectId) async {
    final response = await _request(
      () => _dio.get<List<dynamic>>('/subjects/$subjectId/persons'),
      checkToken: false,
    );
    return BangumiSupport.parsePersons(response.data);
  }

  Future<List<RelatedSubject>> getRelatedSubjects(int subjectId) async {
    final response = await _request(
      () => _dio.get<List<dynamic>>('/subjects/$subjectId/subjects'),
      checkToken: false,
    );
    return BangumiSupport.parseRelatedSubjects(response.data);
  }

  Future<CharacterDetail> getCharacter(int characterId) async {
    final response = await _request(
      () => _dio.get<Map<String, dynamic>>('/characters/$characterId'),
      checkToken: false,
    );
    return BangumiSupport.parseCharacterDetail(response.data ?? const {});
  }

  Future<List<MonoLinkedSubject>> getCharacterSubjects(int characterId) async {
    final response = await _request(
      () => _dio.get<List<dynamic>>('/characters/$characterId/subjects'),
      checkToken: false,
    );
    return BangumiSupport.parseMonoSubjects(response.data);
  }

  Future<List<MonoLinkedPerson>> getCharacterPersons(int characterId) async {
    final response = await _request(
      () => _dio.get<List<dynamic>>('/characters/$characterId/persons'),
      checkToken: false,
    );
    return BangumiSupport.parseCharacterPersons(response.data);
  }

  Future<PersonDetail> getPerson(int personId) async {
    final response = await _request(
      () => _dio.get<Map<String, dynamic>>('/persons/$personId'),
      checkToken: false,
    );
    return BangumiSupport.parsePersonDetail(response.data ?? const {});
  }

  Future<List<MonoLinkedSubject>> getPersonSubjects(int personId) async {
    final response = await _request(
      () => _dio.get<List<dynamic>>('/persons/$personId/subjects'),
      checkToken: false,
    );
    return BangumiSupport.parseMonoSubjects(response.data);
  }

  Future<List<MonoLinkedCharacter>> getPersonCharacters(int personId) async {
    final response = await _request(
      () => _dio.get<List<dynamic>>('/persons/$personId/characters'),
      checkToken: false,
    );
    return BangumiSupport.parsePersonCharacters(response.data);
  }

  /// Official weekly broadcast calendar (not local 新番表).
  ///
  /// Bangumi serves this on the **legacy** root (`/calendar`), not under OpenAPI
  /// `/v0`. Using the Dio baseUrl would hit `/v0/calendar` and 404.
  Future<List<CalendarDay>> getCalendar() async {
    final route = BangumiEndpoints.route;
    final response = await _request(
      () => _dio.get<List<dynamic>>(
        '${route.apiRootUrl}/calendar',
      ),
      checkToken: false,
    );
    return BangumiSupport.parseCalendar(response.data);
  }

  /// Public subject comments (吐槽). Tries HTML page; returns empty if blocked.
  Future<List<SubjectComment>> getSubjectComments(
    int subjectId, {
    int page = 1,
  }) async {
    try {
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 20),
          headers: const {
            'User-Agent':
                'MuBangumi/1.0.0 (Flutter; personal Bangumi client)',
            'Accept': 'text/html,application/xhtml+xml',
          },
          responseType: ResponseType.plain,
        ),
      );
      final response = await dio.get<String>(
        'https://bgm.tv/subject/$subjectId/comments',
        queryParameters: {'page': page},
      );
      return BangumiSupport.parseSubjectCommentsHtml(response.data ?? '');
    } catch (_) {
      return const [];
    }
  }

  /// [episodeType] defaults to `0` (本篇) so progress tooling stays main-only.
  /// Pass `null` to load all types (SP/OP/ED) for UI filters.
  Future<List<Episode>> getEpisodes(
    int subjectId, {
    int? episodeType = 0,
  }) async {
    final result = <Episode>[];
    var offset = 0;
    const limit = 100;
    var total = 0;
    do {
      final response = await _request(
        () => _dio.get<Map<String, dynamic>>(
          '/episodes',
          queryParameters: {
            'subject_id': subjectId,
            'type': ?episodeType,
            'limit': limit,
            'offset': offset,
          },
        ),
      );
      final json = response.data ?? const <String, dynamic>{};
      final page = (json['data'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Episode.fromJson(Map<String, dynamic>.from(item)))
          .toList();
      total = (json['total'] as num?)?.toInt() ?? page.length;
      result.addAll(page);
      offset += page.length;
      if (page.isEmpty) break;
    } while (offset < total);
    result.sort((a, b) => a.sort.compareTo(b.sort));
    return result;
  }

  /// [episodeType] defaults to `0` (本篇) for progress (mark-next / done).
  /// Pass `null` for all types when the UI needs SP/OP/ED filters.
  Future<List<UserEpisodeCollection>> getEpisodeCollections(
    int subjectId, {
    int? episodeType = 0,
  }) async {
    final result = <UserEpisodeCollection>[];
    var offset = 0;
    const limit = 100;
    var total = 0;
    do {
      final response = await _request(
        () => _dio.get<Map<String, dynamic>>(
          '/users/-/collections/$subjectId/episodes',
          queryParameters: {
            'episode_type': ?episodeType,
            'limit': limit,
            'offset': offset,
          },
        ),
      );
      final json = response.data ?? const <String, dynamic>{};
      final page = (json['data'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (item) => UserEpisodeCollection.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList();
      total = (json['total'] as num?)?.toInt() ?? page.length;
      result.addAll(page);
      offset += page.length;
      if (page.isEmpty) break;
    } while (offset < total);
    result.sort((a, b) => a.episode.sort.compareTo(b.episode.sort));
    return result;
  }

  Future<void> updateEpisode(int episodeId, {required int type}) async {
    await _request(
      () => _dio.put<void>(
        '/users/-/collections/-/episodes/$episodeId',
        data: {'type': type},
      ),
    );
  }

  /// Batch update episode watch state (garage "看过自动完成进度").
  Future<void> updateEpisodesBatch(
    int subjectId, {
    required List<int> episodeIds,
    required int type,
  }) async {
    if (episodeIds.isEmpty) return;
    const chunkSize = 100;
    for (var offset = 0; offset < episodeIds.length; offset += chunkSize) {
      final end = offset + chunkSize > episodeIds.length
          ? episodeIds.length
          : offset + chunkSize;
      final chunk = episodeIds.sublist(offset, end);
      await _request(
        () => _dio.patch<void>(
          '/users/-/collections/$subjectId/episodes',
          data: {'episode_id': chunk, 'type': type},
        ),
      );
    }
  }

  /// Create or update a user collection (status, score, comment, tags, privacy).
  ///
  /// [episodeStatus] / [volumeStatus] map to book progress fields only.
  Future<void> updateCollection(
    int subjectId,
    CollectionType type, {
    int rate = 0,
    String comment = '',
    List<String> tags = const [],
    bool private = false,
    int? episodeStatus,
    int? volumeStatus,
  }) async {
    final data = BangumiSupport.collectionUpdatePayload(
      type: type,
      rate: rate,
      comment: comment,
      tags: tags,
      private: private,
      episodeStatus: episodeStatus,
      volumeStatus: volumeStatus,
    );
    await _request(
      () => _dio.post<void>(
        '/users/-/collections/$subjectId',
        data: data,
      ),
    );
  }

  Future<UserCollection?> getUserSubjectCollection(
    String username,
    int subjectId, {
    bool checkToken = true,
  }) async {
    try {
      final response = await _request(
        () => _dio.get<Map<String, dynamic>>(
          '/users/${Uri.encodeComponent(username)}/collections/$subjectId',
        ),
        checkToken: checkToken,
      );
      final json = response.data;
      if (json == null) return null;
      return UserCollection.fromJson(json);
    } on BangumiApiException catch (error) {
      if (error.statusCode == 404) return null;
      rethrow;
    }
  }

  /// Friends who have this subject in their public collections.
  /// Uses a small concurrency pool to avoid freezing the UI / network stack.
  Future<List<FriendSubjectStatus>> getFriendsSubjectStatus(
    int subjectId, {
    required List<BangumiUser> friends,
    int limit = 12,
    int concurrency = 3,
  }) async {
    final selected = friends.take(limit).toList();
    if (selected.isEmpty) return const [];
    // Refresh token once, then skip per-request checks for bulk lookups.
    await ensureFreshToken?.call();
    final statuses = <FriendSubjectStatus>[];
    var index = 0;
    Future<void> worker() async {
      while (true) {
        final current = index;
        index += 1;
        if (current >= selected.length) return;
        final friend = selected[current];
        try {
          final collection = await getUserSubjectCollection(
            friend.username,
            subjectId,
            checkToken: false,
          );
          if (collection == null) continue;
          statuses.add(
            FriendSubjectStatus(
              user: friend,
              type: collection.type,
              rate: collection.rate,
              episodeStatus: collection.episodeStatus,
            ),
          );
        } catch (_) {
          // Ignore individual friend lookup failures.
        }
      }
    }

    await Future.wait([
      for (var i = 0; i < concurrency && i < selected.length; i++) worker(),
    ]);
    statuses.sort((a, b) {
      final order = {
        CollectionType.doing: 0,
        CollectionType.wish: 1,
        CollectionType.done: 2,
        CollectionType.onHold: 3,
        CollectionType.dropped: 4,
      };
      return (order[a.type] ?? 9).compareTo(order[b.type] ?? 9);
    });
    return statuses;
  }

  List<Subject> _subjectsFromPage(Map<String, dynamic>? json) =>
      (json?['data'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Subject.fromJson(Map<String, dynamic>.from(item)))
          .toList();

  Future<Response<T>> _request<T>(
    Future<Response<T>> Function() request, {
    bool retried = false,
    bool checkToken = true,
  }) async {
    try {
      if (checkToken) await ensureFreshToken?.call();
      return await request();
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      if (!retried &&
          status == 401 &&
          onUnauthorizedRefresh != null &&
          await onUnauthorizedRefresh!()) {
        return _request(request, retried: true, checkToken: false);
      }
      if (error.error is BangumiApiException) {
        throw error.error! as BangumiApiException;
      }
      throw BangumiApiException(error.message ?? '未知网络错误');
    }
  }
}
