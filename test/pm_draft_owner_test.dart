import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/auth/website_session.dart';
import 'package:mubangumi/core/network/pm_html_parser.dart';
import 'package:mubangumi/core/network/pm_service.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/models/pm_models.dart';

const user = BangumiUser(
  id: 42,
  username: 'alice',
  nickname: 'Alice',
  avatarUrl: '',
);

void main() {
  test(
    'legacy owner metadata without a current verification must be checked online',
    () async {
      final store = _Store()
        ..snapshot = WebsiteSessionSnapshot(
          cookies: const [WebsiteCookie(name: 'chii_auth', value: 'legacy')],
          syncedAt: DateTime(2026),
          verifiedUserId: 42,
        );
      var requests = 0;
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              requests++;
              handler.resolve(
                Response<String>(
                  requestOptions: options,
                  statusCode: 200,
                  data: '<div id="dock"><a href="/user/alice">Alice</a></div>',
                ),
              );
            },
          ),
        );
      final service = PmService(sessionStore: store, dio: dio);
      addTearDown(service.dispose);
      final result = await service.verifyDraftOwner(user);
      expect(requests, 1);
      expect(result.userId, 42);
      expect(result.requestKey, store.snapshot!.requestKey);
    },
  );
  test(
    'verified OAuth owner can restore drafts without a new website request',
    () async {
      var requests = 0;
      final store = _Store()..snapshot = _session('a', owner: 42);
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (_, _) {
              requests++;
            },
          ),
        );
      final result = await PmService(
        sessionStore: store,
        dio: dio,
      ).verifyDraftOwner(user);
      expect(result.userId, 42);
      expect(requests, 0);
      store.snapshot = _session('a', owner: 99);
      await expectLater(
        PmService(sessionStore: store, dio: dio).verifyDraftOwner(user),
        throwsA(isA<PmAuthException>()),
      );
      expect(requests, 0);
    },
  );

  for (final identifier in ['alice', '42']) {
    test(
      'unverified cookies require a matching own-account header: $identifier',
      () async {
        final store = _Store()..snapshot = _session('a');
        final dio = Dio()
          ..interceptors.add(
            InterceptorsWrapper(
              onRequest: (options, handler) {
                expect(options.path, '/');
                handler.resolve(
                  Response<String>(
                    requestOptions: options,
                    statusCode: 200,
                    data:
                        '<div id="headerNeue2"><div><div class="idBadgerNeue"><a class="avatar" href="/user/$identifier"></a></div></div></div>'
                        '<div class="pm-message"><a class="avatar" href="/user/bob">Bob</a></div>',
                  ),
                );
              },
            ),
          );
        final identity = await PmService(
          sessionStore: store,
          dio: dio,
        ).verifyDraftOwner(user);
        expect(identity.userId, 42);
        expect(identity.authenticationKey, 'chii_auth=a');
      },
    );
  }

  for (final (html, requiresLogin) in [
    (
      '<div class="pm-message"><a class="avatar" href="/user/alice">Alice</a></div>',
      false,
    ),
    ('<div id="dock"><a href="/user/bob">Bob</a></div>', true),
    (
      '<div id="dock"><a href="https://evil.example/user/alice">Alice</a></div>',
      false,
    ),
    (
      '<div id="dock"><a href="javascript://bgm.tv/user/alice">Alice</a></div>',
      false,
    ),
    (
      '<div id="dock"><a href="/user/alice">Alice</a><a href="/user/bob">Bob</a></div>',
      false,
    ),
  ]) {
    test(
      'unknown or mismatched website identity cannot expose an app account draft: $html',
      () async {
        final store = _Store()..snapshot = _session('a');
        final dio = Dio()
          ..interceptors.add(
            InterceptorsWrapper(
              onRequest: (options, handler) {
                handler.resolve(
                  Response<String>(
                    requestOptions: options,
                    statusCode: 200,
                    data: html,
                  ),
                );
              },
            ),
          );
        await expectLater(
          PmService(sessionStore: store, dio: dio).verifyDraftOwner(user),
          throwsA(requiresLogin ? isA<PmAuthException>() : isA<PmException>()),
        );
      },
    );
  }

  test(
    'a late identity probe cannot authorize a replacement session',
    () async {
      final gate = Completer<void>();
      final started = Completer<void>();
      final store = _Store()..snapshot = _session('a');
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) async {
              started.complete();
              await gate.future;
              handler.resolve(
                Response<String>(
                  requestOptions: options,
                  statusCode: 200,
                  data: '<div id="dock"><a href="/user/alice">Alice</a></div>',
                ),
              );
            },
          ),
        );
      final probe = PmService(
        sessionStore: store,
        dio: dio,
      ).verifyDraftOwner(user);
      await started.future;
      store.snapshot = _session('b');
      gate.complete();
      await expectLater(probe, throwsA(isA<PmAuthException>()));
    },
  );

  test(
    'identity parser ignores unrelated profile links outside own-account navigation',
    () {
      expect(
        PmHtmlParser().parseSignedInUser('<a href="/user/alice">Alice</a>'),
        isNull,
      );
      expect(
        PmHtmlParser().parseSignedInUser(
          '<div id="dock"><a href="/user/alice">profile</a><a href="/user/alice/blog">blog</a></div>',
        ),
        'alice',
      );
    },
  );
}

WebsiteSessionSnapshot _session(String cookie, {int? owner}) =>
    WebsiteSessionSnapshot(
      cookies: [WebsiteCookie(name: 'chii_auth', value: cookie)],
      syncedAt: DateTime(2026),
      verifiedUserId: owner,
      verifiedAt: owner == null ? null : DateTime(2026),
      verificationVersion: owner == null ? 0 : 2,
    );

class _Store extends WebsiteSessionStore {
  WebsiteSessionSnapshot? snapshot;
  @override
  Future<WebsiteSessionSnapshot?> read() async => snapshot;
}
