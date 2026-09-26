import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/auth/website_identity.dart';
import 'package:mubangumi/core/network/community_service.dart';
import 'package:mubangumi/core/network/pm_service.dart';
import 'package:mubangumi/models/community_models.dart';
import 'package:mubangumi/models/pm_models.dart';
import 'support/pm_fixtures.dart';

const topic = CommunityTopic(
  id: 42,
  kind: CommunityTopicKind.group,
  title: 'fixture',
  url: 'https://bgm.tv/group/topic/42',
  webUrl: 'https://bgm.tv/group/topic/42',
);

void main() {
  for (final status in [307, 308]) {
    test(
      'PM $status is not a delivery receipt and never replays the POST',
      () async {
        var requests = 0;
        final dio = Dio()
          ..interceptors.add(
            InterceptorsWrapper(
              onRequest: (request, handler) {
                requests++;
                expect(request.followRedirects, false);
                handler.resolve(
                  Response<String>(
                    requestOptions: request,
                    statusCode: status,
                    data: '',
                    headers: Headers.fromMap({
                      'location': ['/pm/inbox.chii'],
                    }),
                  ),
                );
              },
            ),
          );
        final service = PmService(dio: dio, sessionStore: PmTestWebsiteStore());
        addTearDown(service.dispose);
        await expectLater(
          service.compose(
            params: const PmComposeParams(formhash: 'hash', msgReceivers: '2'),
            title: 'title',
            body: 'body',
          ),
          throwsA(isA<PmDeliveryUncertain>()),
        );
        expect(requests, 1);
      },
    );
  }
  for (final create in [false, true]) {
    for (final phase in ['form', 'submission']) {
      test(
        'group ${create ? 'topic' : 'reply'} rejects website account change at $phase',
        () async {
          final store = PmTestWebsiteStore();
          var posts = 0;
          final service = groupService(store, (request) {
            final post = request.method == 'POST';
            if (post) posts++;
            if ((phase == 'form') != post) store.account = 'account-b';
            return Response<String>(
              requestOptions: request,
              statusCode: 200,
              data: post
                  ? '{"id":42,"posts":"<div>reply</div>"}'
                  : '<input name="formhash" value="abcdefgh">',
            );
          });
          await expectLater(
            submit(service, create),
            throwsA(isA<FormatException>()),
          );
          expect(posts, phase == 'form' ? 0 : 1);
        },
      );
    }
    test(
      'group form HTTP error cannot authorize ${create ? 'topic' : 'reply'} POST',
      () async {
        var posts = 0;
        final service = groupService(PmTestWebsiteStore(), (request) {
          if (request.method == 'POST') posts++;
          return Response<String>(
            requestOptions: request,
            statusCode: request.method == 'GET' ? 403 : 200,
            data: request.method == 'GET'
                ? '<input name="formhash" value="abcdefgh">'
                : '{"id":42,"posts":"reply"}',
          );
        });
        await expectLater(
          submit(service, create),
          throwsA(isA<FormatException>()),
        );
        expect(posts, 0);
      },
    );
    test(
      'group login redirect revokes login before ${create ? 'topic' : 'reply'} POST',
      () async {
        final failures = <WebsiteAccessStatus>[];
        final service =
            groupService(
                PmTestWebsiteStore(),
                (request) => Response<String>(
                  requestOptions: request,
                  statusCode: 302,
                  data: '',
                  headers: Headers.fromMap({
                    'location': ['/login?back=group'],
                  }),
                ),
              )
              ..onWebsiteSessionFailure = (status, _, {recoveryUri}) {
                failures.add(status);
                return true;
              };
        await expectLater(
          submit(service, create),
          throwsA(isA<WebsiteAccessException>()),
        );
        expect(failures, [WebsiteAccessStatus.expired]);
      },
    );
  }
  for (final status in [400, 403, 404, 429, 503]) {
    test('reply success marker cannot override HTTP $status', () async {
      var posts = 0;
      final service = groupService(PmTestWebsiteStore(), (request) {
        if (request.method == 'POST') posts++;
        return Response<String>(
          requestOptions: request,
          statusCode: request.method == 'GET' ? 200 : status,
          data: request.method == 'GET'
              ? '<input name="formhash" value="abcdefgh">'
              : '{"posts":"reply"}',
        );
      });
      await expectLater(
        submit(service, false),
        throwsA(isA<FormatException>()),
      );
      expect(posts, 1);
    });
  }
  for (final marker in ['null', 'false', '""', '[]']) {
    test('an empty posts marker $marker is not a reply receipt', () async {
      final service = groupService(
        PmTestWebsiteStore(),
        (request) => Response<String>(
          requestOptions: request,
          statusCode: 200,
          data: request.method == 'GET'
              ? '<input name="formhash" value="abcdefgh">'
              : '{"posts":$marker}',
        ),
      );
      await expectLater(
        submit(service, false),
        throwsA(isA<FormatException>()),
      );
    });
  }
  test(
    'PM POST keeps redirect receipt without following or replaying the body',
    () async {
      RequestOptions? sent;
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (request, handler) {
              sent = request;
              handler.resolve(
                Response<String>(
                  requestOptions: request,
                  statusCode: 302,
                  data: '',
                  headers: Headers.fromMap({
                    'location': ['/pm/inbox.chii'],
                  }),
                ),
              );
            },
          ),
        );
      final service = PmService(dio: dio, sessionStore: PmTestWebsiteStore());
      addTearDown(service.dispose);
      await service.compose(
        params: const PmComposeParams(formhash: 'hash', msgReceivers: '2'),
        title: 'title',
        body: 'body',
      );
      expect(sent!.followRedirects, false);
    },
  );
  test('PM POST login redirect is an authentication failure', () async {
    final failures = <WebsiteAccessStatus>[];
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) {
            handler.resolve(
              Response<String>(
                requestOptions: request,
                statusCode: 302,
                data: '',
                headers: Headers.fromMap({
                  'location': ['/login?back=pm'],
                }),
              ),
            );
          },
        ),
      );
    final service = PmService(dio: dio, sessionStore: PmTestWebsiteStore())
      ..onWebsiteSessionFailure = (status, _, {recoveryUri}) {
        failures.add(status);
        return true;
      };
    addTearDown(service.dispose);
    await expectLater(
      service.compose(
        params: const PmComposeParams(formhash: 'hash', msgReceivers: '2'),
        title: 'title',
        body: 'body',
      ),
      throwsA(isA<PmAuthException>()),
    );
    expect(failures, [WebsiteAccessStatus.expired]);
  });
}

Future<Object?> submit(CommunityService service, bool create) => create
    ? service.createGroupTopic(
        slug: 'demo',
        title: 'title',
        content: 'body',
        turnstileToken: 'once',
      )
    : service.replyToTopic(
        topic: topic,
        content: 'body',
        turnstileToken: 'once',
      );

CommunityService groupService(
  PmTestWebsiteStore store,
  Response<String> Function(RequestOptions) respond,
) {
  final api = Dio()
    ..interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          handler.reject(
            DioException(
              requestOptions: request,
              type: DioExceptionType.badResponse,
              response: Response<Object?>(
                requestOptions: request,
                statusCode: 403,
                data: {'code': 'NOT_ALLOWED', 'message': 'join group first'},
              ),
            ),
          );
        },
      ),
    );
  final html = Dio(BaseOptions(baseUrl: 'https://bgm.tv'))
    ..interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) => handler.resolve(respond(request)),
      ),
    );
  final service =
      CommunityService.test(p1Dio: api, htmlDio: html, sessionStore: store)
        ..setCurrentUsername('alice')
        ..setAccessToken('fixture');
  addTearDown(service.dispose);
  return service;
}
