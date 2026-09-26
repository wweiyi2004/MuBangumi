import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/auth/website_identity.dart';
import 'package:mubangumi/core/auth/website_session.dart';
import 'package:mubangumi/core/network/community_service.dart';
import 'package:mubangumi/core/network/pm_service.dart';
import 'package:mubangumi/models/bangumi_models.dart';

const signedInPage = '''
<html><head><title>Bangumi</title></head><body>
<div id="badgeUserPanel"><a class="avatar" href="/user/alice">Alice</a></div>
<div class="pm-conversation-list"></div>
<input name="formhash" value="fresh-hash">
<script src="/cdn-cgi/challenge-platform/scripts/jsd/api.js"></script>
</body></html>
''';
const alice = BangumiUser(
  id: 1,
  username: 'alice',
  nickname: 'Alice',
  avatarUrl: '',
);

class Store extends WebsiteSessionStore {
  final value = WebsiteSessionSnapshot(
    cookies: const [WebsiteCookie(name: 'chii_auth', value: 'fixture')],
    syncedAt: DateTime.now(),
    userAgent: 'Browser/fixture',
  ).withVerifiedUser(1);
  @override
  Future<WebsiteSessionSnapshot?> read() async => value;
}

Dio responding(
  String html, {
  int status = 200,
  Map<String, List<String>> headers = const {},
}) => Dio()
  ..interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) => handler.resolve(
        Response<String>(
          requestOptions: options,
          statusCode: status,
          data: html,
          headers: Headers.fromMap(headers),
        ),
      ),
    ),
  );

