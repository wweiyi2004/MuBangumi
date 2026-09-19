import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:banjian_server/banjian_server.dart';

/// Isolated localhost fixture; never touches the app's real activity database.
Future<void> main(List<String> args) async {
  final directory = await Directory.systemTemp.createTemp('banjian-web-');
  final store = RoomStore('${directory.path}/room.sqlite');
  final assets = <String, List<int>>{};
  for (final name in ['index.html', 'app.css', 'room_protocol.js', 'app.js']) {
    assets[name] = await File(
      'packages/banjian_server/web/$name',
    ).readAsBytes();
  }
  final server = RoomServer(
    autoCacheCovers: false,
    store: store,
    adminPassword: 'browser-test-password',
    assets: assets,
  );
  await server.start(port: 0, address: InternetAddress.loopbackIPv4);
  final id = store.create({'op': newSecret(), 'title': '周五的番键会'})['id'];
  Json command(String action, [Json extra = const {}]) => store.admin({
    'op': newSecret(),
    'event': id,
    'version': store.event(id)['version'],
    'action': action,
    ...extra,
  });
  final coverFile = File('.dart_tool/anime-ui-covers.json');
  final covers = await coverFile.exists()
      ? jsonDecode(await coverFile.readAsString()) as List
      : [];
  for (final (index, title) in ['葬送的芙莉莲', '孤独摇滚！', '跃动青春'].indexed) {
    var key = '';
    if (index < covers.length) {
      final image = covers[index]['image'] as String;
      key = digest(title);
      store.db.execute('INSERT OR REPLACE INTO covers VALUES(?,?,?)', [
        key,
        'image/jpeg',
        base64Decode(image.split(',').last),
      ]);
    }
    command('add', {
      'subject': {
        'id': index + 1,
        'title': title,
        'summary': '一起感受故事中的细节，分享这一轮的观影体验。',
        'cover': key,
      },
    });
  }
  final round = store.event(id)['rounds'][0]['id'];
  command('start', {'round': round});
  final invite = store.event(id)['invite'];
  for (var i = 0; i < 12; i++) {
    final member = newSecret();
    store.join({
      'op': newSecret(),
      'event': id,
      'invite': invite,
      'token': member,
      'name': '观众 ${i + 1}',
    });
    if (i < 9) {
      store.submit(member, {
        'op': newSecret(),
        'event': id,
        'round': round,
        'action': 'score',
        'score': 6 + i % 5,
      });
    }
    if (i < 3) {
      store.submit(member, {
        'op': newSecret(),
        'event': id,
        'round': round,
        'action': 'comment',
        'text': ['节奏很舒服，细节值得再看一遍。', '人物的情绪藏在很小的动作里。', '音乐响起来的一刻很有感染力。'][i],
      });
    }
  }
  if (args.contains('--many-comments')) {
    final actor = (store.event(id)['members'] as Map).keys.first;
    for (var i = 0; i < 120; i++) {
      store.db.execute(
        'INSERT INTO room_comments(event,round,id,actor,text,time,hidden) VALUES(?,?,?,?,?,?,0)',
        [
          id,
          round,
          'pagination-$i',
          actor,
          '较早的短评 $i',
          DateTime.now().millisecondsSinceEpoch - 1000000 + i * 4000,
        ],
      );
    }
    command('comments', {'round': round, 'value': true});
  }
  await File('.dart_tool/banjian-fixture.json').writeAsString(
    jsonEncode({
      'base': 'http://127.0.0.1:${server.port}',
      'id': id,
      'invite': invite,
      'round': round,
      'password': 'browser-test-password',
    }),
  );
  stdout.writeln('Isolated browser fixture ready.');
  final stop = Completer<void>();
  final signals = ProcessSignal.sigint.watch().listen((_) {
    if (!stop.isCompleted) stop.complete();
  });
  final input = stdin
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
        if (line == 'stop' && !stop.isCompleted) stop.complete();
      });
  await stop.future;
  await signals.cancel();
  await input.cancel();
  await server.close();
  store.close();
  await directory.delete(recursive: true);
}
