import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/auth/website_identity.dart';
import 'package:mubangumi/core/auth/website_session.dart';
import 'package:mubangumi/core/network/community_service.dart';
import 'package:mubangumi/core/network/community_timeline_html_parser.dart';
import 'package:mubangumi/core/storage/community_cache.dart';
import 'package:mubangumi/models/community_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  final parser = CommunityTimelineHtmlParser();
  test('classic events preserve identity, UTC time, target and comment', () {
    final result = parser.parse(_page(900, next: true), page: 1);
    final item = result.items.single;
    expect(item.id, 900);
    expect(item.user.username, 'alice');
    expect(item.user.displayName, 'Alice');
    expect(item.createdAt, DateTime.utc(2026, 10, 20, 17, 52));
    expect(item.description, '看过 ep.3 测试');
    expect(item.content, '测试短评');
    expect(item.targets.single.id, 123);
    expect(item.targets.single.imageUrl, 'https://lain.bgm.tv/cover.jpg');
    expect(item.isStatus, isFalse);
    expect(result.nextPage, 2);
    expect(result.nextUntil, isNull);
    final unpadded = parser.parse(
      _page(901).replaceFirst('2026-10-21 01:52', '2026-1-7 1:52'),
      page: 1,
    );
    expect(unpadded.items.single.createdAt, DateTime.utc(2026, 1, 6, 17, 52));
  });

  test(
    'profile events inherit owner and status is not confused with a rename',
    () {
      final source = _page(900, author: false).replaceFirst(
        '看过 <a href="/subject/ep/3">ep.3 测试</a>',
        '<p class="status">第一行<br>第二行</p>',
      );
      final owner = CommunityUser(id: 1, username: 'alice', nickname: 'Alice');
      final item = parser.parse(source, page: 1, owner: owner).items.single;
      expect(item.user.username, 'alice');
      expect(item.content, '第一行\n第二行');
      expect(item.isStatus, isFalse);
      final replyable = source.replaceFirst(
        '<div class="post_actions date">',
        '<div class="post_actions date"><a class="tml_comment">回复 (3)</a>',
      );
      expect(
        parser.parse(replyable, page: 1, owner: owner).items.single.isStatus,
        isTrue,
      );
      expect(
        parser.parse(replyable, page: 1, owner: owner).items.single.replyCount,
        3,
      );
    },
  );

  test('unrecognized HTML and malformed events are not an empty timeline', () {
    expect(
      () => parser.parse('<html>challenge</html>', page: 1),
      throwsFormatException,
    );
    expect(
      () => parser.parse(
        _page(900).replaceAll('2026-10-21 01:52', 'bad'),
        page: 1,
      ),
      throwsFormatException,
    );
    expect(parser.parse('<div id="timeline"></div>', page: 1).items, isEmpty);
  });

  test('consecutive events by one friend reuse the omitted avatar', () {
    String row(int id, String user, {String? avatar}) =>
        '''
<li id="tml_$id" data-item-user="$user">
${avatar == null ? '' : '<span class="avatar"><a href="/user/$user"><span class="avatarNeue" style="background-image:url(&quot;$avatar&quot;)"></span></a></span>'}
<span class="info clearit"><a href="/user/$user" class="l">$user</a> 想玩 <a href="/subject/1">作品</a>
<div class="post_actions date"><span title="2026-10-21 05:36">刚刚</span></div></span></li>''';
    final source =
        '<div id="timeline"><ul>'
        '${row(3, 'yinleng', avatar: '//lain.bgm.tv/pic/user/l/y.jpg?r=1&amp;hd=1')}'
        '${row(2, 'yinleng')}'
        '${row(1, 'bob')}'
        '</ul></div>';
    final items = parser.parse(source, page: 1).items;
    expect(
      items[0].user.avatarUrl,
      'https://lain.bgm.tv/pic/user/l/y.jpg?r=1&hd=1',
    );
    expect(items[1].user.avatarUrl, items[0].user.avatarUrl);
    // A different user never inherits someone else's avatar.
    expect(items[2].user.avatarUrl, isEmpty);
  });

  test('profile friendship target is never mistaken for the event owner', () {
    final source = _page(900, author: false).replaceFirst(
      '看过 <a href="/subject/ep/3">ep.3 测试</a>',
      '添加了好友 <a href="/user/bob">Bob</a>',
    );
    final result = parser.parse(
      source,
      page: 1,
      owner: const CommunityUser(id: 1, username: 'alice', nickname: 'Alice'),
    );
    expect(result.items.single.user.username, 'alice');
    expect(result.items.single.description, '添加了好友 Bob');
  });

  for (final mode in [CommunityTimelineMode.me, CommunityTimelineMode.all]) {
    test(
      '${mode.name} reads fresh website events before frozen API inbox',
      () async {
        final requests = <RequestOptions>[];
        final service = _service(
          requests,
          (_) async => _page(900, author: mode != CommunityTimelineMode.me),
        );
        service.setCurrentUsername('alice');
        service.setAccessToken('synthetic-api-token');
        final result = await service.loadFreshTimelinePage(mode, refresh: true);
        expect(result.items.single.id, 900);
        expect(result.notice, isNull);
        expect(
          requests.single.path,
          mode == CommunityTimelineMode.me
              ? '/user/alice/timeline'
              : '/timeline',
        );
        expect(requests.single.headers.containsKey('Authorization'), isFalse);
        expect(requests.single.headers.containsKey('Cookie'), isFalse);
        service.dispose();
      },
    );
  }

  test(
    'website pages stay separate from P1 cursors and failures are retryable',
    () async {
      final requests = <RequestOptions>[];
      final service = _service(requests, (options) async {
        if (options.queryParameters['page'] == 2) throw StateError('offline');
        return _page(900, next: true);
      });
      final first = await service.loadFreshTimelinePage(
        CommunityTimelineMode.all,
        refresh: true,
      );
      expect(first.nextPage, 2);
      await expectLater(
        service.loadFreshTimelinePage(
          CommunityTimelineMode.all,
          websitePage: 2,
        ),
        throwsA(
          predicate((error) => error.toString().contains('无法连接 Bangumi 社区')),
        ),
      );
      expect(requests, hasLength(2));
      expect(requests.last.queryParameters['page'], 2);
      service.dispose();
    },
  );

  test(
    'unavailable website explicitly labels P1 fallback as possibly stale',
    () async {
      final requests = <RequestOptions>[];
      final service = _service(requests, (_) async => '<html>challenge</html>');
      final result = await service.loadFreshTimelinePage(
        CommunityTimelineMode.all,
        refresh: true,
      );
      expect(result.items.single.id, 100);
      expect(result.notice, contains('当前内容可能滞后'));
      expect(result.nextUntil, 100);
      expect(result.nextPage, isNull);
      service.dispose();
    },
  );

  test(
    'friends require verified ownership and never use anonymous public feed',
    () async {
      final requests = <RequestOptions>[];
      final service = _service(requests, (_) async => _page(900));
      service.setCurrentUsername('alice');
      var result = await service.loadFreshTimelinePage(
        CommunityTimelineMode.friends,
        refresh: true,
      );
      expect(result.notice, contains('验证网页登录'));
      expect(requests.where((r) => r.path == '/'), isEmpty);
      service.websiteSessionGuard = () async => _session();
      result = await service.loadFreshTimelinePage(
        CommunityTimelineMode.friends,
        refresh: true,
      );
      expect(result.items.single.id, 100);
      expect(result.notice, contains('网页登录身份'));
      service.dispose();
    },
  );

  test(
    'friends use website cookie only after guard and recheck session',
    () async {
      final requests = <RequestOptions>[];
      final service = _service(
        requests,
        (options) async => options.path == '/'
            ? '<div id="dock"><a href="/user/alice">Alice</a></div>'
            : _page(900),
      );
      service.setCurrentUsername('alice');
      service.setAccessToken('synthetic-api-token');
      var guards = 0;
      service.websiteSessionGuard = () async {
        guards++;
        return _session();
      };
      final result = await service.loadFreshTimelinePage(
        CommunityTimelineMode.friends,
        refresh: true,
      );
      expect(result.items.single.id, 900);
      expect(result.notice, isNull);
      expect(guards, 2);
      expect(requests, hasLength(2));
      expect(requests.first.path, startsWith('/ajax/timeline?type=all&page=1'));
      expect(
        requests.first.headers['Cookie'],
        contains('chii_auth=synthetic-cookie'),
      );
      expect(
        requests.every((r) => !r.headers.containsKey('Authorization')),
        isTrue,
      );
      service.dispose();
    },
  );

  test('old website responses cannot cross an API account change', () async {
    final gate = Completer<String>();
    final started = Completer<void>();
    final service = _service([], (_) {
      started.complete();
      return gate.future;
    });
    service.setCurrentUsername('alice');
    final pending = service.loadFreshTimelinePage(
      CommunityTimelineMode.me,
      refresh: true,
    );
    await started.future;
    final rejected = expectLater(pending, throwsFormatException);
    service.setCurrentUsername('bob');
    gate.complete(_page(900, author: false));
    await rejected;
    service.dispose();
  });

  test(
    'website credential replacement rejects the previous friends response',
    () async {
      final service = _service(
        [],
        (_) async =>
            '<div id="dock"><a href="/user/alice">Alice</a></div>${_page(900)}',
      );
      service.setCurrentUsername('alice');
      var count = 0;
      service.websiteSessionGuard = () async =>
          _session(cookie: ++count == 1 ? 'old' : 'new');
      final result = await service.loadFreshTimelinePage(
        CommunityTimelineMode.friends,
        refresh: true,
      );
      expect(result.items.single.id, 100);
      expect(result.notice, contains('网页登录已变化'));
      service.dispose();
    },
  );

  group('timeline snapshots', () {
    late Database db;
    late CommunityCache cache;
    setUp(() async {
      sqfliteFfiInit();
      db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await db.execute(
        'CREATE TABLE community_cache (cache_key TEXT PRIMARY KEY, payload TEXT, updated_at INTEGER, account_scoped INTEGER)',
      );
      cache = CommunityCache.test(connection: db);
    });
    tearDown(() => db.close());

    test(
      'website first page is restored and a lagging API cannot replace it',
      () async {
        var website = true;
        var apiId = 100;
        final service = _service(
          [],
          (_) async =>
              website ? _page(900, author: false) : '<html>challenge</html>',
          cache: cache,
          apiId: () => apiId,
        );
        service.setCurrentUsername('alice');
        await service.loadFreshTimelinePage(
          CommunityTimelineMode.me,
          refresh: true,
        );
        var cached = await service.readCachedTimeline(CommunityTimelineMode.me);
        expect(cached!.single.id, 900);
        expect(cached.single.user.username, 'alice');
        expect(cached.single.content, '测试短评');

        website = false;
        final stale = await service.loadFreshTimelinePage(
          CommunityTimelineMode.me,
          refresh: true,
        );
        expect(stale.items.single.id, 100);
        cached = await service.readCachedTimeline(CommunityTimelineMode.me);
        expect(cached!.single.id, 900);

        apiId = 1000;
        await service.loadFreshTimelinePage(
          CommunityTimelineMode.me,
          refresh: true,
        );
        cached = await service.readCachedTimeline(CommunityTimelineMode.me);
        expect(cached!.single.id, 1000);
        service.dispose();
      },
    );

    test('another user timeline never replaces the own snapshot', () async {
      final service = _service(
        [],
        (_) async => _page(900, author: false),
        cache: cache,
      );
      service.setCurrentUsername('alice');
      final result = await service.loadFreshTimelinePage(
        CommunityTimelineMode.all,
        username: 'bob',
        refresh: true,
      );
      expect(result.items.single.user.username, 'bob');
      expect(
        await service.readCachedTimeline(CommunityTimelineMode.all),
        isNull,
      );
      service.dispose();
    });
  });

  test('only login problems ask the user to verify the website', () async {
    final service = _service([], (options) async {
      if (options.path.startsWith('/ajax/')) throw StateError('offline');
      return '';
    });
    service.setCurrentUsername('alice');
    Future<CommunityTimelinePageResult> load() => service.loadFreshTimelinePage(
      CommunityTimelineMode.friends,
      refresh: true,
    );

    var result = await load();
    expect(result.websiteLoginRequired, isTrue);
    expect(result.items.single.id, 100);

    service.websiteSessionGuard = () async =>
        throw const WebsiteAccessException(
          WebsiteAccessStatus.expired,
          '网页版登录已过期',
        );
    result = await load();
    expect(result.websiteLoginRequired, isTrue);

    service.websiteSessionGuard = () async => _session();
    result = await load();
    expect(result.websiteLoginRequired, isFalse);
    expect(result.notice, contains('当前内容可能滞后'));
    service.dispose();
  });
}

