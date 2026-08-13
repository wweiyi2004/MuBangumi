import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/auth/website_session.dart';
import 'package:mubangumi/core/network/pm_service.dart';
import 'package:mubangumi/models/pm_models.dart';

void main() {
  test('treats a 200 response that stays on the compose page as sent', () async {
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
  });

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

  test('throws when the website reports a failed submission off the compose page',
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
  });
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
