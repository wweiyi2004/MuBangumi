import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/diagnostics/account_diagnostics.dart';
import 'package:mubangumi/core/network/community_service.dart';
import 'package:mubangumi/core/network/community_write_client.dart';

Dio fakeDio(FutureOr<Object?> Function(RequestOptions) respond) =>
    Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) async {
            try {
              handler.resolve(
                Response<Object?>(
                  requestOptions: request,
                  statusCode: 200,
                  data: await respond(request),
                ),
              );
            } on DioException catch (error) {
              handler.reject(error);
            }
          },
        ),
      );

void main() {
  for (final method in ['POST', 'PUT', 'PATCH', 'DELETE']) {
    for (final switchDuringRefresh in [false, true]) {
      test(
        '$method refresh respects account ownership (switch: $switchDuringRefresh)',
        () async {
          var identity = 1;
          var requests = 0;
          final dio = fakeDio((request) {
            if (++requests == 1) {
              throw DioException(
                requestOptions: request,
                type: DioExceptionType.badResponse,
                response: Response<Object?>(
                  requestOptions: request,
                  statusCode: 401,
                  data: {'code': 'TOKEN_INVALID'},
                ),
              );
            }
            return {'id': 42};
          });
          addTearDown(() => dio.close(force: true));
          final client = CommunityWriteClient(
            dio: dio,
            readIdentity: () => identity,
            isAuthenticated: () => true,
            refresh: () async {
              if (switchDuringRefresh) identity++;
              return true;
            },
            diagnostics: AccountDiagnostics(),
          );
          final pending = client.send(
            method,
            '/fixture',
            data: {'turnstileToken': 'synthetic'},
          );
          if (switchDuringRefresh) {
            await expectLater(pending, throwsA(isA<FormatException>()));
          } else {
            expect(await pending, {'id': 42});
          }
          expect(requests, switchDuringRefresh ? 1 : 2);
        },
      );
    }
    for (final outcome in ['success', '401', '403', 'timeout']) {
      test('$method discards a late $outcome after account change', () async {
        var identity = 1;
        var requests = 0;
        var refreshes = 0;
        final dio = fakeDio((request) {
          requests++;
          identity++;
          if (outcome != 'success') {
            throw DioException(
              requestOptions: request,
              type: outcome == 'timeout'
                  ? DioExceptionType.receiveTimeout
                  : DioExceptionType.badResponse,
              response: outcome == 'timeout'
                  ? null
                  : Response<Object?>(
                      requestOptions: request,
                      statusCode: int.parse(outcome),
                      data: {
                        'code': outcome == '401'
                            ? 'TOKEN_INVALID'
                            : 'NOT_ALLOWED',
                      },
                    ),
            );
          }
          return {'id': 42};
        });
        addTearDown(() => dio.close(force: true));
        final client = CommunityWriteClient(
          dio: dio,
          readIdentity: () => identity,
          isAuthenticated: () => true,
          refresh: () async {
            refreshes++;
            return true;
          },
          diagnostics: AccountDiagnostics(),
        );
        await expectLater(
          client.send(method, '/fixture'),
          throwsA(isA<FormatException>()),
        );
        expect(requests, 1);
        expect(refreshes, 0);
      });
    }
  }

  for (final list in [false, true]) {
    for (final outcome in ['success', '401', '503']) {
      test(
        'P1 ${list ? 'list' : 'map'} read stops at old-account $outcome',
        () async {
          late CommunityService service;
          var requests = 0;
          var refreshes = 0;
          final dio = fakeDio((request) {
            requests++;
            service.setCurrentUsername('bob');
            service.setAccessToken('bob-fixture');
            if (outcome != 'success') {
              throw DioException(
                requestOptions: request,
                type: DioExceptionType.badResponse,
                response: Response<Object?>(
                  requestOptions: request,
                  statusCode: int.parse(outcome),
                  data: {'code': 'TOKEN_INVALID'},
                ),
              );
            }
            return list ? <dynamic>[] : {'isFriend': true};
          });
          service = CommunityService.test(p1Dio: dio)
            ..setAccessToken('alice-fixture')
            ..setCurrentUsername('alice')
            ..onUnauthorizedRefresh = () async {
              refreshes++;
              return true;
            };
          addTearDown(service.dispose);
          await expectLater(
            list ? service.loadTimelineReplies(42) : service.isFriend('target'),
            throwsA(isA<FormatException>()),
          );
          expect(requests, 1);
          expect(refreshes, 0);
        },
      );
    }
  }

  for (final remove in [false, true]) {
    test(
      'friend ${remove ? 'removal' : 'addition'} invalidates owner list and late reads',
      () async {
        var changed = false;
        var reads = 0;
        final started = Completer<void>();
        final release = Completer<void>();
        final dio = fakeDio((request) async {
          if (request.method != 'GET') {
            changed = true;
            return null;
          }
          final old = !changed;
          if (++reads == 2) {
            started.complete();
            await release.future;
          }
          return {
            'total': old ? 1 : 0,
            'data': [
              if (old) {'username': 'target'},
            ],
          };
        });
        final service = CommunityService.test(p1Dio: dio)
          ..setAccessToken('fixture')
          ..setCurrentUsername('alice');
        addTearDown(service.dispose);
        await service.loadFriends('alice');
        final pending = service.loadFriends('alice', refresh: true);
        final rejected = expectLater(pending, throwsA(isA<FormatException>()));
        await started.future;
        await (remove
            ? service.removeFriend('target')
            : service.addFriend('target'));
        // The first refresh must not join the pre-mutation GET.
        final current = service.loadFriends('alice');
        release.complete();
        await rejected;
        expect((await current).data, isEmpty);
        expect((await service.loadFriends('alice')).data, isEmpty);
        expect(reads, 3);
      },
    );
  }

  test(
    'friend pagination consumes raw rows even when a whole page is filtered',
    () async {
      final offsets = <int>[];
      final dio = fakeDio((request) {
        final offset = request.queryParameters['offset'] as int;
        offsets.add(offset);
        return {
          'total': 3,
          'data': offset == 0
              ? [{}, null]
              : [
                  {'username': 'carol'},
                ],
        };
      });
      final service = CommunityService.test(p1Dio: dio);
      addTearDown(service.dispose);
      final friends = await service.loadAllFriends('alice', pageSize: 2);
      expect(friends.map((u) => u.username), ['carol']);
      expect(offsets, [0, 2]);
    },
  );
}
