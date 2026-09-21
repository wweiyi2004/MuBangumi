import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/auth/website_identity.dart';
import 'package:mubangumi/core/auth/website_session.dart';
import 'package:mubangumi/core/network/community_service.dart';
import 'package:mubangumi/core/network/pm_service.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/models/pm_models.dart';
import 'package:mubangumi/state/website_session_controller.dart';

const _user = BangumiUser(
  id: 1,
  username: 'alice',
  nickname: 'Alice',
  avatarUrl: '',
);

class _Store extends WebsiteSessionStore {
  WebsiteSessionSnapshot value = WebsiteSessionSnapshot(
    cookies: const [WebsiteCookie(name: 'chii_auth', value: 'fixture')],
    syncedAt: DateTime(2026, 1, 1),
    userAgent: 'Browser/fixture',
  ).withVerifiedUser(1, at: DateTime(2026, 1, 1));

  @override
  Future<WebsiteSessionSnapshot?> read() async => value;
  @override
  Future<void> write(WebsiteSessionSnapshot snapshot) async => value = snapshot;
}

class _Probe extends WebsiteIdentityProbe {
  @override
  Future<int> verify(
    WebsiteSessionSnapshot snapshot,
    BangumiUser expected,
  ) async => expected.id;
}

Future<WebsiteSessionController> _controller() async {
  final controller = WebsiteSessionController(_Store(), probe: _Probe());
  addTearDown(controller.dispose);
  await controller.attachAccount(_user);
  return controller;
}

