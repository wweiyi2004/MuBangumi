import 'dart:convert';
import 'dart:io';
import 'package:banjian_server/banjian_server.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  test(
    'schema 3 migration keeps the latest revision and refreshes metadata across connections',
    () async {
      final dir = await Directory.systemTemp.createTemp('room-v3-');
      final path = '${dir.path}/room.sqlite';
      var store = RoomStore(path);
      final id =
          store.create({'op': newSecret(), 'title': '迁移前'})['id'] as String;
      store.db.execute('DROP TABLE room_revisions');
      store.db.execute('UPDATE events SET revision=42');
      store.db.execute('PRAGMA user_version=3');
      store.close();
      store = RoomStore(path);
      final other = RoomStore(path);
      try {
        expect(store.revision(id), 42);
        expect(store.info(id)['title'], '迁移前');
        other.admin({
          'op': newSecret(),
          'event': id,
          'version': 1,
          'action': 'rename',
          'title': '迁移后',
        });
        expect(store.info(id)['title'], '迁移后');
        expect(store.revision(id), 43);
        final detached = store.info(id);
        detached['title'] = '不得污染缓存';
        expect(store.info(id)['title'], '迁移后');
        expect(File('$path.pre-v4.sqlite').existsSync(), true);
      } finally {
        other.close();
        store.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test('maximum-size bounded previews fit the shared byte budget', () {
    final store = RoomStore(':memory:');
    addTearDown(store.close);
    final id =
        store.create({'op': newSecret(), 'title': '容量边界'})['id'] as String;
    final summary = List.filled(6000, '😀').join(),
        comment = List.filled(500, '😀').join();
    final data = store.info(id);
    data['rounds'] = [
      for (var i = 0; i < 100; i++)
        {
          'id': 'round-$i',
          'subject': {
            'id': i + 1,
            'title': List.filled(200, '动').join(),
            'summary': summary,
            'cover': '',
          },
          'status': i == 99 ? 'open' : 'closed',
          'published': true,
          'publicComments': true,
          'scores': <String, dynamic>{},
          'comments': <dynamic>[],
        },
    ];
    data['current'] = 'round-99';
    data['version'] = 101;
    store.db.execute('UPDATE events SET data=?,revision=200 WHERE id=?', [
      jsonEncode(data),
      id,
    ]);
    store.db.execute(
      'UPDATE room_revisions SET revision=200,metadata_version=metadata_version+1 WHERE event=?',
      [id],
    );
    store.db.execute('BEGIN');
    for (var member = 0; member < 500; member++)
      store.db.execute('INSERT INTO room_members VALUES(?,?,?)', [
        id,
        'member-$member',
        List.filled(40, '😀').join(),
      ]);
    for (var r = 0; r < 100; r++)
      for (var c = 0; c < 20; c++)
        store.db.execute(
          'INSERT INTO room_comments(event,round,id,actor,text,time,hidden) VALUES(?,?,?,?,?,?,0)',
          [id, 'round-$r', 'r${r}c$c', 'member-$c', comment, c],
        );
    store.db.execute('COMMIT');
    final snapshot = store.view(id, admin: true);
    expect(
      utf8.encode(jsonEncode(snapshot)).length,
      lessThan(RoomLimits.snapshotBytes),
    );
    expect(RoomSnapshot.fromJson(snapshot).rounds, hasLength(100));
  });
  test(
    'legacy migration preserves identities, scores, hidden comments and receipts',
    () async {
      final dir = await Directory.systemTemp.createTemp('room-migration-');
      final file = '${dir.path}/room.sqlite';
      final token = newSecret(), actor = digest(token), invite = newSecret();
      final command = {
        'op': 'preserved-op',
        'event': 'old-event',
        'round': 'old-round',
        'action': 'score',
        'score': 8,
      };
      final legacy = sqlite3.open(file);
      legacy.execute(
        'CREATE TABLE events(id TEXT PRIMARY KEY,data TEXT NOT NULL)',
      );
      legacy.execute(
        'CREATE TABLE operations(actor TEXT,id TEXT,hash TEXT NOT NULL,result TEXT NOT NULL,PRIMARY KEY(actor,id))',
      );
      legacy.execute('INSERT INTO events VALUES(?,?)', [
        'old-event',
        jsonEncode({
          'id': 'old-event',
          'title': '旧活动',
          'invite': invite,
          'version': 4,
          'created': '2026-09-18T00:00:00Z',
          'ended': false,
          'current': 'old-round',
          'members': {
            actor: {'name': '成员'},
          },
          'rounds': [
            {
              'id': 'old-round',
              'subject': {'id': 1, 'title': '动画', 'summary': '', 'cover': ''},
              'status': 'open',
              'published': true,
              'publicComments': true,
              'scores': {actor: 8},
              'comments': [
                {
                  'id': 'comment-1',
                  'actor': actor,
                  'text': '旧评论',
                  'time': 1,
                  'hidden': true,
                },
              ],
            },
          ],
        }),
      ]);
      legacy.execute('INSERT INTO operations VALUES(?,?,?,?)', [
        'old-event:$actor',
        'preserved-op',
        digest(jsonEncode(command)),
        jsonEncode({'accepted': true, 'round': 'old-round'}),
      ]);
      legacy.close();
      final store = RoomStore(file);
      try {
        expect(store.event('old-event')['members'][actor]['name'], '成员');
        expect(
          store.view('old-event', token: token)['rounds'][0]['myScore'],
          8,
        );
        expect(
          store.event('old-event')['rounds'][0]['comments'][0]['hidden'],
          true,
        );
        final before = store.revision('old-event');
        expect(store.submit(token, command)['accepted'], true);
        expect(store.revision('old-event'), before);
        final persisted = jsonDecode(
          store.db.select('SELECT data FROM events').single['data'] as String,
        );
        expect(persisted['members'], isEmpty);
        expect(persisted['rounds'][0]['comments'], isEmpty);
        expect(
          dir.listSync().whereType<File>().where(
            (f) => f.path.contains('.pre-v2.'),
          ),
          isNotEmpty,
        );
      } finally {
        store.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'hot writes leave metadata unchanged and deltas replace only changed rounds',
    () {
      final store = RoomStore(':memory:');
      addTearDown(store.close);
      final id =
          store.create({'op': newSecret(), 'title': '增量活动'})['id'] as String;
      Json admin(String action, Json extra) => store.admin({
        'op': newSecret(),
        'event': id,
        'version': store.info(id)['version'],
        'action': action,
        ...extra,
      });
      for (var i = 0; i < 3; i++)
        admin('add', {
          'subject': {'id': i + 1, 'title': '动画$i', 'summary': '', 'cover': ''},
        });
      final round = store.info(id)['rounds'][0]['id'] as String;
      admin('start', {'round': round});
      final token = newSecret();
      store.join({
        'op': newSecret(),
        'event': id,
        'invite': store.info(id)['invite'],
        'token': token,
        'name': '参与者',
      });
      final before = store.view(id, token: token),
          raw = store.db.select('SELECT data FROM events WHERE id=?', [
            id,
          ]).single['data'];
      // Updating the wide row at all would cause needless SQLite page writes.
      store.db.execute(
        "CREATE TRIGGER reject_hot_metadata BEFORE UPDATE ON events BEGIN SELECT RAISE(ABORT,'hot metadata write'); END",
      );
      store.submit(token, {
        'op': newSecret(),
        'event': id,
        'round': round,
        'action': 'score',
        'score': 9,
      });
      expect(
        store.db.select('SELECT data FROM events WHERE id=?', [
          id,
        ]).single['data'],
        raw,
      );
      expect(store.info(id)['version'], before['version']);
      final delta = store.viewSince(id, before['revision'], token: token);
      expect(delta['type'], 'delta');
      expect(delta['rounds'], hasLength(1));
      final merged = RoomSnapshot.fromJson(mergeRoomSnapshot(before, delta));
      expect(merged.rounds, hasLength(3));
      expect(merged.current!.myScore, 9);
      store.db.execute('DROP TRIGGER reject_hot_metadata');
      admin('publish', {'round': round, 'value': true});
      expect(
        store
            .viewSince(id, before['revision'], token: token)
            .containsKey('type'),
        false,
      );
      for (var i = 0; i < 140; i++)
        store.submit(token, {
          'op': newSecret(),
          'event': id,
          'round': round,
          'action': 'score',
          'score': i % 10 + 1,
        });
      expect(
        store
            .viewSince(id, before['revision'], token: token)
            .containsKey('type'),
        false,
      );
      expect(
        store.db.select(
          'SELECT count(*) AS n FROM room_changes WHERE event=?',
          [id],
        ).single['n'],
        lessThanOrEqualTo(128),
      );
    },
  );

  test(
    'comment paging stays anonymous, honors visibility and exports the complete history',
    () async {
      final dir = await Directory.systemTemp.createTemp('room-pages-');
      final store = RoomStore('${dir.path}/room.sqlite');
      try {
        final id =
            store.create({'op': newSecret(), 'title': '分页活动'})['id'] as String;
        Json admin(String action, Json extra) => store.admin({
          'op': newSecret(),
          'event': id,
          'version': store.info(id)['version'],
          'action': action,
          ...extra,
        });
        admin('add', {
          'subject': {'id': 1, 'title': '动画', 'summary': '', 'cover': ''},
        });
        final round = store.info(id)['rounds'][0]['id'] as String;
        final me = newSecret(), other = newSecret();
        for (final token in [me, other])
          store.join({
            'op': newSecret(),
            'event': id,
            'invite': store.info(id)['invite'],
            'token': token,
            'name': token == me ? '我' : '其他人',
          });
        store.db.execute('BEGIN');
        for (var i = 0; i < 125; i++)
          store.db.execute(
            'INSERT INTO room_comments(event,round,id,actor,text,time,hidden) VALUES(?,?,?,?,?,?,?)',
            [
              id,
              round,
              'c-$i',
              digest(i.isEven ? me : other),
              '评论 $i',
              i,
              i % 7 == 0 ? 1 : 0,
            ],
          );
        store.db.execute('COMMIT');
        final private = store.commentsPage(id, round, token: me);
        expect(private['total'], 63);
        expect(
          (private['comments'] as List).every((c) => c['mine'] == true),
          true,
        );
        admin('comments', {'round': round, 'value': true});
        final preview = store.view(id, admin: true)['rounds'][0];
        expect(preview['comments'], hasLength(20));
        expect(preview['commentsMore'], true);
        expect(preview['commentsTotal'], 125);
        final ids = <String>{};
        int? before;
        do {
          final page = RoomCommentsPage.fromJson(
            store.commentsPage(id, round, admin: true, before: before),
          );
          ids.addAll(page.comments.map((c) => c.id));
          before = page.nextCursor;
        } while (before != null);
        expect(ids, hasLength(125));
        final visible = store.commentsPage(id, round, token: other);
        expect(
          (visible['comments'] as List).every(
            (c) => c['mine'] == true || c['hidden'] != true,
          ),
          true,
        );
        final export =
            jsonDecode(await store.exportStream(id, format: 'json').join())
                as Json;
        expect(export['rounds'][0]['comments'], hasLength(125));
        expect(export.containsKey('invite'), false);
        expect(export.containsKey('members'), false);
        expect(jsonEncode(export), isNot(contains(digest(me))));
        expect(
          (await store.exportStream(id, format: 'comments').join()).split(
            '\r\n',
          ),
          hasLength(126),
        );
      } finally {
        store.close();
        await dir.delete(recursive: true);
      }
    },
  );
}
