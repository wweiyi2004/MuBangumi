import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/auth/website_session.dart';
import 'package:mubangumi/core/network/pm_service.dart';
import 'package:mubangumi/models/pm_models.dart';

void main() {
  test('a lost POST response is uncertain rather than safe to retry', () async {
    final service = _service(
      (options) => throw DioException(
        requestOptions: options,
        type: DioExceptionType.receiveTimeout,
      ),
    );
    await expectLater(
      service.compose(
        params: const PmComposeParams(formhash: 'hash', msgReceivers: '42'),
        title: '标题',
        body: '内容',
      ),
      throwsA(isA<PmDeliveryUncertain>()),
    );
  });
  test('challenge-cookie refresh does not invalidate a prepared form', () async {
    final store = _MemoryWebsiteSessionStore()
      ..snapshot = _snapshot('account-a');
    var posts = 0;
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.method == 'POST') posts++;
            handler.resolve(
              Response<String>(
                requestOptions: options,
                statusCode: 200,
                data:
                    '<input name="formhash" value="hash"><input name="msg_receivers" value="alice">',
              ),
            );
          },
        ),
      );
    final service = PmService(sessionStore: store, dio: dio);
    final params = await service.loadComposeParams('alice');
    store.snapshot = WebsiteSessionSnapshot(
      cookies: [
        ...store.snapshot!.cookies,
        const WebsiteCookie(name: 'cf_clearance', value: 'new-challenge'),
      ],
      syncedAt: DateTime(2026),
    );
    await service.compose(params: params, title: 'title', body: 'body');
    expect(posts, 1);
  });

  for (final reply in [false, true]) {
    test(
      'a loaded ${reply ? 'reply' : 'compose'} form cannot be sent under a new website account',
      () async {
        final store = _MemoryWebsiteSessionStore()
          ..snapshot = _snapshot('account-a');
        var posts = 0;
        final dio = Dio()
          ..interceptors.add(
            InterceptorsWrapper(
              onRequest: (options, handler) {
                if (options.method == 'POST') posts++;
                handler.resolve(
                  Response<String>(
                    requestOptions: options,
                    statusCode: 200,
                    data:
                        '<input name="formhash" value="hash"><input name="msg_receivers" value="alice">',
                  ),
                );
              },
            ),
          );
        final service = PmService(sessionStore: store, dio: dio);
        final params = reply ? null : await service.loadComposeParams('alice');
        final detail = reply ? await service.loadConversation('chat') : null;
        store.snapshot = _snapshot('account-b');
        await expectLater(
          reply
              ? service.reply(form: detail!.form, body: 'private')
              : service.compose(
                  params: params!,
                  title: 'title',
                  body: 'private',
                ),
          throwsA(isA<PmAuthException>()),
        );
        expect(posts, 0);
      },
    );
  }

  test(
    'a private response that arrives after changing accounts is rejected',
    () async {
      final started = Completer<void>();
      final responseReady = Completer<void>();
      final store = _MemoryWebsiteSessionStore()
        ..snapshot = _snapshot('account-a');
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) async {
              started.complete();
              await responseReady.future;
              handler.resolve(
                Response<String>(
                  requestOptions: options,
                  statusCode: 200,
                  data:
                      '<input name="formhash" value="hash"><input name="msg_receivers" value="alice">',
                ),
              );
            },
          ),
        );
      final service = PmService(sessionStore: store, dio: dio);
      final load = service.loadComposeParams('alice');
      await started.future;
      store.snapshot = _snapshot('account-b');
      responseReady.complete();
      await expectLater(load, throwsA(isA<PmAuthException>()));
    },
  );

  test(
    'treats a 200 response that stays on the compose page as sent',
    () async {
      final service = _service(
        (options) => Response<String>(
          requestOptions: options,
          statusCode: 200,
          data: '''
<html><body>
<form><input name="formhash" value="hash"><textarea name="msg_body"></textarea></form>
</body></html>
''',
        ),
      );

      await service.compose(
        params: const PmComposeParams(formhash: 'hash', msgReceivers: '42'),
        title: '标题',
        body: '内容',
      );
    },
  );

  test('does not report a keyword-free success notice as a failure', () async {
    final service = _service(
      (options) => Response<String>(
        requestOptions: options,
        statusCode: 200,
        data: '<div id="colunmNotice"><div class="text">短信已发送</div></div>',
      ),
    );

    await service.compose(
      params: const PmComposeParams(formhash: 'hash', msgReceivers: '42'),
      title: '标题',
      body: '内容',
    );
  });

  test(
    'throws when the website reports a failed submission off the compose page',
    () async {
      final service = _service(
        (options) => Response<String>(
          requestOptions: options,
          statusCode: 200,
          data:
              '<div id="colunmNotice"><div class="text">发送未成功，请稍后重试</div></div>',
          // Simulate the response landing on a page other than /pm/create.chii.
          redirects: [
            RedirectRecord(
              302,
              'POST',
              Uri.parse('https://bgm.tv/pm/inbox.chii'),
            ),
          ],
        ),
      );

      await expectLater(
        service.compose(
          params: const PmComposeParams(formhash: 'hash', msgReceivers: '42'),
          title: '标题',
          body: '内容',
        ),
        throwsA(
          isA<PmException>().having(
            (error) => error.message,
            'message',
            contains('发送未成功'),
          ),
        ),
      );
    },
  );
}

PmService _service(Response<String> Function(RequestOptions) respond) {
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) => handler.resolve(respond(options)),
    ),
  );
  return PmService(
    sessionStore: _MemoryWebsiteSessionStore()
      ..snapshot = WebsiteSessionSnapshot(
        cookies: [WebsiteCookie(name: 'chii_cvlet_session', value: 'token')],
        syncedAt: DateTime.now(),
      ),
    dio: dio,
  );
}

class _MemoryWebsiteSessionStore extends WebsiteSessionStore {
  WebsiteSessionSnapshot? snapshot;

  @override
  Future<WebsiteSessionSnapshot?> read() async => snapshot;

  @override
  Future<void> write(WebsiteSessionSnapshot snapshot) async {
    this.snapshot = snapshot;
  }

  @override
  Future<void> clear() async {
    snapshot = null;
  }
}

WebsiteSessionSnapshot _snapshot(String account) => WebsiteSessionSnapshot(
  cookies: [WebsiteCookie(name: 'chii_auth', value: account)],
  syncedAt: DateTime(2026),
);
