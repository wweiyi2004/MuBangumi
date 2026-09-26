import 'package:mubangumi/state/account_access_controller.dart';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/auth/website_identity.dart';
import 'package:mubangumi/core/auth/website_session.dart';
import 'package:mubangumi/core/network/community_service.dart';
import 'package:mubangumi/core/network/pm_service.dart';
import 'package:mubangumi/core/storage/snapshot_cache.dart';
import 'package:mubangumi/core/storage/pm_draft_store.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/models/community_models.dart';
import 'package:mubangumi/models/pm_models.dart';
import 'package:mubangumi/screens/messages_page.dart';
import 'package:mubangumi/screens/pm_page.dart';
import 'package:mubangumi/state/pm_contacts_controller.dart';
import 'package:mubangumi/state/pm_mailbox_controller.dart';
import 'package:mubangumi/state/service_providers.dart';
import 'package:mubangumi/state/session_controller.dart';
import 'package:mubangumi/state/website_session_controller.dart';
import 'support/memory_pm_draft_repository.dart';
import 'support/pm_fixtures.dart';

const _owner = BangumiUser(
  id: 1,
  username: 'user1',
  nickname: '账号一',
  avatarUrl: '',
);
const _friend = BangumiUser(
  id: 10,
  username: 'cached',
  nickname: '缓存好友',
  avatarUrl: '',
);
const _newFriend = BangumiUser(
  id: 11,
  username: 'fresh',
  nickname: '新好友',
  avatarUrl: '',
);
const _mailbox = '<div class="pm-conversation-list"></div>';
const _identity =
    '<div id="badgeUserPanel"><a class="avatar" href="/user/user1">user</a></div>';
const _challenge =
    '<title>Just a moment...</title><form id="challenge-form">Cloudflare</form>';

class _Cache extends SnapshotCache {
  final data = <int, List<BangumiUser>>{};
  final reads = <int>[];
  @override
  Future<List<BangumiUser>?> readPmFriends(int userId) async {
    reads.add(userId);
    return data[userId];
  }

  @override
  Future<void> writePmFriends(int userId, List<BangumiUser> friends) async {
    data[userId] = friends;
  }
}

class _Store extends WebsiteSessionStore {
  WebsiteSessionSnapshot? value = WebsiteSessionSnapshot(
    cookies: const [
      WebsiteCookie(name: 'chii_auth', value: 'synthetic'),
      WebsiteCookie(name: 'chii_sid', value: 'old'),
    ],
    syncedAt: DateTime(2026),
  ).withVerifiedUser(1);
  int writes = 0;
  @override
  Future<WebsiteSessionSnapshot?> read() async => value;
  @override
  Future<void> write(WebsiteSessionSnapshot snapshot) async {
    value = snapshot;
    writes++;
  }
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
  final FutureOr<ResponseBody> Function(RequestOptions, int) respond;
  final requests = <RequestOptions>[];
  int active = 0, peak = 0;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    active++;
    if (active > peak) peak = active;
    try {
      return await respond(options, requests.length);
    } finally {
      active--;
    }
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _response(String body, {List<String> cookies = const []}) =>
    ResponseBody.fromString(
      body,
      200,
      headers: {
        'content-type': ['text/html; charset=utf-8'],
        if (cookies.isNotEmpty) 'set-cookie': cookies,
      },
    );

class _Community extends CommunityService {
  final refreshes = <bool>[];
  Future<List<BangumiUser>>? pending;
  @override
  Future<List<BangumiUser>> loadAllFriends(
    String username, {
    bool refresh = false,
    int pageSize = 30,
  }) async {
    refreshes.add(refresh);
    return pending ?? [_newFriend];
  }

