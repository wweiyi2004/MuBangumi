import 'dart:io';
import 'dart:async';
import 'package:banjian_server/banjian_server.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/features/anime_appreciation/room_host.dart';
import 'package:mubangumi/features/anime_appreciation/room_connection.dart';
import 'banjian_participation_test.dart' show MemoryParticipation;

class LostAdminResponse extends RoomApi {
  LostAdminResponse(RoomApi previous)
    : super(previous.base, token: previous.token);
  bool lose = true;
  @override
  Future<Json> request(String path, [Json? body]) async {
    final data = await super.request(path, body);
    if (path == 'admin' && lose) {
      lose = false;
      throw const SocketException('lost response after commit');
    }
    return data;
  }
}

class DelayedStateResponse extends RoomApi {
  DelayedStateResponse(RoomApi previous)
    : super(previous.base, token: previous.token);
  final captured = Completer<void>(), release = Completer<void>();
  @override
  Future<Json> request(String path, [Json? body]) async {
    final data = await super.request(path, body);
    if (path.startsWith('state?') && !captured.isCompleted) {
      captured.complete();
      await release.future;
    }
    return data;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  test(
    'host follows a new browser-created activity instead of sharing the ended room',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'banjian-active-room-',
      );
      final host = RoomHost(
        autoCacheCovers: false,
        directory: () async => temp,
        commandStorage: MemoryParticipation(),
        port: 0,
      );
      addTearDown(() async {
        await host.stop();
        host.dispose();
        await temp.delete(recursive: true);
      });
      await host.start();
      await host.command('create', {'title': '同名活动'});
      final old = host.event!['id'];
      final external = RoomApi(host.base!, token: host.api!.token);
      await external.request('admin', {
        'op': newSecret(),
        'event': old,
        'version': host.event!['version'],
        'action': 'end',
      });
      final created = await external.request('admin', {
        'op': newSecret(),
        'action': 'create',
        'title': '同名活动',
      });
      await host.refresh();
      expect(host.event!['id'], created['id']);
      expect(host.event!['ended'], false);
      final link = await host.prepareInvite();
      expect(link.eventId, created['id']);
      await host.refresh(eventId: old);
      expect(host.event!['id'], old);
      expect(() => host.makeInvite(), throwsA(isA<RoomError>()));
    },
  );
  test(
    'embedded host isolates the server, loads bundled pages and restores SQLite activity',
    () async {
      final temp = await Directory.systemTemp.createTemp('banjian-host-');
      final storage = MemoryParticipation();
      final host = RoomHost(
        autoCacheCovers: false,
        directory: () async => temp,
        commandStorage: storage,
        port: 0,
      );
      addTearDown(() async {
        await host.stop();
        host.dispose();
        await temp.delete(recursive: true);
      });
      await host.start();
      expect(host.running, true);
      expect(host.password, isNotEmpty);
      final api = RoomApi(host.base!);
      expect((await api.request('health'))['service'], 'mubangumi-banjian');
      final client = HttpClient();
      final res = await (await client.getUrl(
        host.base!.resolve('/admin'),
      )).close();
      expect(res.statusCode, 200);
      await res.drain<void>();
      client.close(force: true);
      await host.command('create', {'title': '真实隔离服务测试'});
      final id = host.event!['id'];
      expect(host.history.length, 1);
      await host.command('add', {
        'subject': {'id': 1, 'title': '测试动画', 'summary': '', 'cover': ''},
      });
      expect(host.event!['rounds'].length, 1);
      host.api = LostAdminResponse(host.api!);
      await expectLater(
        host.command('add', {
          'subject': {'id': 2, 'title': '响应丢失测试', 'summary': '', 'cover': ''},
        }),
        throwsA(isA<SocketException>()),
      );
      expect(host.hasPendingCommand, true);
      await host.retryCommand();
      expect(host.event!['rounds'].length, 2);
      expect(host.hasPendingCommand, false);
      final external = RoomApi(host.base!, token: host.api!.token);
      final version = host.event!['version'];
      await external.request('admin', {
        'op': newSecret(),
        'event': id,
        'version': version,
        'action': 'rename',
        'title': '网页同步到原生',
      });
      for (var i = 0; i < 100 && host.event?['title'] != '网页同步到原生'; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(host.event!['title'], '网页同步到原生');
      expect(host.liveConnected, true);
      final delayed = DelayedStateResponse(host.api!);
      host.api = delayed;
      final reload = host.refresh();
      await delayed.captured.future;
      await external.request('admin', {
        'op': newSecret(),
        'event': id,
        'version': host.event!['version'],
        'action': 'rename',
        'title': '保留较新的实时状态',
      });
      for (var i = 0; i < 100 && host.event?['title'] != '保留较新的实时状态'; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      delayed.release.complete();
      await reload;
      expect(host.event!['title'], '保留较新的实时状态');
      final exported = await external.download(
        'export?event=$id&format=scores',
      );
      expect(exported, isNotEmpty);
      final oldPassword = host.password;
      await host.stop();
      expect(host.running, false);
      await host.start();
      expect(host.event!['id'], id);
      expect(host.password, isNot(oldPassword));
      expect(host.event!['rounds'].length, 2);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
