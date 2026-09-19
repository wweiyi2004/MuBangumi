import 'dart:io';
import 'dart:async';
import 'package:banjian_server/banjian_server.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/features/anime_appreciation/room_connection.dart';

class MemoryParticipation implements ParticipationStorage {
  Json? value;
  bool fail = false;
  Duration delay = Duration.zero;
  @override
  Future<Json?> read() async => value == null ? null : clone(value!);
  @override
  Future<void> write(Json next) async {
    await Future<void>.delayed(delay);
    if (fail) throw StateError('disk failure');
    value = clone(next);
  }
}

Future<void> waitUntil(
  bool Function() condition, {
  String reason = 'condition did not become true',
}) async {
  for (var i = 0; i < 200; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail(reason);
}

void main() {
  late Directory temp;
  late RoomStore store;
  late RoomServer server;
  late RoomInvite invite;
  late ParticipationController c;
  late MemoryParticipation memory;
  late String id, round;
  Json admin(String action, [Json extra = const {}]) => store.admin({
    'op': newSecret(),
    'event': id,
    'version': store.event(id)['version'],
    'action': action,
    ...extra,
  });
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('banjian-native-');
    store = RoomStore('${temp.path}/room.sqlite');
    id = store.create({'op': newSecret(), 'title': '原生参与测试'})['id'];
    admin('add', {
      'subject': {'id': 1, 'title': '第一部', 'summary': '', 'cover': ''},
    });
    round = store.event(id)['rounds'][0]['id'];
    admin('start', {'round': round});
    server = RoomServer(
      autoCacheCovers: false,
      store: store,
      adminPassword: 'test-management-password',
      assets: {},
    );
    await server.start(port: 0, address: InternetAddress.loopbackIPv4);
    invite = RoomInvite(
      Uri.parse('http://127.0.0.1:${server.port}'),
      id,
      store.event(id)['invite'],
    );
    memory = MemoryParticipation();
    c = ParticipationController(storage: memory);
    await c.join(invite, '测试昵称');
  });
  tearDown(() async {
    c.dispose();
    await server.close();
    store.close();
    await temp.delete(recursive: true);
  });
  test(
    'native submissions persist before dispatch and receive real acknowledgement',
    () async {
      await c.submit('score', score: 9);
      await waitUntil(() => c.pending.isEmpty && c.current?['myScore'] == 9);
      expect(store.view(id, admin: true)['rounds'][0]['count'], 1);
      expect(c.message, '评分已确认');
      expect(memory.value?['pending'], isEmpty);
    },
  );
  test('failed local write never dispatches an unpersisted command', () async {
    memory.fail = true;
    await expectLater(c.submit('score', score: 10), throwsStateError);
    expect(store.view(id, admin: true)['rounds'][0]['count'], 0);
    expect(c.pending, isEmpty);
  });
  test(
    'overlapping draft edits and queue acknowledgements preserve both',
    () async {
      memory.delay = const Duration(milliseconds: 20);
      await Future.wait([
        c.submit('score', score: 7),
        c.saveDraft(round, text: '输入不能被评分确认覆盖'),
        c.saveDraft(round, score: 8),
      ]);
      await waitUntil(() => c.pending.isEmpty);
      expect(c.drafts[round]['text'], '输入不能被评分确认覆盖');
      expect(c.drafts[round]['score'], 8);
      expect(memory.value!['drafts'][round]['text'], '输入不能被评分确认覆盖');
    },
  );
  test('offline queue survives controller restart and replays once', () async {
    final port = server.port;
    await server.close();
    await waitUntil(
      () => !c.online,
      reason: 'participant stayed online after server shutdown',
    );
    await c.submit('score', score: 6);
    expect(c.pending.length, 1);
    c.dispose();
    c = ParticipationController(storage: memory);
    await c.restore();
    server = RoomServer(
      autoCacheCovers: false,
      store: store,
      adminPassword: 'test-management-password',
      assets: {},
    );
    await server.start(port: port, address: InternetAddress.loopbackIPv4);
    await c.refresh();
    await waitUntil(
      () => c.pending.isEmpty && c.current?['myScore'] == 6,
      reason:
          'restarted participant did not receive queued score acknowledgement',
    );
    expect(store.view(id, admin: true)['rounds'][0]['count'], 1);
  });
  test(
    'late offline comment rejected on its original round with draft retained',
    () async {
      final port = server.port;
      await server.close();
      await waitUntil(
        () => !c.online,
        reason:
            'participant stayed online after server shutdown before late comment',
      );
      await c.saveDraft(round, text: '来晚的短评');
      await c.submit('comment', text: '来晚的短评');
      admin('close', {'round': round});
      admin('add', {
        'subject': {'id': 2, 'title': '第二部', 'summary': '', 'cover': ''},
      });
      admin('start', {'round': store.event(id)['rounds'][1]['id']});
      server = RoomServer(
        autoCacheCovers: false,
        store: store,
        adminPassword: 'test-management-password',
        assets: {},
      );
      await server.start(port: port, address: InternetAddress.loopbackIPv4);
      await c.refresh();
      await waitUntil(
        () => c.pending.isEmpty,
        reason: 'late comment did not receive its original-round rejection',
      );
      expect(c.drafts[round]['text'], '来晚的短评');
      expect(store.view(id, admin: true)['rounds'][1]['comments'], isEmpty);
      expect(c.message, contains('原输入已保留'));
    },
  );
  test('older HTTP success cannot undo a newer refresh', () async {
    final held = DelayedParticipantStateApi(c.api!);
    c.api = held;
    final old = c.refresh();
    final snapshot = await held.captured.future;
    admin('rename', {'title': '更新后的活动'});
    await c.refresh();
    held.release.complete(snapshot);
    await old;
    expect(c.event?['title'], '更新后的活动');
  });
  test('older HTTP failure cannot disconnect a successful refresh', () async {
    final held = DelayedParticipantStateApi(c.api!);
    c.api = held;
    final old = c.refresh();
    await held.captured.future;
    await c.refresh();
    held.release.completeError(StateError('late failure'));
    await old;
    expect(c.online, true);
  });
  test('live structural update wins over an in-flight HTTP snapshot', () async {
    final held = DelayedParticipantStateApi(c.api!);
    c.api = held;
    final old = c.refresh();
    final snapshot = await held.captured.future;
    final manager = RoomApi(invite.base);
    manager.token = (await manager.request('login', {
      'password': 'test-management-password',
    }))['token'];
    await manager.request('admin', {
      'op': newSecret(),
      'event': id,
      'version': store.info(id)['version'],
      'action': 'rename',
      'title': '来自实时连接的新状态',
    });
    await waitUntil(() => c.event?['title'] == '来自实时连接的新状态');
    held.release.complete(snapshot);
    await old;
    expect(c.event?['title'], '来自实时连接的新状态');
  });
  test(
    'changing rooms invalidates the previous room HTTP continuation',
    () async {
      final held = DelayedParticipantStateApi(c.api!);
      c.api = held;
      final old = c.refresh();
      final snapshot = await held.captured.future;
      admin('end');
      final next =
          store.create({'op': newSecret(), 'title': '下一场'})['id'] as String;
      await c.join(
        RoomInvite(invite.base, next, store.info(next)['invite']),
        '新活动昵称',
      );
      held.release.complete(snapshot);
      await old;
      expect(c.event?['id'], next);
      expect(c.name, '新活动昵称');
      expect(c.online, true);
    },
  );

  test('leave hides temporary entry and rejoin keeps one identity', () async {
    await c.leave();
    expect(c.active, false);
    await c.join(invite, '测试昵称');
    expect(c.active, true);
    expect(store.view(id, admin: true)['memberCount'], 1);
  });
  test(
    'the same room reached through another address keeps its participant identity',
    () async {
      final token = memory.value!['token'];
      await c.leave();
      c.dispose();
      c = ParticipationController(storage: memory);
      await c.restore();
      final other = RoomInvite(
        Uri.parse('http://localhost:${server.port}'),
        id,
        invite.secret,
      );
      expect(c.hasIdentity(other), true);
      await c.join(other, '测试昵称');
      expect(c.invite!.base.host, 'localhost');
      expect(memory.value!['token'], token);
      expect(store.view(id, admin: true)['memberCount'], 1);
    },
  );
  test(
    'a composer captured before a round switch cannot submit to the next title',
    () async {
      final previous = round;
      admin('add', {
        'subject': {'id': 2, 'title': '下一部', 'summary': '', 'cover': ''},
      });
      admin('start', {'round': store.event(id)['rounds'][1]['id']});
      await c.refresh();
      await expectLater(
        c.submit('comment', text: '上一部的感受', roundId: previous),
        throwsA(isA<RoomError>()),
      );
      expect(store.view(id, admin: true)['rounds'][1]['comments'], isEmpty);
    },
  );
}

class DelayedParticipantStateApi extends RoomApi {
  DelayedParticipantStateApi(this.delegate)
    : super(delegate.base, token: delegate.token);
  final RoomApi delegate;
  final captured = Completer<Json>(), release = Completer<Json>();
  var count = 0;
  @override
  Future<Json> request(String path, [Json? body]) async {
    if (path.startsWith('state?') && count++ == 0) {
      captured.complete(await delegate.request(path, body));
      return release.future;
    }
    return delegate.request(path, body);
  }
}
