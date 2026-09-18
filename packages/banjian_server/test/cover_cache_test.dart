import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:banjian_server/banjian_server.dart';
import 'package:test/test.dart';

final png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aK1sAAAAASUVORK5CYII=',
);
void main() {
  late RoomStore store;
  late Directory temp;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('banjian-covers-');
    store = RoomStore('${temp.path}/room.sqlite');
  });
  tearDown(() async {
    store.close();
    await temp.delete(recursive: true);
  });
  test(
    'selected collection cover URL caches locally without metadata lookup',
    () async {
      var downloads = 0;
      final cache = RoomCoverCache(
        store,
        lookup: (_) async => throw StateError('must use selected image'),
        loader: (uri) async {
          downloads++;
          expect(uri.scheme, 'https');
          return RoomCoverImage(png, 'image/png');
        },
      );
      final subject = <String, dynamic>{
        'id': 1,
        'cover': '',
        'coverSource': 'http://lain.bgm.tv/pic/cover/l/demo.png',
      };
      final key = await cache.ensure(subject);
      expect(cache.contains(key), true);
      expect(await cache.ensure(subject), key);
      expect(downloads, 1);
    },
  );
  test(
    'legacy snapshots with no image URL resolve metadata and cache bytes',
    () async {
      var lookedUp = 0;
      final cache = RoomCoverCache(
        store,
        lookup: (id) async {
          lookedUp = id;
          return 'https://lain.bgm.tv/pic/cover/l/legacy.png';
        },
        loader: (_) async => RoomCoverImage(png, 'image/png'),
      );
      final key = await cache.ensure({'id': 282, 'cover': ''});
      expect(lookedUp, 282);
      expect(cache.contains(key), true);
    },
  );
  test(
    'foreign image targets and non-image responses are never cached',
    () async {
      expect(roomCoverUri('https://127.0.0.1/pic/cover/l/a.png'), null);
      expect(roomCoverUri('https://lain.bgm.tv:8443/pic/cover/l/a.png'), null);
      expect(
        roomCoverUri('https://user:password@lain.bgm.tv/pic/cover/l/a.png'),
        null,
      );
      expect(roomCoverUri('https://lain.bgm.tv/settings'), null);
      final cache = RoomCoverCache(
        store,
        lookup: (_) async => 'https://lain.bgm.tv/pic/cover/l/a.png',
        loader: (_) async =>
            RoomCoverImage(utf8.encode('<html>error</html>'), 'image/png'),
      );
      await expectLater(
        cache.ensure({'id': 1, 'cover': ''}),
        throwsA(isA<RoomError>()),
      );
      expect(
        store.db.select('SELECT count(*) AS n FROM covers').single['n'],
        0,
      );
    },
  );
  test(
    'background enrichment preserves concurrent score, comments and management version',
    () async {
      final gate = Completer<RoomCoverImage>();
      final server = RoomServer(
        store: store,
        adminPassword: 'test-cover-password',
        assets: {},
        autoCacheCovers: false,
        coverLoader: (_) => gate.future,
      );
      final id = store.create({'op': newSecret(), 'title': '封面补全'})['id'];
      void command(String action, Json fields) => store.admin({
        'op': newSecret(),
        'event': id,
        'version': store.event(id)['version'],
        'action': action,
        ...fields,
      });
      command('add', {
        'subject': {
          'id': 282,
          'title': '从收藏导入',
          'summary': '原简介',
          'cover': '',
          'coverSource': 'https://lain.bgm.tv/pic/cover/l/a.png',
        },
      });
      final round = store.event(id)['rounds'][0]['id'];
      command('start', {'round': round});
      final token = newSecret();
      store.join({
        'op': newSecret(),
        'event': id,
        'invite': store.event(id)['invite'],
        'token': token,
        'name': '参与者',
      });
      final work = server.repairCovers(id);
      store.submit(token, {
        'op': newSecret(),
        'event': id,
        'round': round,
        'action': 'score',
        'score': 8,
      });
      store.submit(token, {
        'op': newSecret(),
        'event': id,
        'round': round,
        'action': 'comment',
        'text': '正在补封面也能评分',
      });
      final version = store.event(id)['version'];
      gate.complete(RoomCoverImage(png, 'image/png'));
      await work;
      final view = store.view(id, token: token);
      final r = view['rounds'][0];
      expect(view['version'], version);
      expect(r['myScore'], 8);
      expect(r['comments'].length, 1);
      expect(r['subject']['summary'], '原简介');
      expect(r['subject']['cover'], isNotEmpty);
      await server.start(port: 0, address: InternetAddress.loopbackIPv4);
      final client = HttpClient();
      final response = await (await client.getUrl(
        Uri.parse(
          'http://127.0.0.1:${server.port}/cover/${r['subject']['cover']}',
        ),
      )).close();
      final bytes = await response.fold<List<int>>([], (a, b) => a..addAll(b));
      expect(response.statusCode, 200);
      expect(response.headers.contentType?.mimeType, 'image/png');
      expect(bytes, png);
      client.close(force: true);
      await server.close();
    },
  );
  test('failed downloads can be retried without re-adding the round', () async {
    var fail = true;
    final server = RoomServer(
      store: store,
      adminPassword: 'test-cover-password',
      assets: {},
      autoCacheCovers: false,
      coverLookup: (_) async => 'https://lain.bgm.tv/pic/cover/l/a.png',
      coverLoader: (_) async {
        if (fail) throw const SocketException('offline');
        return RoomCoverImage(png, 'image/png');
      },
    );
    final id = store.create({'op': newSecret(), 'title': '旧活动'})['id'];
    store.admin({
      'op': newSecret(),
      'event': id,
      'version': 1,
      'action': 'add',
      'subject': {'id': 1, 'title': '已有条目', 'summary': '', 'cover': ''},
    });
    await server.repairCovers(id);
    expect(store.event(id)['rounds'][0]['subject']['coverError'], isNotEmpty);
    fail = false;
    await server.repairCovers(id);
    final rounds = store.event(id)['rounds'] as List;
    expect(rounds.length, 1);
    expect(rounds[0]['subject']['cover'], isNotEmpty);
    expect(rounds[0]['subject'].containsKey('coverError'), false);
    await server.close();
  });
}