  @override
  Future<CommunityPageResult<BangumiUser>> loadFriends(
    String username, {
    int limit = 30,
    int offset = 0,
    bool refresh = false,
  }) async => const CommunityPageResult(data: [_newFriend], total: 1);
  @override
  Future<void> removeFriend(String username) async {}
}

class _Pm extends PmService {
  @override
  Future<List<PmConversation>> loadInbox({int page = 1}) async => [];
  @override
  Future<List<PmConversation>> loadOutbox({int page = 1}) async => [];
}

class _Session extends PmTestSession {
  void startLoading() => state = const SessionState();
}

Future<WebsiteSessionController> _controller(
  _Store store, {
  WebsiteIdentityProbe? probe,
}) async {
  final controller = WebsiteSessionController(
    store,
    probe:
        probe ??
        WebsiteIdentityProbe(
          dio: Dio()
            ..httpClientAdapter = _Adapter((_, _) => _response(_identity)),
        ),
  );
  addTearDown(controller.dispose);
  await controller.reload();
  await controller.attachAccount(_owner);
  return controller;
}

Future<void> _show(
  WidgetTester tester, {
  required _Community community,
  required _Cache cache,
  _Session? session,
  bool messages = false,
}) async {
  final pm = _Pm();
  addTearDown(pm.dispose);
  addTearDown(community.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        communityServiceProvider.overrideWithValue(community),
        pmServiceProvider.overrideWithValue(pm),
        pmFriendsCacheProvider.overrideWithValue(cache),
        sessionProvider.overrideWith((ref) => session ?? _Session()),
        websiteSessionStoreProvider.overrideWithValue(_Store()),
        pmDraftRepositoryProvider.overrideWithValue(MemoryPmDraftRepository()),
      ],
      child: MaterialApp(
        home: messages ? const Scaffold(body: MessagesPage()) : const PmPage(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  test(
    'reattaching the same saved account renews request context, not identity',
    () async {
      final store = _Store();
      final controller = await _controller(store);
      final old = controller.state.snapshot!;
      await controller.attachAccount(null);
      expect(
        await controller.absorbResponseCookies(old.requestKey, [
          Cookie.fromSetCookieValue('chii_sid=late; Domain=bgm.tv'),
        ]),
        isNull,
      );
      await controller.attachAccount(_owner);
      final renewed = controller.state.snapshot!;
      expect(renewed.requestKey, isNot(old.requestKey));
      expect(renewed.verifiedAt, old.verifiedAt);
      expect(controller.state.isSynced, isTrue);
      await controller.absorbResponseCookies(renewed.requestKey, [
        Cookie.fromSetCookieValue('chii_sid=current; Domain=bgm.tv'),
      ]);
      expect(
        controller.state.snapshot!.cookieHeader,
        contains('chii_sid=current'),
      );
    },
  );

  test(
    'account access rejects a response immediately when the API owner changes',
    () async {
      final store = _Store();
      final website = await _controller(store);
      BangumiUser? owner = _owner;
      final access = AccountAccessController(
        website: website,
        currentUser: () => owner,
      );
      addTearDown(access.dispose);
      final key = website.state.snapshot!.requestKey;
      owner = const BangumiUser(
        id: 2,
        username: 'user2',
        nickname: '',
        avatarUrl: '',
      );
      expect(
        await access.absorbWebsiteResponseCookies(key, [
          Cookie.fromSetCookieValue('chii_sid=late; Domain=bgm.tv'),
        ]),
        isNull,
      );
      expect(store.writes, 0);
    },
  );

  test(
    'expired response cookies are removed and Max-Age overrides Expires',
    () async {
      final store = _Store();
      final controller = await _controller(store);
      final parsed = parseWebsiteResponseCookies([
        'chii_sid=deleted; Max-Age=0; Expires=Wed, 01 Jan 2031 00:00:00 GMT; Path=/',
        'cf_clearance=fresh; Max-Age=60; Expires=Wed, 01 Jan 2020 00:00:00 GMT; Path=/',
        'malformed',
      ], Uri.parse('https://bgm.tv/pm/inbox.chii'));
      final next = await controller.absorbResponseCookies(
        controller.state.snapshot!.requestKey,
        parsed,
      );
      expect(next!.cookies.any((cookie) => cookie.name == 'chii_sid'), isFalse);
      expect(
        next.cookies
            .singleWhere((cookie) => cookie.name == 'cf_clearance')
            .isExpired,
        isFalse,
      );
      expect(next.isVerifiedFor(1, DateTime.now()), isTrue);
    },
  );

  test(
    'identity GET recovers from one challenge using the rotated cookie',
    () async {
      final store = _Store();
      final adapter = _Adapter(
        (_, count) => count == 1
            ? _response(_challenge, cookies: ['cf_clearance=renewed; Path=/'])
            : _response(_identity),
      );
      final delays = <Duration>[];
      final probe = WebsiteIdentityProbe(
        dio: Dio()..httpClientAdapter = adapter,
        retryDelay: (delay) async {
          delays.add(delay);
        },
      );
      final controller = await _controller(store, probe: probe);
      expect(await controller.ensureVerified(force: true), isTrue);
      expect(adapter.requests, hasLength(2));
      expect(
        adapter.requests.last.headers['Cookie'],
        contains('cf_clearance=renewed'),
      );
      expect(delays, [const Duration(seconds: 2)]);
      expect(controller.state.isSynced, isTrue);
    },
  );

  test(
    'repeated auth rotations cannot recursively probe without a bound',
    () async {
      final store = _Store();
      final adapter = _Adapter(
        (_, count) => _response(
          _identity,
          cookies: ['chii_auth=rotation$count; Domain=bgm.tv; Path=/'],
        ),
      );
      final controller = await _controller(
        store,
        probe: WebsiteIdentityProbe(dio: Dio()..httpClientAdapter = adapter),
      );
      await controller.absorbResponseCookies(
        controller.state.snapshot!.requestKey,
        [
          Cookie.fromSetCookieValue(
            'chii_auth=candidate; Domain=bgm.tv; Path=/',
          ),
        ],
      );
      expect(adapter.requests, hasLength(1));
      expect(controller.state.isSynced, isFalse);
      expect(controller.state.snapshot!.verifiedUserId, isNull);
    },
  );

  for (final fail in [false, true]) {
    testWidgets(
      'cached friends are visible during background refresh (failure: $fail)',
      (tester) async {
        final pending = Completer<List<BangumiUser>>();
        final community = _Community()..pending = pending.future;
        final cache = _Cache()..data[1] = [_friend];
        await _show(tester, community: community, cache: cache);
        expect(find.text('缓存好友'), findsOneWidget);
        expect(find.text('正在加载完整好友列表…'), findsNothing);
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
        expect(community.refreshes, [false]);
        if (fail) {
          pending.completeError(Exception('offline'));
        } else {
          pending.complete([_newFriend]);
        }
        await tester.pumpAndSettle();
        expect(find.text(fail ? '缓存好友' : '新好友'), findsOneWidget);
        expect(cache.data[1]!.single.id, fail ? 10 : 11);
        await tester.tap(find.byTooltip('刷新好友和会话'));
        await tester.pumpAndSettle();
        expect(community.refreshes, [false, true]);
      },
    );
  }

  testWidgets('bootstrap waits for the first account and loads friends once', (
    tester,
  ) async {
    final community = _Community();
    final session = _Session()..startLoading();
    await _show(
      tester,
      community: community,
      cache: _Cache(),
      session: session,
    );
    expect(community.refreshes, isEmpty);
    session.switchUser(1);
    await tester.pumpAndSettle();
    expect(community.refreshes, [false]);
    expect(find.text('新好友'), findsOneWidget);
  });

  for (final changed in [false, true]) {
    testWidgets(
      'FriendsPage return refreshes PM only after a mutation ($changed)',
      (tester) async {
        final community = _Community();
        await _show(
          tester,
          community: community,
          cache: _Cache(),
          messages: true,
        );
        await tester.pumpAndSettle();
        expect(community.refreshes, [false]);
        await tester.tap(find.text('好友'));
        await tester.pumpAndSettle();
        if (changed) {
          await tester.longPress(find.text('新好友'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('解除'));
          await tester.pumpAndSettle();
        }
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(community.refreshes, changed ? [false, false] : [false]);
      },
    );
  }

  test(
    'friend requests share a Future and a late old-account result is ignored',
    () async {
      final old = Completer<List<BangumiUser>>();
      final next = Completer<List<BangumiUser>>();
      final cache = _Cache()..data[1] = [_friend];
      var calls = 0;
      final inbox = PmMailboxController(({page = 1}) async => []);
      final outbox = PmMailboxController(({page = 1}) async => []);
      final contacts = PmContactsController(
        inbox: inbox,
        outbox: outbox,
        cache: cache,
        loadFriends: ({bool refresh = false}) =>
            ++calls == 1 ? old.future : next.future,
      );
      addTearDown(() {
        contacts.dispose();
        inbox.dispose();
        outbox.dispose();
      });
      final first = contacts.attachAccount(1);
      expect(identical(first, contacts.refreshFriends()), isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(contacts.friends, [_friend]);
      final second = contacts.attachAccount(2);
      await Future<void>.delayed(Duration.zero);
      expect(contacts.friends, isEmpty);
      old.complete([_friend]);
      await first;
      expect(contacts.friends, isEmpty);
      next.complete([_newFriend]);
      await second;
      expect(cache.reads, [1, 2]);
      expect(cache.data[2], [_newFriend]);
      expect(calls, 2);
    },
  );

  test(
    'sid rotates without losing verification; stale responses and other domains are ignored',
    () async {
      final store = _Store();
      final controller = await _controller(store);
      final before = controller.state.snapshot!;
      final updated = await controller
          .absorbResponseCookies(before.requestKey, [
            Cookie.fromSetCookieValue(
              'chii_sid=new; Domain=.bgm.tv; Path=/; Max-Age=3600; HttpOnly',
            ),
            Cookie.fromSetCookieValue(
              'evil=no; Domain=bgm.tv.evil.invalid; Path=/',
            ),
          ]);
      expect(updated!.authenticationKey, before.authenticationKey);
      expect(updated.requestKey, isNot(before.requestKey));
      expect(updated.verificationVersion, 2);
      expect(updated.verificationId, before.verificationId);
      expect(updated.isVerifiedFor(1, DateTime.now()), isTrue);
      expect(controller.state.isSynced, isTrue);
      expect(updated.cookies.any((c) => c.name == 'evil'), isFalse);
      expect(updated.cookies.last.expiresAt, isNotNull);
      final writes = store.writes;
      await controller.absorbResponseCookies(before.requestKey, [
        Cookie.fromSetCookieValue('chii_sid=late; Domain=bgm.tv'),
      ]);
      await controller.absorbResponseCookies(updated.requestKey, [
        Cookie.fromSetCookieValue('chii_sid=new; Domain=bgm.tv'),
      ]);
      expect(store.writes, writes);
      store.value = WebsiteSessionSnapshot(
        cookies: const [
          WebsiteCookie(name: 'chii_auth', value: 'second-account'),
        ],
        syncedAt: DateTime.now(),
      ).withVerifiedUser(2);
      await controller.attachAccount(
        const BangumiUser(
          id: 2,
          username: 'user2',
          nickname: '',
          avatarUrl: '',
        ),
      );
      final switchedWrites = store.writes;
      await controller.absorbResponseCookies(updated.requestKey, [
        Cookie.fromSetCookieValue('chii_sid=wrong-owner; Domain=bgm.tv'),
      ]);
      expect(store.writes, switchedWrites);
      expect(controller.state.isSynced, isTrue);
      expect(store.value!.verifiedUserId, 2);
      expect(store.value!.cookieHeader, 'chii_auth=second-account');
    },
  );

  test(
    'authentication cookie rotation verifies the candidate before binding',
    () async {
      final store = _Store();
      final pending = Completer<ResponseBody>();
      final started = Completer<void>();
      final adapter = _Adapter((_, _) {
        started.complete();
        return pending.future;
      });
      final probe = WebsiteIdentityProbe(
        dio: Dio()..httpClientAdapter = adapter,
      );
      final controller = await _controller(store, probe: probe);
      final absorption = controller.absorbResponseCookies(
        controller.state.snapshot!.requestKey,
        [Cookie.fromSetCookieValue('chii_auth=rotated; Domain=bgm.tv; Path=/')],
      );
      await started.future;
      expect(controller.state.status, WebsiteAccessStatus.checking);
      expect(controller.state.snapshot!.verifiedUserId, isNull);
      expect(store.value!.cookies.first.value, 'synthetic');
      expect(adapter.requests, hasLength(1));
      pending.complete(_response(_identity));
      await absorption;
      expect(controller.state.snapshot!.authenticationKey, 'chii_auth=rotated');
      expect(controller.state.isSynced, isTrue);
    },
  );

  test(
    'GET absorbs sid without an extra read; POST also absorbs cookies once',
    () async {
      final store = _Store();
      final controller = await _controller(store);
      final adapter = _Adapter(
        (options, count) => _response(
          options.method == 'POST'
              ? '<div class="message">发送成功</div>'
              : _mailbox,
          cookies: ['chii_sid=sid$count; Path=/'],
        ),
      );
      final service = PmService(dio: Dio()..httpClientAdapter = adapter)
        ..websiteSessionGuard = (() =>
            controller.requireVerifiedSession(_owner))
        ..onWebsiteResponseCookies = controller.absorbResponseCookies;
      addTearDown(service.dispose);
      await service.loadInbox();
      expect(adapter.requests, hasLength(1));
      expect(
        controller.state.snapshot!.cookieHeader,
        contains('chii_sid=sid1'),
      );
      try {
        await service.compose(
          params: const PmComposeParams(formhash: 'fake', msgReceivers: '10'),
          title: 'synthetic',
          body: 'synthetic',
        );
      } on PmDeliveryUncertain {
        /* No success receipt in this fixture. */
      }
      expect(adapter.requests, hasLength(2));
      expect(
        adapter.requests.last.headers['Cookie'],
        contains('chii_sid=sid1'),
      );
      expect(
        controller.state.snapshot!.cookieHeader,
        contains('chii_sid=sid2'),
      );
    },
  );

  test(
    'identity probe persists response cookies through verification',
    () async {
      final store = _Store();
      final adapter = _Adapter(
        (_, _) => _response(_identity, cookies: ['cf_clearance=fresh; Path=/']),
      );
      final controller = await _controller(
        store,
        probe: WebsiteIdentityProbe(dio: Dio()..httpClientAdapter = adapter),
      );
      expect(await controller.ensureVerified(force: true), isTrue);
      expect(store.value!.cookieHeader, contains('cf_clearance=fresh'));
      expect(store.value!.isVerifiedFor(1, DateTime.now()), isTrue);
    },
  );

  for (final succeeds in [true, false]) {
    test(
      'GET challenge retries once before reporting (recovers: $succeeds)',
      () async {
        final adapter = _Adapter(
          (_, count) =>
              _response(count == 1 || !succeeds ? _challenge : _mailbox),
        );
        final failures = <WebsiteAccessStatus>[];
        final delays = <Duration>[];
        final service =
            PmService(
                sessionStore: _Store(),
                dio: Dio()..httpClientAdapter = adapter,
                retryDelay: (d) async {
                  delays.add(d);
                },
              )
              ..onWebsiteSessionFailure = (status, _, {Uri? recoveryUri}) {
                failures.add(status);
                return true;
              };
        addTearDown(service.dispose);
        if (succeeds) {
          await service.loadInbox();
        } else {
          await expectLater(
            service.loadInbox(),
            throwsA(isA<PmAuthException>()),
          );
        }
        expect(adapter.requests, hasLength(2));
        expect(delays, [const Duration(seconds: 2)]);
        expect(failures, succeeds ? isEmpty : [WebsiteAccessStatus.challenge]);
      },
    );
  }

  test('POST challenge is never replayed', () async {
    final adapter = _Adapter((_, _) => _response(_challenge));
    final service = PmService(
      sessionStore: _Store(),
      dio: Dio()..httpClientAdapter = adapter,
      retryDelay: (_) async => fail('POST must not retry'),
    );
    addTearDown(service.dispose);
    await expectLater(
      service.compose(
        params: const PmComposeParams(formhash: 'fake', msgReceivers: '10'),
        title: 'synthetic',
        body: 'synthetic',
      ),
      throwsA(isA<PmAuthException>()),
    );
    expect(adapter.requests, hasLength(1));
  });

  test(
    'initial mailboxes request only page one, and the shared HTML gate caps concurrency',
    () async {
      final adapter = _Adapter((_, _) async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return _response(_mailbox);
      });
      final service = PmService(
        sessionStore: _Store(),
        dio: Dio()..httpClientAdapter = adapter,
      );
      final inbox = PmMailboxController(service.loadInbox),
          outbox = PmMailboxController(service.loadOutbox);
      final contacts = PmContactsController(
        inbox: inbox,
        outbox: outbox,
        loadFriends: ({bool refresh = false}) async => [],
      );
      addTearDown(() {
        contacts.dispose();
        inbox.dispose();
        outbox.dispose();
        service.dispose();
      });
      await contacts.refresh();
      expect(adapter.requests.map((r) => r.path), [
        '/pm/inbox.chii',
        '/pm/outbox.chii',
      ]);
      expect(adapter.requests.map((r) => r.queryParameters['page']), [1, 1]);
      expect(adapter.peak, 1);
      await Future.wait([
        for (var page = 2; page < 8; page++) service.loadInbox(page: page),
      ]);
      expect(adapter.peak, 2);
    },
  );
}
