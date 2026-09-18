import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:banjian_server/banjian_server.dart';
import 'package:test/test.dart';

void main() {
  test(
    'shutdown closes an upgrade that finishes after the socket sweep',
    () async {
      final store = RoomStore(':memory:');
      final upgraded = Completer<void>();
      final release = Completer<void>();
      final server = RoomServer(
        store: store,
        adminPassword: 'test-management-password',
        assets: {},
        autoCacheCovers: false,
        upgradeWebSocket: (request) async {
          final socket = await WebSocketTransformer.upgrade(request);
          upgraded.complete();
          await release.future;
          return socket;
        },
      );
      await server.start(port: 0, address: InternetAddress.loopbackIPv4);
      final client = await WebSocket.connect(
        'ws://127.0.0.1:${server.port}/ws',
      );
      final closed = Completer<void>();
      client.listen((_) {}, onDone: closed.complete);
      addTearDown(() async {
        if (!release.isCompleted) release.complete();
        await client.close();
        await server.close();
        store.close();
      });
      await upgraded.future;
      await server.close();
      release.complete();
      await closed.future.timeout(const Duration(seconds: 2));
      expect(client.closeCode, 1001);
    },
  );

  late Directory temp;
  late RoomStore store;
  late RoomServer server;
  late Uri base;
  late String admin, id, invite, round, member;
  Future<({int status, dynamic body})> request(
    String path, {
    Json? body,
    String token = '',
    String? origin,
  }) async {
    final client = HttpClient();
    try {
      final req = await client.openUrl(
        body == null ? 'GET' : 'POST',
        base.resolve(path),
      );
      req.headers.contentType = ContentType.json;
      if (token.isNotEmpty) req.headers.set('Authorization', 'Bearer $token');
      if (origin != null) req.headers.set('Origin', origin);
      if (body != null) req.write(jsonEncode(body));
      final res = await req.close();
      final text = await utf8.decodeStream(res);
      dynamic value;
      try {
        value = jsonDecode(text);
      } catch (_) {
        value = text;
      }
      return (status: res.statusCode, body: value);
    } finally {
      client.close(force: true);
    }
  }

  Future<Json> cmd(String action, [Json data = const {}]) async {
    final e = store.event(id);
    final res = await request(
      '/api/admin',
      token: admin,
      body: {
        'op': newSecret(),
        'event': id,
        'version': e['version'],
        'action': action,
        ...data,
      },
    );
    expect(res.status, 200, reason: res.body.toString());
    return res.body as Json;
  }

  Future<void> restart() async {
    await server.close();
    store.close();
    store = RoomStore('${temp.path}/room.sqlite');
    server = RoomServer(
      autoCacheCovers: false,
      store: store,
      adminPassword: 'test-management-password',
      assets: {'index.html': utf8.encode('<!doctype html><title>test</title>')},
    );
    await server.start(port: 0, address: InternetAddress.loopbackIPv4);
    base = Uri.parse('http://127.0.0.1:${server.port}');
    admin = (await request(
      '/api/login',
      body: {'password': 'test-management-password'},
    )).body['token'];
  }

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('banjian-test-');
    store = RoomStore('${temp.path}/room.sqlite');
    server = RoomServer(
      autoCacheCovers: false,
      store: store,
      adminPassword: 'test-management-password',
      assets: {'index.html': utf8.encode('<!doctype html><title>test</title>')},
    );
    await server.start(port: 0, address: InternetAddress.loopbackIPv4);
    base = Uri.parse('http://127.0.0.1:${server.port}');
    admin = (await request(
      '/api/login',
      body: {'password': 'test-management-password'},
    )).body['token'];
    id = (await request(
      '/api/admin',
      token: admin,
      body: {'op': newSecret(), 'action': 'create', 'title': '周五番键会'},
    )).body['id'];
    await cmd('add', {
      'subject': {'id': 1, 'title': '测试动画', 'summary': '离线快照', 'cover': ''},
    });
    round = (store.event(id)['rounds'] as List).first['id'];
    await cmd('start', {'round': round});
    invite = store.event(id)['invite'];
    member = newSecret();
    expect(
      (await request(
        '/api/join',
        body: {
          'op': newSecret(),
          'event': id,
          'invite': invite,
          'token': member,
          'name': '小明',
        },
      )).status,
      200,
    );
  });
  tearDown(() async {
    await server.close();
    store.close();
    await temp.delete(recursive: true);
  });
  Json score(int value, {String? op}) => {
    'op': op ?? newSecret(),
    'event': id,
    'round': round,
    'action': 'score',
    'score': value,
  };

  test(
    'participant projection never leaks names, credentials or hidden aggregate',
    () async {
      await request('/api/command', token: member, body: score(8));
      final view =
          (await request('/api/state?event=$id', token: member)).body as Json;
      expect(view.containsKey('members'), false);
      expect(view.containsKey('invite'), false);
      expect(view['rounds'][0].containsKey('stats'), false);
      expect(view['rounds'][0]['myScore'], 8);
      expect(jsonEncode(view).contains(digest(member)), false);
      final management = store.view(id, admin: true);
      expect(management['members'], [
        {'name': '小明', 'submitted': true},
      ]);
      expect(management['rounds'][0]['myScore'], null);
      final export = store.export(id);
      expect(jsonEncode(export).contains('小明'), false);
      expect(export.containsKey('invite'), false);
      await cmd('publish', {'round': round, 'value': true});
      expect(store.view(id, token: member)['rounds'][0]['stats']['mean'], 8);
    },
  );
  test('authorization and same origin enforcement', () async {
    expect((await request('/api/history', token: member)).status, 401);
    expect(
      (await request(
        '/api/admin',
        token: member,
        body: {'op': newSecret(), 'action': 'end', 'event': id},
      )).status,
      401,
    );
    expect((await request('/api/state?event=$id')).status, 401);
    expect(
      (await request(
        '/api/export?event=$id&format=json',
        token: member,
      )).status,
      401,
    );
    expect(
      (await request(
        '/api/login',
        body: {'password': 'test-management-password'},
        origin: 'https://evil.example',
      )).status,
      403,
    );
    expect(
      (await request(
        '/api/preview',
        body: {'event': id, 'invite': 'wrong'},
      )).status,
      403,
    );
    expect((await request('/api/health', origin: base.origin)).status, 200);
  });
  test(
    'discovery proves the invitation without disclosing the secret or member data',
    () async {
      final nonce = newSecret();
      final result = await request(
        '/api/locate',
        body: {'event': id, 'nonce': nonce},
      );
      expect(result.status, 200);
      expect(result.body['proof'], roomLocationProof(invite, id, nonce));
      expect(result.body['event'], id);
      expect(jsonEncode(result.body).contains(invite), false);
      expect(result.body.containsKey('members'), false);
      expect(
        (await request(
          '/api/locate',
          body: {'event': id, 'nonce': 'short'},
        )).status,
        400,
      );
      expect(
        (await request('/api/invitation?event=$id', token: member)).status,
        401,
      );
      final link = await request('/api/invitation?event=$id', token: admin);
      expect(RoomInvite.parse(link.body['url'])!.eventId, id);
      expect(link.body['qr'], contains('<svg'));
      expect(link.body['localOnly'], true);
    },
  );
  test('idempotent score and comment, immutable operation payload', () async {
    final c = score(7);
    expect((await request('/api/command', token: member, body: c)).status, 200);
    expect((await request('/api/command', token: member, body: c)).status, 200);
    expect(
      (await request(
        '/api/command',
        token: member,
        body: {...c, 'score': 9},
      )).status,
      409,
    );
    await request('/api/command', token: member, body: score(9));
    final comment = {
      'op': newSecret(),
      'event': id,
      'round': round,
      'action': 'comment',
      'text': '<script>alert(1)</script>',
    };
    expect(
      (await request('/api/command', token: member, body: comment)).status,
      200,
    );
    expect(
      (await request('/api/command', token: member, body: comment)).status,
      200,
    );
    final r = store.view(id, token: member)['rounds'][0];
    expect(r['count'], 1);
    expect(r['myScore'], 9);
    expect(r['comments'].length, 1);
    expect(
      (await request(
        '/api/command',
        token: member,
        body: {...comment, 'op': newSecret(), 'text': 'too fast'},
      )).status,
      429,
    );
  });
  test(
    'ended rooms cannot issue new invitations and history keeps the active room first',
    () async {
      final title = store.event(id)['title'];
      await cmd('end');
      final created = await request(
        '/api/admin',
        token: admin,
        body: {'op': newSecret(), 'action': 'create', 'title': title},
      );
      expect(created.status, 200);
      final newId = created.body['id'] as String;
      // Updating an old record must not move it ahead of the active activity.
      await cmd('rename', {'title': title});
      expect(store.history().first['id'], newId);
      expect(
        (await request('/api/invitation?event=$id', token: admin)).status,
        409,
      );
      expect((await request('/api/qr?event=$id', token: admin)).status, 409);
      expect(
        (await request('/api/invitation?event=$newId', token: admin)).status,
        200,
      );
      expect(store.preview(id, invite)['ended'], true);
      expect(
        store.preview(newId, store.event(newId)['invite'])['ended'],
        false,
      );
    },
  );
  test('acknowledged writes and operation receipts survive restart', () async {
    final c = score(10);
    await request('/api/command', token: member, body: c);
    await restart();
    expect(store.view(id, token: member)['rounds'][0]['myScore'], 10);
    expect((await request('/api/command', token: member, body: c)).status, 200);
    expect(store.view(id, token: member)['rounds'][0]['count'], 1);
  });
  test(
    'old round writes rejected and successful receipt replay allowed after close',
    () async {
      final old = score(8);
      await request('/api/command', token: member, body: old);
      await cmd('close', {'round': round});
      expect(
        (await request('/api/command', token: member, body: score(4))).status,
        409,
      );
      expect(
        (await request('/api/command', token: member, body: old)).status,
        200,
      );
      await cmd('add', {
        'subject': {'id': 2, 'title': '下一部', 'summary': '', 'cover': ''},
      });
      final second = store.event(id)['rounds'][1]['id'];
      await cmd('start', {'round': second});
      expect(
        (await request('/api/command', token: member, body: score(3))).status,
        409,
      );
      expect(store.view(id, token: member)['rounds'][1]['count'], 0);
    },
  );
  test('pause, resume, end and closed round reopening rules', () async {
    await cmd('pause', {'round': round});
    expect(
      (await request('/api/command', token: member, body: score(8))).status,
      409,
    );
    await cmd('resume', {'round': round});
    expect(
      (await request('/api/command', token: member, body: score(8))).status,
      200,
    );
    await cmd('close', {'round': round});
    expect(
      (await request(
        '/api/admin',
        token: admin,
        body: {
          'op': newSecret(),
          'event': id,
          'version': store.event(id)['version'],
          'action': 'resume',
          'round': round,
        },
      )).status,
      409,
    );
    await cmd('end');
    expect(
      (await request('/api/command', token: member, body: score(8))).status,
      409,
    );
  });
  test(
    'concurrent management writes use structural version, scores do not conflict',
    () async {
      final version = store.event(id)['version'];
      await request('/api/command', token: member, body: score(8));
      expect(store.event(id)['version'], version);
      final body = {
        'op': newSecret(),
        'event': id,
        'version': version,
        'action': 'rename',
        'title': '改名',
      };
      expect(
        (await request('/api/admin', token: admin, body: body)).status,
        200,
      );
      expect(
        (await request(
          '/api/admin',
          token: admin,
          body: {...body, 'op': newSecret(), 'title': '覆盖'},
        )).status,
        409,
      );
      expect(store.event(id)['title'], '改名');
    },
  );
  test(
    'comments private until enabled, hide removes from other participant view',
    () async {
      final other = newSecret();
      await request(
        '/api/join',
        body: {
          'op': newSecret(),
          'event': id,
          'invite': invite,
          'token': other,
          'name': '小红',
        },
      );
      await request(
        '/api/command',
        token: member,
        body: {
          'op': newSecret(),
          'event': id,
          'round': round,
          'action': 'comment',
          'text': '喜欢',
        },
      );
      expect(store.view(id, token: other)['rounds'][0]['comments'], isEmpty);
      await cmd('comments', {'round': round, 'value': true});
      final comments = store.view(id, token: other)['rounds'][0]['comments'];
      expect(comments.length, 1);
      expect(comments[0].containsKey('actor'), false);
      await cmd('hide', {
        'round': round,
        'comment': comments[0]['id'],
        'value': true,
      });
      expect(store.view(id, token: other)['rounds'][0]['comments'], isEmpty);
      expect(
        store.view(id, token: member)['rounds'][0]['comments'][0]['hidden'],
        true,
      );
    },
  );
  test(
    'invitation rotation blocks new admission without revoking existing votes',
    () async {
      await cmd('rotateInvite');
      expect(
        (await request(
          '/api/join',
          body: {
            'op': newSecret(),
            'event': id,
            'invite': invite,
            'token': newSecret(),
            'name': 'new',
          },
        )).status,
        403,
      );
      expect(
        (await request('/api/command', token: member, body: score(8))).status,
        200,
      );
    },
  );
  test('rejoining with same token is one identity even after end', () async {
    await cmd('end');
    expect(
      (await request(
        '/api/join',
        body: {
          'op': newSecret(),
          'event': id,
          'invite': invite,
          'token': member,
          'name': '改名',
        },
      )).status,
      200,
    );
    expect(store.view(id, admin: true)['memberCount'], 1);
    expect(
      (await request(
        '/api/join',
        body: {
          'op': newSecret(),
          'event': id,
          'invite': invite,
          'token': newSecret(),
          'name': '新用户',
        },
      )).status,
      409,
    );
  });
  test(
    'CSV neutralizes formula prefixes, exports anonymous data only',
    () async {
      await request(
        '/api/command',
        token: member,
        body: {
          'op': newSecret(),
          'event': id,
          'round': round,
          'action': 'comment',
          'text': '=HYPERLINK("https://example.com")',
        },
      );
      final csv = store.csv(id, comments: true);
      expect(csv, contains("'=HYPERLINK"));
      expect(csv, isNot(contains('小明')));
      expect(
        (await request(
          '/api/export?event=$id&format=json',
          token: admin,
        )).status,
        200,
      );
    },
  );
  test(
    'validation rejects invalid scores, oversized text and malformed input',
    () async {
      for (final value in [0, 11])
        expect(
          (await request(
            '/api/command',
            token: member,
            body: score(value),
          )).status,
          400,
        );
      expect(
        (await request(
          '/api/command',
          token: member,
          body: {...score(8), 'score': 8.5},
        )).status,
        400,
      );
      expect(
        (await request(
          '/api/command',
          token: member,
          body: {
            'op': newSecret(),
            'event': id,
            'round': round,
            'action': 'comment',
            'text': 'x' * 501,
          },
        )).status,
        400,
      );
      expect(
        (await request(
          '/api/join',
          body: {
            'op': newSecret(),
            'event': id,
            'invite': invite,
            'token': 'short',
            'name': 'x',
          },
        )).status,
        400,
      );
    },
  );
  test(
    'websocket sends role filtered snapshot and stops after logout',
    () async {
      final ws = await WebSocket.connect('ws://127.0.0.1:${server.port}/ws');
      final messages = <Json>[];
      ws.listen((v) => messages.add(jsonDecode(v as String) as Json));
      ws.add(jsonEncode({'event': id, 'token': member}));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(messages, isNotEmpty);
      expect(messages.last['rounds'][0].containsKey('stats'), false);
      await request('/api/command', token: member, body: score(6));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(messages.last['rounds'][0]['myScore'], 6);
      await ws.close();
      final management = await WebSocket.connect(
        'ws://127.0.0.1:${server.port}/ws',
      );
      final done = Completer<void>();
      management.listen((_) {}, onDone: () => done.complete());
      management.add(jsonEncode({'event': id, 'token': admin}));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await request('/api/logout', token: admin, body: {});
      await done.future.timeout(const Duration(seconds: 2));
      expect(management.closeCode, 1008);
    },
  );
  test(
    'QR is real SVG for participant link, assets are served without CDN',
    () async {
      final qr = await request('/api/qr?event=$id', token: admin);
      expect(qr.status, 200);
      expect(qr.body, contains('<svg'));
      expect(qr.body, contains('<rect'));
      expect((await request('/admin')).status, 200);
      expect((await request('/join/$id')).status, 200);
      expect((await request('/room.sqlite')).status, 404);
      expect((await request('/api/qr?event=$id', token: member)).status, 401);
    },
  );
  test('50 concurrent identities update without lost scores', () async {
    final tokens = List.generate(50, (_) => newSecret());
    await Future.wait(
      tokens.asMap().entries.map(
        (entry) => request(
          '/api/join',
          body: {
            'op': newSecret(),
            'event': id,
            'invite': invite,
            'token': entry.value,
            'name': '测试${entry.key}',
          },
        ),
      ),
    );
    final timer = Stopwatch()..start();
    final results = await Future.wait(
      tokens.map((t) => request('/api/command', token: t, body: score(8))),
    );
    expect(results.every((r) => r.status == 200), true);
    expect(store.view(id, admin: true)['rounds'][0]['count'], 50);
    // Diagnostic only: physical LAN and long-duration targets are separate.
    print(
      '50 concurrent loopback score acknowledgements: ${timer.elapsedMilliseconds} ms',
    );
  });
  test(
    'invite decoder permits only known route and safe local / TLS transports',
    () {
      final valid = RoomInvite(base, id, invite).url;
      expect(RoomInvite.parse(valid)?.eventId, id);
      expect(
        RoomInvite.parse(valid.replaceFirst('127.0.0.1', '8.8.8.8')),
        null,
      );
      expect(RoomInvite.parse(valid.replaceFirst('/join/', '/admin/')), null);
      expect(RoomInvite.parse('file:///join/$id#invite=$invite'), null);
      expect(RoomInvite.parse('https://example.com/join/$id#invite=%'), null);
      expect(
        RoomInvite.parse(
          'https://example.com/join/$id#invite=$invite',
        )?.eventId,
        id,
      );
    },
  );
}
