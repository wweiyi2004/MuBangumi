import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/network/community_service.dart';

void main() {
  for (final remove in [false, true]) {
    for (final scenario in [
      'late_401',
      'during_refresh',
      'logout',
      'same_account',
    ]) {
      test(
        '${remove ? 'remove' : 'add'} friend authentication retry: $scenario',
        () async {
          final tokens = <String>[];
          final started = Completer<void>();
          final response = Completer<void>();
          final refreshStarted = Completer<void>();
          final refreshed = Completer<void>();
          var refreshCalls = 0;
          final dio = Dio(BaseOptions(baseUrl: 'https://next.bgm.tv'));
          dio.interceptors.add(
            InterceptorsWrapper(
              onRequest: (options, handler) async {
                tokens.add(options.headers['Authorization'].toString());
                if (tokens.length == 1) {
                  started.complete();
                  await response.future;
                  handler.reject(
                    DioException(
                      requestOptions: options,
                      type: DioExceptionType.badResponse,
                      response: Response<Map<String, dynamic>>(
                        requestOptions: options,
                        statusCode: 401,
                        data: {'code': 'TOKEN_INVALID'},
                      ),
                    ),
                  );
                } else {
                  handler.resolve(
                    Response<void>(requestOptions: options, statusCode: 204),
                  );
                }
              },
            ),
          );
          final service = CommunityService(p1Dio: dio)
            ..setAccessToken('account-a-test-token')
            ..setCurrentUsername('account-a');
          addTearDown(service.dispose);
          service.onUnauthorizedRefresh = () async {
            refreshCalls++;
            if (scenario == 'during_refresh') {
              refreshStarted.complete();
              await refreshed.future;
            } else {
              service.setAccessToken('account-a-renewed-token');
            }
            return true;
          };
          Object? error;
          final pending =
              (remove
                      ? service.removeFriend('target-user')
                      : service.addFriend('target-user'))
                  .catchError((Object caught) {
                    error = caught;
                  });
          await started.future;
          if (scenario == 'late_401') {
            service.setCurrentUsername('account-b');
            service.setAccessToken('account-b-test-token');
          } else if (scenario == 'logout') {
            service.setCurrentUsername(null);
            service.setAccessToken(null);
          }
          response.complete();
          if (scenario == 'during_refresh') {
            await refreshStarted.future;
            service.setCurrentUsername('account-b');
            service.setAccessToken('account-b-test-token');
            refreshed.complete();
          }
          await pending;
          expect(
            tokens,
            [
              'Bearer account-a-test-token',
              if (scenario == 'same_account') 'Bearer account-a-renewed-token',
            ],
            reason:
                'Account A intent must not issue a second write authenticated as account B.',
          );
          expect(error, scenario == 'same_account' ? isNull : isNotNull);
          expect(
            refreshCalls,
            const ['late_401', 'logout'].contains(scenario) ? 0 : 1,
          );
        },
      );
    }
  }
}
