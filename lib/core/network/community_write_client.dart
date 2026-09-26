import 'package:dio/dio.dart';
import '../diagnostics/account_diagnostics.dart';

/// One account guard and one credential retry for every P1 write verb. Domain
/// rejection, CAPTCHA failures and uncertain network outcomes are never retried.
class CommunityWriteClient {
  CommunityWriteClient({
    required this.dio,
    required this.readIdentity,
    required this.isAuthenticated,
    required this.refresh,
    required this.diagnostics,
  });
  final Dio dio;
  final int Function() readIdentity;
  final bool Function() isAuthenticated;
  final Future<bool> Function() refresh;
  final AccountDiagnostics diagnostics;

  Future<Object?> send(
    String method,
    String path, {
    Map<String, dynamic> data = const {},
  }) async {
    final identity = readIdentity();
    void guard() {
      if (identity != readIdentity() || !isAuthenticated()) {
        diagnostics.record(
          AccountArea.communityApi,
          AccountEvent.requestDiscarded,
          generation: identity,
        );
        throw const FormatException('登录账号已变化，请重新操作');
      }
    }

    for (var attempt = 0; attempt < 2; attempt++) {
      guard();
      try {
        final response = await dio.request<Object?>(
          '/p1$path',
          data: method == 'DELETE' ? null : data,
          options: Options(
            method: method,
            contentType: Headers.jsonContentType,
            headers: const {'Accept': 'application/json'},
            validateStatus: (s) => s != null && s >= 200 && s < 300,
          ),
        );
        guard();
        return response.data;
      } on DioException catch (error) {
        guard();
        if (attempt != 0 ||
            !isCredentialFailure(
              error,
              oneShot: data.containsKey('turnstileToken'),
            )) {
          rethrow;
        }
        diagnostics.record(
          AccountArea.communityApi,
          AccountEvent.credentialRefresh,
          generation: identity,
          attempt: 1,
        );
        final refreshed = await refresh();
        guard();
        if (!refreshed) rethrow;
      }
    }
    throw const FormatException('未能完成请求，请重新操作');
  }

  static bool isCredentialFailure(DioException error, {bool oneShot = false}) {
    if (error.response?.statusCode != 401) return false;
    final data = error.response?.data;
    if (data is! Map) return !oneShot;
    final code = data['code']?.toString();
    return (code == null && !oneShot) ||
        const {
          'TOKEN_INVALID',
          'NEED_LOGIN',
          'AUTHORIZATION_INVALID',
        }.contains(code);
  }
}
