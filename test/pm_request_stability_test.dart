import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/auth/website_identity.dart';
import 'package:mubangumi/core/auth/website_session.dart';
import 'package:mubangumi/core/network/pm_service.dart';
import 'package:mubangumi/models/pm_models.dart';
import 'package:mubangumi/state/pm_mailbox_controller.dart';

const _mailbox = '<div class="pm-conversation-list"></div>';

class _Store extends WebsiteSessionStore {
  WebsiteSessionSnapshot value = WebsiteSessionSnapshot(
    cookies: const [WebsiteCookie(name: 'chii_auth', value: 'fixture')],
    syncedAt: DateTime(2026),
  ).withVerifiedUser(1);
  @override
  Future<WebsiteSessionSnapshot?> read() async => value;
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
  final FutureOr<ResponseBody> Function(RequestOptions, int) respond;
  int calls = 0;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) async => respond(options, ++calls);
  @override
  void close({bool force = false}) {}
}

ResponseBody _response(
  String body, {
  int status = 200,
  Map<String, List<String>> headers = const {},
}) => ResponseBody.fromString(
  body,
  status,
  headers: {
    'content-type': ['text/html; charset=utf-8'],
    ...headers,
  },
);

void main() {
  for (final type in [
    DioExceptionType.connectionError,
    DioExceptionType.receiveTimeout,
  ]) {
    test('a transient $type retries GET once', () async {
      final adapter = _Adapter((options, count) {
        if (count == 1) throw DioException(requestOptions: options, type: type);
        return _response(_mailbox);
      });
      final service = PmService(
        sessionStore: _Store(),
        dio: Dio()..httpClientAdapter = adapter,
        retryDelay: (_) async {},
      );
      addTearDown(service.dispose);
      expect(await service.loadInbox(), isEmpty);
      expect(adapter.calls, 2);
    });
  }

  test(
    'persistent gateway failures stop after one retry and keep existing messages',
    () async {
      var failing = false;
      final adapter = _Adapter(
        (_, _) => failing
            ? _response('unavailable', status: 502)
            : _response(
                '<a class="pm-conversation-item" href="/pm/conversation/42.chii"><span class="pm-conversation-name">Alice</span></a>',
              ),
      );
      final failures = <WebsiteAccessStatus>[];
      final service =
          PmService(
              sessionStore: _Store(),
              dio: Dio()..httpClientAdapter = adapter,
              retryDelay: (_) async {},
            )
            ..onWebsiteSessionFailure = (status, _, {Uri? recoveryUri}) {
              failures.add(status);
              return true;
            };
      addTearDown(service.dispose);
      final box = PmMailboxController(service.loadInbox);
      addTearDown(box.dispose);
      await box.refresh();
      failing = true;
      await box.refresh();
      expect(adapter.calls, 3);
      expect(box.items.single.id, '42');
      expect(box.error, contains('502'));
      expect(box.needAuth, false);
      expect(failures, isEmpty);
    },
  );

  for (final kind in ['seconds', 'date', 'invalid']) {
    test(
      '429 $kind Retry-After pauses both mailbox reads without revoking login',
      () async {
        var now = DateTime.utc(2026, 9, 21);
        final retryAfter = kind == 'seconds'
            ? '10'
            : kind == 'date'
            ? HttpDate.format(now.add(const Duration(seconds: 10)))
            : 'unknown';
        final adapter = _Adapter(
          (_, count) => count == 1
              ? _response(
                  'too many requests',
                  status: 429,
                  headers: {
                    'retry-after': [retryAfter],
                  },
                )
              : _response(_mailbox),
        );
        final failures = <WebsiteAccessStatus>[];
        final service =
            PmService(
                sessionStore: _Store(),
                dio: Dio()..httpClientAdapter = adapter,
                now: () => now,
                retryDelay: (_) async {},
              )
              ..onWebsiteSessionFailure = (status, _, {Uri? recoveryUri}) {
                failures.add(status);
                return true;
              };
        addTearDown(service.dispose);
        await expectLater(service.loadInbox(), throwsA(isA<PmException>()));
        await expectLater(service.loadOutbox(), throwsA(isA<PmException>()));
        expect(adapter.calls, 1);
        expect(failures, isEmpty);
        now = now.add(Duration(seconds: kind == 'invalid' ? 31 : 11));
        expect(await service.loadOutbox(), isEmpty);
        expect(adapter.calls, 2);
      },
    );
  }

  test('503 with Retry-After is not immediately retried', () async {
    final adapter = _Adapter(
      (_, _) => _response(
        'unavailable',
        status: 503,
        headers: {
          'retry-after': ['60'],
        },
      ),
    );
    final service = PmService(
      sessionStore: _Store(),
      dio: Dio()..httpClientAdapter = adapter,
      retryDelay: (_) async {
        fail('must respect cooldown');
      },
    );
    addTearDown(service.dispose);
    await expectLater(service.loadInbox(), throwsA(isA<PmException>()));
    expect(adapter.calls, 1);
  });

  test('account change during backoff prevents the retry', () async {
    final store = _Store();
    final adapter = _Adapter((_, _) => _response('unavailable', status: 502));
    final service = PmService(
      sessionStore: store,
      dio: Dio()..httpClientAdapter = adapter,
      retryDelay: (_) async {
        store.value = WebsiteSessionSnapshot(
          cookies: const [WebsiteCookie(name: 'chii_auth', value: 'different')],
          syncedAt: DateTime.now(),
        ).withVerifiedUser(2);
      },
    );
    addTearDown(service.dispose);
    await expectLater(service.loadInbox(), throwsA(isA<PmAuthException>()));
    expect(adapter.calls, 1);
  });

  test('real 401 still revokes login and is never retried', () async {
    final failures = <WebsiteAccessStatus>[];
    final adapter = _Adapter(
      (_, _) => _response('login required', status: 401),
    );
    final service =
        PmService(
            sessionStore: _Store(),
            dio: Dio()..httpClientAdapter = adapter,
            retryDelay: (_) async {
              fail('must not retry login rejection');
            },
          )
          ..onWebsiteSessionFailure = (status, _, {Uri? recoveryUri}) {
            failures.add(status);
            return true;
          };
    addTearDown(service.dispose);
    await expectLater(service.loadInbox(), throwsA(isA<PmAuthException>()));
    expect(adapter.calls, 1);
    expect(failures, [WebsiteAccessStatus.expired]);
  });

  for (final lostResponse in [false, true]) {
    test(
      'POST network failure is uncertain and never retried (lost: $lostResponse)',
      () async {
        final adapter = _Adapter((options, _) {
          if (lostResponse) {
            throw DioException(
              requestOptions: options,
              type: DioExceptionType.receiveTimeout,
            );
          }
          return _response('Bad Gateway', status: 502);
        });
        final service = PmService(
          sessionStore: _Store(),
          dio: Dio()..httpClientAdapter = adapter,
        );
        addTearDown(service.dispose);
        await expectLater(
          service.compose(
            params: const PmComposeParams(formhash: 'hash', msgReceivers: '42'),
            title: 'fixture',
            body: 'fixture',
          ),
          throwsA(isA<PmDeliveryUncertain>()),
        );
        expect(adapter.calls, 1);
      },
    );
  }

  test('post-send refresh cannot join a read from before the send', () async {
    final oldRead = Completer<ResponseBody>();
    final started = Completer<void>();
    final adapter = _Adapter((options, count) {
      if (count == 1) {
        started.complete();
        return oldRead.future;
      }
      return _response(
        options.method == 'POST'
            ? '<div id="colunmNotice"><div class="text">短信已发送</div></div>'
            : _mailbox,
      );
    });
    final service = PmService(
      sessionStore: _Store(),
      dio: Dio()..httpClientAdapter = adapter,
    );
    addTearDown(service.dispose);
    final initial = service.loadInbox();
    await started.future;
    await service.compose(
      params: const PmComposeParams(formhash: 'hash', msgReceivers: '42'),
      title: 'fixture',
      body: 'fixture',
    );
    final refreshed = service.loadInbox();
    await Future<void>.delayed(Duration.zero);
    oldRead.complete(_response(_mailbox));
    await Future.wait([initial, refreshed]);
    expect(adapter.calls, 3);
  });

  test(
    'an unknown conversation document is a recoverable load error',
    () async {
      final adapter = _Adapter((_, _) => _response('<html>unavailable</html>'));
      final service = PmService(
        sessionStore: _Store(),
        dio: Dio()..httpClientAdapter = adapter,
      );
      addTearDown(service.dispose);
      await expectLater(
        service.loadConversation('42'),
        throwsA(isA<PmException>()),
      );
    },
  );

  test('overlapping reads of the same mailbox share one request', () async {
    final ready = Completer<ResponseBody>();
    final started = Completer<void>();
    final adapter = _Adapter((_, count) {
      if (count == 1) started.complete();
      return ready.future;
    });
    final service = PmService(
      sessionStore: _Store(),
      dio: Dio()..httpClientAdapter = adapter,
    );
    addTearDown(service.dispose);
    final first = service.loadInbox();
    await started.future;
    final second = service.loadInbox();
    await Future<void>.delayed(Duration.zero);
    ready.complete(_response(_mailbox));
    await Future.wait([first, second]);
    expect(adapter.calls, 1);
  });

  test(
    'a temporary 502 retries the read once without requesting login',
    () async {
      final adapter = _Adapter(
        (_, count) => count == 1
            ? _response('Bad Gateway', status: 502)
            : _response(_mailbox),
      );
      final service = PmService(
        sessionStore: _Store(),
        dio: Dio()..httpClientAdapter = adapter,
      );
      addTearDown(service.dispose);
      expect(await service.loadInbox(), isEmpty);
      expect(adapter.calls, 2);
    },
  );

  test('an HTTP 200 error page is not an empty mailbox', () async {
    final adapter = _Adapter(
      (_, _) => _response(
        '<html><title>Temporarily unavailable</title>Retry later</html>',
      ),
    );
    final service = PmService(
      sessionStore: _Store(),
      dio: Dio()..httpClientAdapter = adapter,
    );
    addTearDown(service.dispose);
    await expectLater(
      service.loadInbox(),
      throwsA(
        isA<PmException>().having(
          (e) => e is PmAuthException,
          'requires login',
          false,
        ),
      ),
    );
  });

  test('a real 503 challenge is classified through the HTTP adapter', () async {
    final failures = <WebsiteAccessStatus>[];
    final adapter = _Adapter(
      (_, _) => _response(
        'challenge',
        status: 503,
        headers: {
          'cf-mitigated': ['challenge'],
        },
      ),
    );
    final service =
        PmService(
            sessionStore: _Store(),
            dio: Dio()..httpClientAdapter = adapter,
          )
          ..onWebsiteSessionFailure = (status, _, {Uri? recoveryUri}) {
            failures.add(status);
            return true;
          };
    addTearDown(service.dispose);
    await expectLater(service.loadInbox(), throwsA(isA<PmAuthException>()));
    expect(adapter.calls, 2);
    expect(failures, [WebsiteAccessStatus.challenge]);
  });
}
