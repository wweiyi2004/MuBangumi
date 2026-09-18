import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:banjian_server/banjian_server.dart';

/// A bounded loopback load check. It is not a substitute for hotspot/phone tests.
Future<void> main(List<String> args) async {
  final seconds = args.isEmpty ? 120 : int.parse(args.first);
  final temp = await Directory.systemTemp.createTemp('banjian-load-');
  final store = RoomStore('${temp.path}/room.sqlite');
  final server = RoomServer(
    autoCacheCovers: false,
    store: store,
    adminPassword: 'load-test-password',
    assets: {},
  );
  await server.start(port: 0, address: InternetAddress.loopbackIPv4);
  final id = store.create({'op': newSecret(), 'title': '负载测试'})['id'];
  store.admin({
    'op': newSecret(),
    'event': id,
    'version': 1,
    'action': 'add',
    'subject': {'id': 1, 'title': '负载测试', 'summary': '', 'cover': ''},
  });
  final round = store.event(id)['rounds'][0]['id'];
  store.admin({
    'op': newSecret(),
    'event': id,
    'version': 2,
    'action': 'start',
    'round': round,
  });
  final invite = store.event(id)['invite'];
  final tokens = List.generate(50, (_) => newSecret());
  final clients = <WebSocket>[];
  final observed = <int, int>{};
  final pending = <int, Completer<void>>{};
  final client = HttpClient();
  final delays = <int>[];
  var received = 0, submitted = 0;
  Future<void> post(String token, Json body) async {
    final r = await client.postUrl(
      Uri.parse('http://127.0.0.1:${server.port}/api/command'),
    );
    r.headers.contentType = ContentType.json;
    r.headers.set('Authorization', 'Bearer $token');
    r.write(jsonEncode(body));
    final response = await r.close();
    await response.drain<void>();
    if (response.statusCode != 200)
      throw StateError('HTTP ${response.statusCode}');
  }

  try {
    for (var i = 0; i < tokens.length; i++) {
      store.join({
        'op': newSecret(),
        'event': id,
        'invite': invite,
        'token': tokens[i],
        'name': '负载客户端$i',
      });
      final ws = await WebSocket.connect('ws://127.0.0.1:${server.port}/ws');
      clients.add(ws);
      final index = i;
      ws.listen((raw) {
        received++;
        final data = jsonDecode(raw as String) as Json;
        final score = data['rounds'][0]['myScore'];
        if (score is int) {
          observed[index] = score;
          final gate = pending[index];
          if (gate != null && !gate.isCompleted) gate.complete();
        }
      });
      ws.add(jsonEncode({'token': tokens[i], 'event': id}));
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final elapsed = Stopwatch()..start();
    var cycle = 0;
    while (elapsed.elapsed.inSeconds < seconds) {
      final value = cycle % 10 + 1;
      await Future.wait(
        List.generate(50, (i) async {
          final timer = Stopwatch()..start();
          final gate = Completer<void>();
          pending[i] = gate;
          await post(tokens[i], {
            'op': newSecret(),
            'event': id,
            'round': round,
            'action': 'score',
            'score': value,
          });
          submitted++;
          while (observed[i] != value) {
            await gate.future.timeout(const Duration(seconds: 5));
            if (observed[i] != value) {
              pending[i] = Completer<void>();
              await pending[i]!.future.timeout(const Duration(seconds: 5));
            }
          }
          delays.add(timer.elapsedMicroseconds);
          pending.remove(i);
        }),
      );
      cycle++;
      if (cycle % 5 == 0)
        stdout.writeln(
          'Load check ${elapsed.elapsed.inSeconds}s / ${seconds}s',
        );
      await Future<void>.delayed(const Duration(seconds: 5));
    }
    delays.sort();
    final report = {
      'transport': 'Windows loopback HTTP + WebSocket',
      'clients': 50,
      'durationSeconds': elapsed.elapsed.inSeconds,
      'acknowledgedWrites': submitted,
      'receivedSnapshots': received,
      'uniqueScores': store.view(id, admin: true)['rounds'][0]['count'],
      'p95AcknowledgementAndOwnSnapshotMs':
          delays[(delays.length * .95).floor().clamp(0, delays.length - 1)] /
          1000,
      'maxMs': delays.last / 1000,
    };
    if (report['uniqueScores'] != 50) throw StateError('score count mismatch');
    final output = File(
      '../../docs/qa/banjian-implementation/load-results.json',
    );
    await output.parent.create(recursive: true);
    await output.writeAsString(
      const JsonEncoder.withIndent('  ').convert(report),
    );
    stdout.writeln(jsonEncode(report));
  } finally {
    client.close(force: true);
    for (final ws in clients) {
      await ws.close();
    }
    await server.close();
    store.close();
    await temp.delete(recursive: true);
  }
}
