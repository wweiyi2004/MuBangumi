import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:banjian_server/banjian_server.dart';

/// A bounded loopback load check. It is not a substitute for hotspot/phone tests.
Future<void> main(List<String> args) async {
  final seconds = args.isEmpty ? 120 : int.parse(args.first);
  final delta = args.contains('--delta');
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
  for (var i = 1; i < 10; i++)
    store.admin({
      'op': newSecret(),
      'event': id,
      'version': store.info(id)['version'],
      'action': 'add',
      'subject': {
        'id': i + 1,
        'title': '历史番单 $i',
        'summary': List.filled(40, '用于验证增量同步的简介。').join(),
        'cover': '',
      },
    });
  store.admin({
    'op': newSecret(),
    'event': id,
    'version': store.info(id)['version'],
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
  var notifications = 0, bytesReceived = 0;
  bool closing = false;
  final snapshots = <int, Json>{};
  final fetching = List.filled(50, false), dirty = List.filled(50, false);
  void observe(int index, Json data) {
    snapshots[index] = data;
    received++;
    final score = data['rounds'][0]['myScore'];
    if (score is int) {
      observed[index] = score;
      final gate = pending[index];
      if (gate != null && !gate.isCompleted) gate.complete();
    }
  }

  Future<void> pull(int index) async {
    dirty[index] = true;
    if (fetching[index] || closing) return;
    fetching[index] = true;
    try {
      do {
        dirty[index] = false;
        final old = snapshots[index];
        final uri = Uri.parse('http://127.0.0.1:${server.port}/api/state')
            .replace(
              queryParameters: {
                'event': id,
                if (old != null) 'since': '${old['revision']}',
                if (old?['serverEpoch'] != null) 'epoch': old!['serverEpoch'],
              },
            );
        final r = await client.getUrl(uri);
        r.headers.set('Authorization', 'Bearer ${tokens[index]}');
        final response = await r.close();
        final bytes = await response.fold<List<int>>(
          [],
          (all, chunk) => all..addAll(chunk),
        );
        bytesReceived += bytes.length;
        if (response.statusCode != 200)
          throw StateError('state HTTP ${response.statusCode}');
        observe(
          index,
          mergeRoomSnapshot(old, jsonDecode(utf8.decode(bytes)) as Json),
        );
      } while (dirty[index] && !closing);
    } catch (error) {
      if (!closing) {
        final gate = pending[index];
        if (gate != null && !gate.isCompleted) gate.completeError(error);
      }
    } finally {
      fetching[index] = false;
    }
  }

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
        bytesReceived += utf8.encode(raw as String).length;
        final data = jsonDecode(raw) as Json;
        if (data['type'] == 'invalidate') {
          notifications++;
          unawaited(pull(index));
        } else {
          observe(index, data);
        }
      });
      ws.add(
        jsonEncode({
          'token': tokens[i],
          'event': id,
          if (delta) 'updates': 'invalidate',
        }),
      );
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
      'catalogRounds': 10,
      'mode': delta ? 'invalidation + HTTP deltas' : 'legacy full snapshots',
      'payloadBytesReceived': bytesReceived,
      'receivedNotifications': notifications,
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
      '../../docs/qa/architecture-fixes/load-${delta ? 'delta' : 'full'}.json',
    );
    await output.parent.create(recursive: true);
    await output.writeAsString(
      const JsonEncoder.withIndent('  ').convert(report),
    );
    stdout.writeln(jsonEncode(report));
  } finally {
    closing = true;
    client.close(force: true);
    for (final ws in clients) {
      await ws.close();
    }
    await server.close();
    while (fetching.any((v) => v)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    store.close();
    await temp.delete(recursive: true);
  }
}
