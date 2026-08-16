import 'package:dio/dio.dart';

import 'bangumi_endpoints.dart';
import 'bangumi_user_agent.dart';

class NetworkRouteProbeResult {
  const NetworkRouteProbeResult({
    required this.available,
    required this.elapsed,
    this.message = '',
  });

  final bool available;
  final Duration elapsed;
  final String message;

  String get summary {
    if (!available) return message.isEmpty ? '暂时不可用' : message;
    final milliseconds = elapsed.inMilliseconds;
    final quality = milliseconds < 600
        ? '畅通'
        : milliseconds < 1600
        ? '一般'
        : '较慢';
    return '$milliseconds ms · $quality';
  }
}

class BangumiRouteProbe {
  BangumiRouteProbe({Dio Function(BangumiNetworkRoute route)? dioFactory})
    : _dioFactory = dioFactory ?? _defaultDio;

  static final shared = BangumiRouteProbe();

  final Dio Function(BangumiNetworkRoute route) _dioFactory;
  final Map<BangumiNetworkRoute, _CachedProbe> _cache = {};

  Future<NetworkRouteProbeResult> probe(
    BangumiNetworkRoute route, {
    bool force = false,
  }) async {
    final cached = _cache[route];
    if (!force &&
        cached != null &&
        DateTime.now().difference(cached.createdAt) <
            const Duration(minutes: 2)) {
      return cached.result;
    }

    final stopwatch = Stopwatch()..start();
    try {
      final response = await _dioFactory(route).get<void>('/subjects/8');
      stopwatch.stop();
      final available =
          response.statusCode != null && response.statusCode! < 400;
      final result = NetworkRouteProbeResult(
        available: available,
        elapsed: stopwatch.elapsed,
        message: available ? '' : 'HTTP ${response.statusCode ?? 0}',
      );
      _cache[route] = _CachedProbe(result, DateTime.now());
      return result;
    } on DioException catch (error) {
      stopwatch.stop();
      final result = NetworkRouteProbeResult(
        available: false,
        elapsed: stopwatch.elapsed,
        message: _probeErrorMessage(error),
      );
      _cache[route] = _CachedProbe(result, DateTime.now());
      return result;
    }
  }

  static Dio _defaultDio(BangumiNetworkRoute route) => Dio(
    BaseOptions(
      baseUrl: route.apiBaseUrl,
      connectTimeout: const Duration(seconds: 6),
      receiveTimeout: const Duration(seconds: 10),
      headers: const {
        'Accept': 'application/json',
        'User-Agent': muBangumiUserAgent,
      },
    ),
  );

  static String _probeErrorMessage(DioException error) => switch (error.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout => '测速超时',
    DioExceptionType.connectionError => '无法连接',
    _ =>
      error.response?.statusCode == null
          ? '测速失败'
          : 'HTTP ${error.response!.statusCode}',
  };
}

class _CachedProbe {
  const _CachedProbe(this.result, this.createdAt);

  final NetworkRouteProbeResult result;
  final DateTime createdAt;
}
