import 'dart:io';
import 'package:banjian_server/banjian_server.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

const jpeg = [255, 216, 255, 224, 0, 16];
const avatar = 'https://lain.bgm.tv/pic/user/l/000/00/00/1.jpg?r=1';

void main() {
  late RoomStore store;
  late String id, invite;
  setUp(() {
    store = RoomStore(':memory:');
    id = store.admin({
      'op': newSecret(),
      'action': 'create',
      'title': '番键会',
    })['id'];
    invite = store.event(id)['invite'];
  });
  tearDown(() => store.close());

  Json join(String token, Object? picture) => store.join({
    'op': newSecret(),
    'event': id,
    'invite': invite,
    'token': token,
    'name': '小明',
    'avatar': picture,
  });
  List members() => store.view(id, admin: true)['members'] as List;

  test('only Bangumi user pictures are queued, never arbitrary URLs', () {
    expect(roomAvatarUri(avatar), isNotNull);
    expect(
      roomAvatarUri('http://lain.bgm.tv/pic/user/m/1.jpg')?.scheme,
      'https',
    );
    for (final bad in [
      'https://evil.example/pic/user/1.jpg',
      'https://lain.bgm.tv/pic/cover/l/1.jpg',
      'https://user@lain.bgm.tv/pic/user/1.jpg',
      'javascript:alert(1)',
    ]) {
      expect(roomAvatarUri(bad), isNull, reason: bad);
    }
    join(newSecret(), 'https://evil.example/pic/user/1.jpg');
    join(newSecret(), 42);
    join(newSecret(), null);
    expect(members(), hasLength(3));
    expect(store.pendingAvatars(id), isEmpty);
    expect(members().every((m) => !(m as Json).containsKey('avatar')), true);
  });

  test('server caches a joined avatar and exposes only its cache key', () async {
    final token = newSecret();
    join(token, avatar);
    expect(store.pendingAvatars(id).single.source, avatar);
    final loaded = <Uri>[];
    final server = RoomServer(
      store: store,
      adminPassword: 'test-management-password',
      assets: {},
      autoCacheCovers: false,
      coverLoader: (uri) async {
        loaded.add(uri);
        return const RoomCoverImage(jpeg, 'image/jpeg');
      },
    );
    await server.repairAvatars(id);
    final key = digest(avatar);
    expect(loaded, [Uri.parse(avatar)]);
    expect(members().single['avatar'], key);
    expect(store.pendingAvatars(id), isEmpty);
    // The participant projection never lists members or avatars.
    expect(store.view(id, token: token).containsKey('members'), false);
    // The admin snapshot model accepts the key.
    expect(
      RoomSnapshot.fromJson(store.view(id, admin: true)).toJson()['members'],
      [
        {'name': '小明', 'submitted': false, 'avatar': key},
      ],
    );

    // Rejoining with a new picture re-queues it; a stale cache write is ignored.
    const next = 'https://lain.bgm.tv/pic/user/l/000/00/00/2.jpg';
    join(token, next);
    expect(members().single.containsKey('avatar'), false);
    expect(store.setMemberAvatar(id, digest(token), avatar, key), false);
    await server.repairAvatars(id);
    expect(members().single['avatar'], digest(next));
  });

  test('failed downloads leave the default icon and retry later', () async {
    join(newSecret(), avatar);
    var fail = true;
    final server = RoomServer(
      store: store,
      adminPassword: 'test-management-password',
      assets: {},
      autoCacheCovers: false,
      coverLoader: (_) async {
        if (fail) throw const RoomError(502, 'offline');
        return const RoomCoverImage(jpeg, 'image/jpeg');
      },
    );
    await server.repairAvatars(id);
    expect(members().single.containsKey('avatar'), false);
    fail = false;
    await server.repairAvatars(id);
    expect(members().single['avatar'], digest(avatar));
  });

  test('an existing v4 database gains the avatar columns', () async {
    final temp = await Directory.systemTemp.createTemp('banjian-avatar-');
    addTearDown(() => temp.delete(recursive: true));
    final path = '${temp.path}/room.sqlite';
    final old = RoomStore(path);
    final event = old.admin({
      'op': newSecret(),
      'action': 'create',
      'title': '旧活动',
    })['id'];
    old.close();
    // Recreate the member table exactly as v4 shipped it.
    final raw = sqlite3.open(path);
    raw.execute('DROP TABLE room_members');
    raw.execute(
      'CREATE TABLE room_members (event TEXT NOT NULL, actor TEXT NOT NULL, name TEXT NOT NULL, PRIMARY KEY(event,actor))',
    );
    raw.execute("INSERT INTO room_members VALUES(?, 'actor', '老成员')", [event]);
    raw.close();

    final upgraded = RoomStore(path);
    addTearDown(upgraded.close);
    expect(upgraded.view(event, admin: true)['members'], [
      {'name': '老成员', 'submitted': false},
    ]);
    expect(upgraded.pendingAvatars(event), isEmpty);
  });
}
