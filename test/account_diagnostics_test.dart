import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/diagnostics/account_diagnostics.dart';
import 'package:mubangumi/core/network/account_diagnostics_interceptor.dart';
import 'package:mubangumi/core/network/community_write_client.dart';

class Adapter implements HttpClientAdapter {
  Adapter(this.respond);
  final ResponseBody Function(RequestOptions) respond;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? body,
    Future<void>? cancel,
  ) async => respond(options);
  @override
  void close({bool force = false}) {}
}

void main() {
  test(
    'diagnostic export excludes all request data and arbitrary version strings',
    () async {
      final diagnostics = AccountDiagnostics();
      final dio =
          Dio(BaseOptions(baseUrl: 'https://example.test/private-account/'))
            ..httpClientAdapter = Adapter(
              (_) => ResponseBody.fromString('private response body', 403),
            )
            ..interceptors.add(
              AccountDiagnosticsInterceptor(
                diagnostics,
                AccountArea.privateMessages,
              ),
            );
      addTearDown(() => dio.close(force: true));
      await expectLater(
        dio.post(
          'private-thread',
          data: 'private message',
          options: Options(
            headers: {
              'Cookie': 'secret-cookie',
              'Authorization': 'secret-token',
            },
          ),
        ),
        throwsA(isA<DioException>()),
      );
      diagnostics.observeBrowser('private-device-name Chrome/144.0.0.0');
      final output = diagnostics.exportJson(
        platform: 'windows',
        version: 'secret-token',
        build: 'private-user',
        patch: 3,
        apiSignedIn: true,
        websiteState: 6,
      );
      for (final secret in [
        'private-account',
        'private-thread',
        'private response',
        'private message',
        'secret-cookie',
        'secret-token',
        'private-user',
        'private-device-name',
      ]) {
        expect(output, isNot(contains(secret)));
      }
      final decoded = jsonDecode(output) as Map;
      expect(decoded['version'], 'unknown');
      expect(decoded['webview_major'], 144);
      expect((decoded['events'] as List).last['http_status'], 403);
      expect((decoded['events'] as List).last['event'], 'requestFailed');
    },
  );
  test('diagnostics are bounded and clear the browser fingerprint', () {
    final diagnostics = AccountDiagnostics(capacity: 3);
    for (var i = 0; i < 10; i++) {
      diagnostics.record(
        AccountArea.website,
        AccountEvent.stateChanged,
        generation: i,
      );
    }
    expect(diagnostics.events.map((e) => e['generation']), [7, 8, 9]);
    diagnostics.observeBrowser('Chrome/144.0');
    diagnostics.clear();
    expect(diagnostics.events, isEmpty);
    expect(diagnostics.webViewMajor, isNull);
  });
  for (final method in ['POST', 'PUT', 'PATCH', 'DELETE']) {
    for (final changed in [false, true]) {
      test('$method shared guard, account changed: $changed', () async {
        var identity = 1, calls = 0, refreshes = 0;
        final dio = Dio(BaseOptions(baseUrl: 'https://next.bgm.tv'))
          ..httpClientAdapter = Adapter(
            (_) => ResponseBody.fromString(
              ++calls == 1 ? '{"code":"TOKEN_INVALID"}' : '{}',
              calls == 1 ? 401 : 200,
              headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
              },
            ),
          );
        addTearDown(() => dio.close(force: true));
        final client = CommunityWriteClient(
          dio: dio,
          readIdentity: () => identity,
          isAuthenticated: () => true,
          refresh: () async {
            refreshes++;
            if (changed) identity++;
            return true;
          },
          diagnostics: AccountDiagnostics(),
        );
        if (changed) {
          await expectLater(
            client.send(method, '/fixture'),
            throwsFormatException,
          );
        } else {
          await client.send(method, '/fixture');
        }
        expect(calls, changed ? 1 : 2);
        expect(refreshes, 1);
      });
    }
  }
  test(
    'shared write client never retries uncertain or CAPTCHA-rejected POSTs',
    () async {
      for (final status in [401, 503]) {
        var requests = 0, refreshes = 0;
        final dio = Dio(BaseOptions(baseUrl: 'https://next.bgm.tv'))
          ..httpClientAdapter = Adapter((_) {
            requests++;
            return ResponseBody.fromString(
              '{"code":"CAPTCHA_ERROR"}',
              status,
              headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
              },
            );
          });
        final client = CommunityWriteClient(
          dio: dio,
          readIdentity: () => 1,
          isAuthenticated: () => true,
          refresh: () async {
            refreshes++;
            return true;
          },
          diagnostics: AccountDiagnostics(),
        );
        await expectLater(
          client.send(
            'POST',
            '/fixture',
            data: {'turnstileToken': 'single-use'},
          ),
          throwsA(isA<DioException>()),
        );
        expect(requests, 1);
        expect(refreshes, 0);
        dio.close(force: true);
      }
    },
  );
}
