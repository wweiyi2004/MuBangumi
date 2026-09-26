import 'package:dio/dio.dart';
import '../diagnostics/account_diagnostics.dart';

class AccountDiagnosticsInterceptor extends Interceptor {
  AccountDiagnosticsInterceptor(this.diagnostics, this.area);
  final AccountDiagnostics diagnostics;
  final AccountArea area;
  final _requests = Expando<({int id, Stopwatch watch})>();
  AccountMethod _method(String value) => switch (value.toUpperCase()) {
    'GET' => AccountMethod.get,
    'POST' => AccountMethod.post,
    'PUT' => AccountMethod.put,
    'PATCH' => AccountMethod.patch,
    'DELETE' => AccountMethod.delete,
    _ => AccountMethod.other,
  };
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final id = diagnostics.nextRequest();
    _requests[options] = (id: id, watch: Stopwatch()..start());
    diagnostics.record(
      area,
      AccountEvent.requestStarted,
      request: id,
      method: _method(options.method),
    );
    handler.next(options);
  }

  void _finish(RequestOptions options, int? status, bool failed) {
    final request = _requests[options];
    diagnostics.record(
      area,
      failed ? AccountEvent.requestFailed : AccountEvent.requestSucceeded,
      request: request?.id,
      method: _method(options.method),
      status: status,
      elapsedMs: request?.watch.elapsedMilliseconds,
    );
    _requests[options] = null;
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    _finish(
      response.requestOptions,
      response.statusCode,
      (response.statusCode ?? 0) >= 400,
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _finish(err.requestOptions, err.response?.statusCode, true);
    handler.next(err);
  }
}