void main() {
  for (final status in [
    WebsiteAccessStatus.expired,
    WebsiteAccessStatus.challenge,
  ]) {
    test(
      'a late $status cannot revoke re-verification of the same cookie',
      () async {
        final controller = await _controller();
        final old = controller.state.snapshot!;
        expect(await controller.ensureVerified(force: true), true);
        final current = controller.state.snapshot!;
        expect(current.authenticationKey, old.authenticationKey);
        expect(current.requestKey, isNot(old.requestKey));
        expect(controller.reportFailure(status, old.requestKey), false);
        expect(controller.state.isSynced, true);
        expect(controller.reportFailure(status, current.requestKey), true);
        expect(controller.state.status, status);
        expect(controller.state.isSynced, false);
      },
    );
  }

  test(
    'browser and challenge changes have distinct request keys but preserve draft ownership',
    () {
      final old = _Store().value;
      for (final change in ['browser', 'challenge']) {
        final updated = WebsiteSessionSnapshot(
          cookies: [
            ...old.cookies,
            if (change == 'challenge')
              const WebsiteCookie(name: 'cf_clearance', value: 'fresh'),
          ],
          syncedAt: old.syncedAt,
          userAgent: change == 'browser' ? 'NewBrowser/fixture' : old.userAgent,
        ).withVerifiedUser(1, at: old.verifiedAt);
        expect(updated.authenticationKey, old.authenticationKey);
        expect(updated.requestKey, isNot(old.requestKey));
        expect(
          WebsiteSessionSnapshot.fromJson(updated.toJson()).requestKey,
          updated.requestKey,
        );
      }
    },
  );

  for (final challenge in [false, true]) {
    test(
      'late PM GET rejection retries once after renewed verification (challenge: $challenge)',
      () async {
        final controller = await _controller();
        final started = Completer<void>();
        final release = Completer<void>();
        var requests = 0;
        final dio = Dio()
          ..interceptors.add(
            InterceptorsWrapper(
              onRequest: (options, handler) async {
                final first = ++requests == 1;
                if (first) {
                  started.complete();
                  await release.future;
                }
                handler.resolve(
                  Response<String>(
                    requestOptions: options,
                    statusCode: first ? (challenge ? 403 : 401) : 200,
                    data: first && challenge
                        ? '<title>Just a moment...</title>'
                        : '<html></html>',
                    headers: Headers.fromMap(
                      first && challenge
                          ? {
                              'cf-mitigated': ['challenge'],
                            }
                          : {},
                    ),
                  ),
                );
              },
            ),
          );
        final service = PmService(dio: dio)
          ..onWebsiteSessionFailure = controller.reportFailure
          ..websiteSessionGuard = () =>
              controller.requireVerifiedSession(_user);
        addTearDown(service.dispose);
        final pending = service.loadInbox();
        await started.future;
        expect(await controller.ensureVerified(force: true), true);
        release.complete();
        expect(await pending, isEmpty);
        expect(requests, 2);
        expect(controller.state.isSynced, true);
      },
    );
  }

  test(
    'GET session recovery is bounded even if every response follows a renewal',
    () async {
      final controller = await _controller();
      var requests = 0;
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) async {
              requests++;
              await controller.ensureVerified(force: true);
              handler.resolve(
                Response<String>(
                  requestOptions: options,
                  statusCode: 401,
                  data: '',
                ),
              );
            },
          ),
        );
      final service = PmService(dio: dio)
        ..onWebsiteSessionFailure = controller.reportFailure
        ..websiteSessionGuard = () => controller.requireVerifiedSession(_user);
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
      expect(requests, 2);
      expect(controller.state.isSynced, true);
    },
  );

  for (final challenge in [false, true]) {
    test(
      'late PM POST rejection preserves renewed login and never resends (challenge: $challenge)',
      () async {
        final controller = await _controller();
        var requests = 0;
        final dio = Dio()
          ..interceptors.add(
            InterceptorsWrapper(
              onRequest: (options, handler) async {
                requests++;
                await controller.ensureVerified(force: true);
                handler.resolve(
                  Response<String>(
                    requestOptions: options,
                    statusCode: challenge ? 403 : 401,
                    data: '',
                    headers: Headers.fromMap(
                      challenge
                          ? {
                              'cf-mitigated': ['challenge'],
                            }
                          : {},
                    ),
                  ),
                );
              },
            ),
          );
        final service = PmService(dio: dio)
          ..onWebsiteSessionFailure = controller.reportFailure
          ..websiteSessionGuard = () =>
              controller.requireVerifiedSession(_user);
        addTearDown(service.dispose);
        await expectLater(
          service.compose(
            params: const PmComposeParams(formhash: 'hash', msgReceivers: '2'),
            title: 'fixture',
            body: 'fixture',
          ),
          throwsA(isA<PmDeliveryUncertain>()),
        );
        expect(requests, 1);
        expect(controller.state.isSynced, true);
      },
    );
  }

  for (final renew in [false, true]) {
    test(
      'group form rejection belongs to its original request context (renew: $renew)',
      () async {
        final controller = await _controller();
        var writes = 0;
        final api = Dio()
          ..interceptors.add(
            InterceptorsWrapper(
              onRequest: (options, handler) {
                handler.reject(
                  DioException(
                    requestOptions: options,
                    response: Response(
                      requestOptions: options,
                      statusCode: 401,
                      data: {
                        'code': 'NOT_ALLOWED',
                        'message':
                            "you don't have permission to create posts,join group first",
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
              onRequest: (options, handler) async {
                if (options.method == 'POST') writes++;
                if (renew) await controller.ensureVerified(force: true);
                handler.resolve(
                  Response<String>(
                    requestOptions: options,
                    statusCode: 401,
                    data: '',
                  ),
                );
              },
            ),
          );
        final service = CommunityService.test(p1Dio: api, htmlDio: html)
          ..setAccessToken('fixture')
          ..onWebsiteSessionFailure = controller.reportFailure
          ..websiteSessionGuard = () =>
              controller.requireVerifiedSession(_user);
        addTearDown(service.dispose);
        await expectLater(
          service.createGroupTopic(
            slug: 'fixture',
            title: 'fixture',
            content: 'fixture',
            turnstileToken: 'fixture',
          ),
          throwsA(isA<FormatException>()),
        );
        expect(writes, 0);
        expect(controller.state.isSynced, renew);
      },
    );
  }
}
