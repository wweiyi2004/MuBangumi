import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/netaba_models.dart';
import 'bangumi_user_agent.dart';
import 'async_cache.dart';

class NetabaApiException implements Exception {
  const NetabaApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Client for the public [netaba.re](https://netaba.re) analytics API.
///
/// Data source: https://api.netaba.re — historical Bangumi score / rank /
/// collection snapshots maintained by the Netabare project.
class NetabaApi {
  NetabaApi({Dio? dio, DateTime Function()? now})
    : _cache = AsyncCache<Object>(
        maxAge: const Duration(minutes: 10),
        maxEntries: 64,
        now: now,
      ),
      _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: 'https://api.netaba.re',
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
              headers: const {
                'Accept': 'application/json',
                'User-Agent':
                    'MuBangumi/$muBangumiUaVersion (Flutter; personal Bangumi client; +https://netaba.re)',
              },
            ),
          ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onError: (error, handler) {
          // Status/transport first so dedicated messages are reachable;
          // a JSON error body must not shadow them.
          final data = error.response?.data;
          final status = error.response?.statusCode;
          var message = '获取评分历史失败，请稍后重试';
          if (error.type == DioExceptionType.connectionTimeout ||
              error.type == DioExceptionType.receiveTimeout) {
            message = '评分历史请求超时，请检查网络';
          } else if (status == 404) {
            message = '该条目暂无历史评分记录';
          } else if (status == 429) {
            message = '评分历史请求太频繁，稍后再试';
          } else if (data is Map) {
            message =
                (data['message'] ?? data['error'] ?? data['title'] ?? message)
                    .toString();
          }
          handler.reject(
            DioException(
              requestOptions: error.requestOptions,
              response: error.response,
              type: error.type,
              error: NetabaApiException(
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
  final AsyncCache<Object> _cache;

  void clearCache() => _cache.clear();

  Future<NetabaSubjectHistory> getSubjectHistory(int subjectId) async =>
      await _cache.get(
            'subject:$subjectId',
            () => _fetchSubjectHistory(subjectId),
          )
          as NetabaSubjectHistory;

  Future<NetabaTrending> getTrending() async =>
      await _cache.get('trending', _fetchTrending) as NetabaTrending;

  Future<List<NetabaTrendingItem>> getScoreIncreases() async =>
      await _cache.get('score-increases', _fetchScoreIncreases)
          as List<NetabaTrendingItem>;

  /// Full score / rank / collection history for a Bangumi subject.
  Future<NetabaSubjectHistory> _fetchSubjectHistory(int subjectId) async {
    final response = await _request(
      () => _dio.get<Map<String, dynamic>>('/subject/$subjectId'),
    );
    return NetabaSubjectHistory.fromJson(response.data ?? const {});
  }

  /// Recent score movers: rising / falling / finished.
  Future<NetabaTrending> _fetchTrending() async {
    final response = await _request(
      () => _dio.get<Map<String, dynamic>>('/trending'),
    );
    return NetabaTrending.fromJson(response.data ?? const {});
  }

  /// Long-term reputation gains ranking (开播以来评分提升).
  Future<List<NetabaTrendingItem>> _fetchScoreIncreases() async {
    final response = await _request(
      () => _dio.get<dynamic>('/score-increases'),
    );
    final data = response.data;
    if (data is List) {
      return [
        for (final item in data)
          if (item is Map)
            NetabaTrendingItem.fromJson(Map<String, dynamic>.from(item)),
      ];
    }
    if (data is Map) {
      final list = data['items'] ?? data['data'] ?? data['list'];
      if (list is List) {
        return [
          for (final item in list)
            if (item is Map)
              NetabaTrendingItem.fromJson(Map<String, dynamic>.from(item)),
        ];
      }
    }
    return const [];
  }

  Future<Response<T>> _request<T>(Future<Response<T>> Function() run) async {
    try {
      return await run();
    } on DioException catch (error) {
      final nested = error.error;
      if (nested is NetabaApiException) rethrow;
      throw DioException(
        requestOptions: error.requestOptions,
        response: error.response,
        type: error.type,
        error: NetabaApiException(
          nested?.toString() ?? error.message ?? '获取评分历史失败',
          statusCode: error.response?.statusCode,
        ),
      );
    }
  }
}

final netabaApiProvider = Provider<NetabaApi>((ref) => NetabaApi());
