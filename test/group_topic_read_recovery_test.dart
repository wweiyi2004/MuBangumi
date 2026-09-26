import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/auth/website_identity.dart';
import 'package:mubangumi/core/network/community_service.dart';
import 'package:mubangumi/models/community_models.dart';
import 'support/pm_fixtures.dart';

const topic = CommunityTopic(
  id: 42,
  kind: CommunityTopicKind.group,
  title: 'topic',
  url: '',
  webUrl: 'https://untrusted.invalid/group/topic/42',
);
const login =
    '<form id="loginForm" action="/login"><input type="password"></form>';
const body =
    '<div class="postTopic"><div class="topic_content">private fixture body</div></div>';

void main() {
  for (final result in ['body', 'login', 'empty']) {
    test(
      'group HTML fallback uses verified cookies and handles $result',
      () async {
        final api = Dio()
          ..interceptors.add(
            InterceptorsWrapper(
              onRequest: (options, handler) => handler.reject(
                DioException(
                  requestOptions: options,
                  type: DioExceptionType.badResponse,
                  response: Response(requestOptions: options, statusCode: 403),
                ),
              ),
            ),
          );
        final reads = <RequestOptions>[];
        final html = Dio(BaseOptions(baseUrl: 'https://bgm.tv'))
          ..interceptors.add(
            InterceptorsWrapper(
              onRequest: (options, handler) {
                reads.add(options);
                handler.resolve(
                  Response<String>(
                    requestOptions: options,
                    statusCode: 200,
                    data: options.headers['Cookie'] == null
                        ? login
                        : result == 'body'
                        ? body
                        : result == 'login'
                        ? login
                        : '<p>not available</p>',
                  ),
                );
              },
            ),
          );
        final service =
            CommunityService.test(
                p1Dio: api,
                htmlDio: html,
                sessionStore: PmTestWebsiteStore(),
              )
              ..setAccessToken('fixture')
              ..setCurrentUsername('alice');
        addTearDown(service.dispose);
        final pending = service.loadTopic(topic);
        if (result == 'body') {
          expect((await pending).posts.single.body, 'private fixture body');
        } else if (result == 'login') {
          await expectLater(
            pending,
            throwsA(
              isA<WebsiteAccessException>().having(
                (e) => e.status,
                'status',
                WebsiteAccessStatus.expired,
              ),
            ),
          );
        } else {
          await expectLater(pending, throwsA(isA<FormatException>()));
        }
        expect(reads, hasLength(2));
        expect(
          reads.every(
            (r) => r.uri.host == 'bgm.tv' && r.uri.path == '/group/topic/42',
          ),
          true,
        );
        expect(reads.last.headers['Cookie'], contains('chii_auth=account-a'));
      },
    );
  }

  test(
    'an account change cannot turn an old API response into a new-account HTML read',
    () async {
      final release = Completer<void>();
      final started = Completer<void>();
      var htmlReads = 0;
      final api = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) async {
              started.complete();
              await release.future;
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {'replies': []},
                ),
              );
            },
          ),
        );
      final html = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              htmlReads++;
              handler.resolve(
                Response<String>(
                  requestOptions: options,
                  statusCode: 200,
                  data: body,
                ),
              );
            },
          ),
        );
      final service = CommunityService.test(p1Dio: api, htmlDio: html)
        ..setAccessToken('fixture')
        ..setCurrentUsername('alice');
      addTearDown(service.dispose);
      final pending = service.loadTopic(topic);
      await started.future;
      service.setCurrentUsername('bob');
      final assertion = expectLater(pending, throwsA(isA<FormatException>()));
      release.complete();
      await assertion;
      expect(htmlReads, 0);
    },
  );
}