WebsiteSessionSnapshot _session({String cookie = 'synthetic-cookie'}) =>
    WebsiteSessionSnapshot(
      cookies: [WebsiteCookie(name: 'chii_auth', value: cookie)],
      syncedAt: DateTime.now(),
    ).withVerifiedUser(1);

CommunityService _service(
  List<RequestOptions> requests,
  Future<String> Function(RequestOptions) html, {
  CommunityCache? cache,
  int Function()? apiId,
}) {
  final web = Dio(BaseOptions(baseUrl: 'https://bgm.tv'));
  final api = Dio(BaseOptions(baseUrl: 'https://next.bgm.tv'));
  web.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) async {
        requests.add(options);
        try {
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: await html(options),
            ),
          );
        } catch (error) {
          handler.reject(DioException(requestOptions: options, error: error));
        }
      },
    ),
  );
  api.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        handler.resolve(
          Response(
            requestOptions: options,
            statusCode: 200,
            data: [
              {
                'id': apiId?.call() ?? 100,
                'uid': 1,
                'user': {'id': 1, 'username': 'alice', 'nickname': 'Alice'},
                'createdAt': 1792168423,
                'cat': 5,
                'type': 1,
                'memo': {
                  'status': {'tsukkomi': '旧动态'},
                },
              },
            ],
          ),
        );
      },
    ),
  );
  return CommunityService.test(htmlDio: web, p1Dio: api, cache: cache);
}

String _page(int id, {bool author = true, bool next = false}) =>
    '''
<div id="timeline"><ul><li id="tml_$id">
<span class="info_full">
${author ? '<a href="/user/alice">Alice</a>' : ''} 看过 <a href="/subject/ep/3">ep.3 测试</a>
<div class="collectInfo"><div class="comment">测试短评</div></div>
<div class="card"><a href="/subject/123"><img src="//lain.bgm.tv/cover.jpg"></a><p class="title"><a href="/subject/123">测试作品</a></p></div>
<div class="post_actions date"><span title="2026-10-21 01:52">刚刚</span> · web</div>
</span></li></ul><div id="tmlPager">${next ? '<a href="?page=2">下一页</a>' : ''}</div></div>
''';