void main() {
  test(
    'explicit Cloudflare challenge header wins even over apparent normal HTML',
    () async {
      final failures = <WebsiteAccessStatus>[];
      final service =
          PmService(
              sessionStore: Store(),
              dio: responding(
                signedInPage,
                headers: {
                  'cf-mitigated': ['challenge'],
                },
              ),
            )
            ..onWebsiteSessionFailure = (status, _, {Uri? recoveryUri}) {
              failures.add(status);
              return true;
            };
      addTearDown(service.dispose);
      await expectLater(service.loadInbox(), throwsException);
      expect(failures, [WebsiteAccessStatus.challenge]);
    },
  );
  test(
    'actual challenge document is still recognized without response headers',
    () {
      expect(
        WebsiteIdentityProbe.isChallenge(
          '<html><title>Just a moment...</title><form id="challenge-form"></form><script src="/cdn-cgi/challenge-platform/h/g/orchestrate/chl_page/v1"></script></html>',
        ),
        isTrue,
      );
      expect(
        WebsiteIdentityProbe.isChallenge(
          '<html><title>Just a moment...</title><script>window._cf_chl_opt = {cType:"managed"};</script></html>',
        ),
        isTrue,
      );
    },
  );
  test(
    'challenge header on a 503 is distinguished from an unavailable origin',
    () async {
      await expectLater(
        WebsiteIdentityProbe(
          dio: responding(
            'challenge',
            status: 503,
            headers: {
              'cf-mitigated': ['challenge'],
            },
          ),
        ).verify(Store().value, alice),
        throwsA(
          isA<WebsiteAccessException>().having(
            (error) => error.status,
            'status',
            WebsiteAccessStatus.challenge,
          ),
        ),
      );
    },
  );
  for (final statusCode in [401, 403]) {
    for (final membership in [true, false]) {
      test(
        'NOT_ALLOWED $statusCode only uses website fallback for membership: $membership',
        () async {
          var htmlReads = 0, htmlWrites = 0, requests = 0;
          final api = Dio()
            ..interceptors.add(
              InterceptorsWrapper(
                onRequest: (options, handler) {
                  requests++;
                  handler.reject(
                    DioException(
                      requestOptions: options,
                      type: DioExceptionType.badResponse,
                      response: Response(
                        requestOptions: options,
                        statusCode: statusCode,
                        data: {
                          'code': 'NOT_ALLOWED',
                          'message': membership
                              ? "you don't have permission to create posts, join group first"
                              : "you don't have permission to create topic",
                        },
                      ),
                    ),
                  );
                },
              ),
            );
          final html = Dio()
            ..interceptors.add(
              InterceptorsWrapper(
                onRequest: (options, handler) {
                  if (options.method == 'POST') {
                    htmlWrites++;
                  } else {
                    htmlReads++;
                  }
                  handler.resolve(
                    Response<String>(
                      requestOptions: options,
                      statusCode: 200,
                      data: options.method == 'POST'
                          ? '{"id":42}'
                          : signedInPage,
                    ),
                  );
                },
              ),
            );
          final service = CommunityService.test(
            p1Dio: api,
            htmlDio: html,
            sessionStore: Store(),
          )..setAccessToken('fixture');
          addTearDown(service.dispose);
          final pending = service.createGroupTopic(
            slug: 'fixture',
            title: 't',
            content: 'b',
            turnstileToken: 'once',
          );
          if (membership) {
            await pending;
          } else {
            await expectLater(pending, throwsException);
          }
          expect(requests, 1);
          expect(htmlReads, membership ? 1 : 0);
          expect(htmlWrites, membership ? 1 : 0);
        },
      );
    }
  }
  test(
    'a returned topic form or unrelated topic links do not prove publication succeeded',
    () async {
      final api = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  type: DioExceptionType.badResponse,
                  response: Response(
                    requestOptions: options,
                    statusCode: 401,
                    data: {
                      'code': 'NOT_JOIN_PRIVATE_GROUP_ERROR',
                      'message': "join 'fixture'",
                    },
                  ),
                ),
              );
            },
          ),
        );
      final html = responding(
        '$signedInPage<form id="postTopic"></form><a href="/group/topic/99">other topic</a>',
      );
      final service = CommunityService.test(
        p1Dio: api,
        htmlDio: html,
        sessionStore: Store(),
      )..setAccessToken('fixture');
      addTearDown(service.dispose);
      await expectLater(
        service.createGroupTopic(
          slug: 'fixture',
          title: 't',
          content: 'b',
          turnstileToken: 'once',
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('结果未知'),
          ),
        ),
      );
    },
  );
  test('background JS detections on a signed-in page are not a challenge', () {
    expect(WebsiteIdentityProbe.isChallenge(signedInPage), isFalse);
  });
  test(
    'a normal guest page with background detection is not a challenge either',
    () {
      expect(
        WebsiteIdentityProbe.isChallenge(
          '<html><title>Bangumi</title><script src="/cdn-cgi/challenge-platform/scripts/jsd/main.js"></script></html>',
        ),
        isFalse,
      );
    },
  );
  test(
    'identity HTTP probe accepts real account navigation alongside JS detection',
    () async {
      expect(
        await WebsiteIdentityProbe(
          dio: responding(signedInPage),
        ).verify(Store().value, alice),
        1,
      );
    },
  );
  test(
    'inbox background detection does not revoke the verified account',
    () async {
      final failures = <WebsiteAccessStatus>[];
      final service =
          PmService(sessionStore: Store(), dio: responding(signedInPage))
            ..onWebsiteSessionFailure = (status, _, {Uri? recoveryUri}) {
              failures.add(status);
              return true;
            };
      addTearDown(service.dispose);
      expect(await service.loadInbox(), isEmpty);
      expect(failures, isEmpty);
    },
  );
  test(
    'classic group fallback accepts a verified form with background detection',
    () async {
      var writes = 0;
      final html = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              if (options.method == 'POST') writes++;
              handler.resolve(
                Response<String>(
                  requestOptions: options,
                  statusCode: 200,
                  data: options.method == 'POST' ? '{"id":42}' : signedInPage,
                ),
              );
            },
          ),
        );
      final api = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  type: DioExceptionType.badResponse,
                  response: Response(
                    requestOptions: options,
                    statusCode: 401,
                    data: {
                      'code': 'NOT_JOIN_PRIVATE_GROUP_ERROR',
                      'message': "join 'fixture'",
                    },
                  ),
                ),
              );
            },
          ),
        );
      final service = CommunityService.test(
        htmlDio: html,
        p1Dio: api,
        sessionStore: Store(),
      )..setAccessToken('fixture');
      addTearDown(service.dispose);
      await service.createGroupTopic(
        slug: 'fixture',
        title: 'title',
        content: 'body',
        turnstileToken: 'once',
      );
      expect(writes, 1);
    },
  );
  for (final unclassified in [
    <String, dynamic>{'message': 'wrong captcha'},
    'wrong captcha',
    <String, dynamic>{},
  ]) {
    test(
      'one-shot writes do not replay an unclassified 401: $unclassified',
      () async {
        var requests = 0, refreshes = 0;
        final dio = Dio()
          ..interceptors.add(
            InterceptorsWrapper(
              onRequest: (options, handler) {
                requests++;
                handler.reject(
                  DioException(
                    requestOptions: options,
                    type: DioExceptionType.badResponse,
                    response: Response(
                      requestOptions: options,
                      statusCode: 401,
                      data: unclassified,
                    ),
                  ),
                );
              },
            ),
          );
        final service = CommunityService.test(p1Dio: dio)
          ..setAccessToken('fixture');
        addTearDown(service.dispose);
        service.onUnauthorizedRefresh = () async {
          refreshes++;
          return true;
        };
        await expectLater(
          service.createGroupTopic(
            slug: 'fixture',
            title: 't',
            content: 'b',
            turnstileToken: 'once',
          ),
          throwsException,
        );
        expect(requests, 1);
        expect(refreshes, 0);
      },
    );
  }
  test(
    'official TOKEN_INVALID renews credentials before CAPTCHA is consumed',
    () async {
      var requests = 0, refreshes = 0;
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              requests++;
              if (requests == 1) {
                handler.reject(
                  DioException(
                    requestOptions: options,
                    type: DioExceptionType.badResponse,
                    response: Response(
                      requestOptions: options,
                      statusCode: 401,
                      data: {'code': 'TOKEN_INVALID'},
                    ),
                  ),
                );
              } else {
                expect(options.headers['Authorization'], 'Bearer renewed');
                handler.resolve(
                  Response(
                    requestOptions: options,
                    statusCode: 200,
                    data: {'id': 1},
                  ),
                );
              }
            },
          ),
        );
      final service = CommunityService.test(p1Dio: dio)..setAccessToken('old');
      addTearDown(service.dispose);
      service.onUnauthorizedRefresh = () async {
        refreshes++;
        service.setAccessToken('renewed');
        return true;
      };
      await service.createGroupTopic(
        slug: 'fixture',
        title: 't',
        content: 'b',
        turnstileToken: 'unused',
      );
      expect(requests, 2);
      expect(refreshes, 1);
    },
  );
  test(
    'group post cannot retry as a different account after credential refresh',
    () async {
      var requests = 0;
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              requests++;
              if (requests == 1) {
                handler.reject(
                  DioException(
                    requestOptions: options,
                    type: DioExceptionType.badResponse,
                    response: Response(
                      requestOptions: options,
                      statusCode: 401,
                      data: {'code': 'NEED_LOGIN'},
                    ),
                  ),
                );
              } else {
                handler.resolve(
                  Response(
                    requestOptions: options,
                    statusCode: 200,
                    data: {'id': 1},
                  ),
                );
              }
            },
          ),
        );
      final service = CommunityService.test(p1Dio: dio)
        ..setAccessToken('fixture')
        ..setCurrentUsername('alice');
      addTearDown(service.dispose);
      service.onUnauthorizedRefresh = () async {
        service.setCurrentUsername('bob');
        return true;
      };
      await expectLater(
        service.createGroupTopic(
          slug: 'fixture',
          title: 't',
          content: 'b',
          turnstileToken: 'unused',
        ),
        throwsFormatException,
      );
      expect(requests, 1);
    },
  );
}
