import 'dart:convert';
import 'package:sqlite3/sqlite3.dart';
import 'protocol.dart';

/// Runs in the service isolate. Every acknowledgement follows a FULL SQLite
/// transaction, including the operation receipt. Public projections never
/// serialize the internal identity / score relation.
class RoomStore {
  RoomStore(String path) : db = sqlite3.open(path) {
    db.execute('PRAGMA journal_mode=WAL');
    db.execute('PRAGMA synchronous=FULL');
    db.execute('PRAGMA busy_timeout=5000');
    db.execute(
      'CREATE TABLE IF NOT EXISTS events (id TEXT PRIMARY KEY, data TEXT NOT NULL)',
    );
    db.execute(
      'CREATE TABLE IF NOT EXISTS operations (actor TEXT, id TEXT, hash TEXT NOT NULL, result TEXT NOT NULL, PRIMARY KEY(actor,id))',
    );
    db.execute(
      'CREATE TABLE IF NOT EXISTS covers (id TEXT PRIMARY KEY, mime TEXT, bytes BLOB)',
    );
  }
  final Database db;
  void close() => db.close();
  Json event(String id) {
    final rows = db.select('SELECT data FROM events WHERE id=?', [id]);
    if (rows.isEmpty) reject('活动不存在', 404);
    return jsonDecode(rows.single['data'] as String) as Json;
  }

  List<Json> history() => db
      .select(
        "SELECT data FROM events ORDER BY json_extract(data, '\$.ended') ASC, json_extract(data, '\$.created') DESC, id DESC",
      )
      .map((row) {
        final e = jsonDecode(row['data'] as String) as Json;
        return <String, dynamic>{
          'id': e['id'],
          'title': e['title'],
          'ended': e['ended'],
          'created': e['created'],
          'rounds': (e['rounds'] as List).length,
        };
      })
      .toList();
  void _save(Json e) => db.execute(
    'INSERT OR REPLACE INTO events(id,data) VALUES(?,?)',
    [e['id'], jsonEncode(e)],
  );
  Json once(String actor, Json command, Json Function() action) {
    final id = textField(command, 'op', max: 80);
    final hash = digest(jsonEncode(command));
    db.execute('BEGIN IMMEDIATE');
    try {
      final old = db.select(
        'SELECT hash,result FROM operations WHERE actor=? AND id=?',
        [actor, id],
      );
      if (old.isNotEmpty) {
        if (old.single['hash'] != hash) reject('操作编号已使用，请勿更改待提交内容', 409);
        final result = jsonDecode(old.single['result'] as String) as Json;
        db.execute('COMMIT');
        return result;
      }
      final result = action();
      db.execute('INSERT INTO operations VALUES(?,?,?,?)', [
        actor,
        id,
        hash,
        jsonEncode(result),
      ]);
      db.execute('COMMIT');
      return result;
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  Json create(Json c) => once('admin', c, () {
    if (history().any((e) => e['ended'] != true)) reject('请先结束正在进行的活动', 409);
    final e = <String, dynamic>{
      'id': newSecret(16),
      'title': textField(c, 'title', max: 80),
      'invite': newSecret(),
      'version': 1,
      'created': DateTime.now().toUtc().toIso8601String(),
      'ended': false,
      'current': null,
      'rounds': <dynamic>[],
      'members': <String, dynamic>{},
    };
    _save(e);
    return {'id': e['id']};
  });
  void verifyInvite(Json e, String invite) {
    if (digest(invite) != digest(e['invite'] as String)) reject('邀请链接已失效', 403);
  }

  Json preview(String id, String invite) {
    final e = event(id);
    verifyInvite(e, invite);
    return {
      'id': id,
      'title': e['title'],
      'ended': e['ended'],
      'count': (e['members'] as Map).length,
      'created': e['created'],
    };
  }

  Json join(Json c) {
    final id = textField(c, 'event');
    final token = textField(c, 'token', max: 128);
    if (!RegExp(r'^[A-Za-z0-9_-]{32,128}$').hasMatch(token)) reject('参与凭据无效');
    final actor = digest(token);
    // Always validate the invitation, even when replaying a registration.
    verifyInvite(event(id), textField(c, 'invite'));
    return once('join:$id:$actor', c, () {
      final e = event(id);
      final members = e['members'] as Json;
      if (!members.containsKey(actor) && e['ended'] == true)
        reject('活动已经结束', 409);
      if (!members.containsKey(actor) && members.length >= 500)
        reject('活动参与人数已达上限', 409);
      if (!members.containsKey(actor))
        members[actor] = {'name': textField(c, 'name', max: 40)};
      _save(e);
      return {'joined': true};
    });
  }

  String participant(Json e, String token) {
    final actor = digest(token);
    if (!(e['members'] as Map).containsKey(actor)) reject('请先加入活动', 401);
    return actor;
  }

  Json submit(String token, Json c) {
    final id = textField(c, 'event');
    final actor = participant(event(id), token);
    return once('$id:$actor', c, () {
      final e = event(id);
      final rid = textField(c, 'round');
      final r = _round(e, rid);
      if (e['ended'] == true || e['current'] != rid || r['status'] != 'open')
        reject('本轮已暂停、截止或切换，未提交到其他番剧', 409);
      switch (c['action']) {
        case 'score':
          (r['scores'] as Json)[actor] = intField(c, 'score', min: 1, max: 10);
        case 'comment':
          final comments = r['comments'] as List;
          if (comments.length >= 5000) reject('本轮评论已达上限', 409);
          final mine = comments.where((v) => v['actor'] == actor).toList();
          final now = DateTime.now().millisecondsSinceEpoch;
          if (mine.isNotEmpty && now - (mine.last['time'] as int) < 3000)
            reject('请稍等 3 秒再发短评', 429);
          comments.add({
            'id': newSecret(16),
            'actor': actor,
            'text': textField(c, 'text'),
            'time': now,
            'hidden': false,
          });
        default:
          reject('未知参与操作');
      }
      _save(e);
      return {'accepted': true, 'round': rid};
    });
  }

  Json _round(Json e, String id) =>
      (e['rounds'] as List).cast<Json>().firstWhere(
        (r) => r['id'] == id,
        orElse: () => throw const RoomError(404, '轮次不存在'),
      );
  Json admin(Json c) {
    if (c['action'] == 'create') return create(c);
    return once('admin', c, () {
      final e = event(textField(c, 'event'));
      if (c['version'] != e['version']) reject('另一位管理员已更新活动，已刷新，请重新操作', 409);
      final action = c['action'];
      if (e['ended'] == true &&
          ![
            'publish',
            'comments',
            'hide',
            'rename',
            'rotateInvite',
          ].contains(action))
        reject('活动已结束', 409);
      switch (action) {
        case 'rename':
          e['title'] = textField(c, 'title', max: 80);
        case 'add':
          final rounds = e['rounds'] as List;
          if (rounds.length >= 100) reject('每场最多 100 部番剧');
          final subject = c['subject'];
          if (subject is! Json) reject('条目无效');
          final sid = intField(subject, 'id', min: 1);
          final cover = subject['cover'] is String
              ? subject['cover'] as String
              : '';
          if (cover.isNotEmpty && !RegExp(r'^[a-f0-9]{64}$').hasMatch(cover))
            reject('封面无效');
          rounds.add({
            'id': newSecret(16),
            'subject': {
              'id': sid,
              'title': textField(subject, 'title', max: 200),
              'summary': textField(subject, 'summary', max: 6000, empty: true),
              'cover': cover,
              'coverSource':
                  roomCoverUri(
                    subject['coverSource'] is String
                        ? subject['coverSource'] as String
                        : '',
                  )?.toString() ??
                  '',
            },
            'status': 'waiting',
            'published': false,
            'publicComments': false,
            'scores': <String, dynamic>{},
            'comments': <dynamic>[],
          });
        case 'remove':
          final r = _round(e, textField(c, 'round'));
          if (r['status'] != 'waiting') reject('已开始的轮次不能删除', 409);
          (e['rounds'] as List).remove(r);
        case 'move':
          final r = _round(e, textField(c, 'round'));
          final rounds = e['rounds'] as List;
          final index = intField(c, 'index', max: rounds.length - 1);
          if (r['status'] != 'waiting' || rounds[index]['status'] != 'waiting')
            reject('只能调整未开始的番剧');
          rounds.remove(r);
          rounds.insert(index, r);
        case 'start':
          final r = _round(e, textField(c, 'round'));
          if (r['status'] != 'waiting') reject('该轮次已经开始或结束', 409);
          if (e['current'] != null)
            _round(e, e['current'])['status'] = 'closed';
          e['current'] = r['id'];
          r['status'] = 'open';
        case 'pause':
        case 'resume':
        case 'close':
          final r = _round(e, textField(c, 'round'));
          if (e['current'] != r['id'] || r['status'] == 'closed')
            reject('本轮已截止，不能重新开放', 409);
          r['status'] = action == 'pause'
              ? 'paused'
              : action == 'resume'
              ? 'open'
              : 'closed';
        case 'publish':
        case 'comments':
          final r = _round(e, textField(c, 'round'));
          if (c['value'] is! bool) reject('开关无效');
          r[action == 'publish' ? 'published' : 'publicComments'] = c['value'];
        case 'hide':
          final r = _round(e, textField(c, 'round'));
          final comment = (r['comments'] as List).cast<Json>().firstWhere(
            (v) => v['id'] == c['comment'],
            orElse: () => throw const RoomError(404, '评论不存在'),
          );
          if (c['value'] is! bool) reject('开关无效');
          comment['hidden'] = c['value'];
        case 'end':
          e['ended'] = true;
          for (final r in e['rounds'] as List) {
            if (r['status'] != 'waiting') r['status'] = 'closed';
          }
        case 'rotateInvite':
          e['invite'] = newSecret();
        default:
          reject('未知管理操作');
      }
      e['version'] = (e['version'] as int) + 1;
      _save(e);
      return {'id': e['id'], 'version': e['version']};
    });
  }

  bool updateRoundCover(
    String eventId,
    String roundId,
    int subjectId, {
    String? cover,
    String? error,
  }) {
    db.execute('BEGIN IMMEDIATE');
    try {
      final e = event(eventId);
      final rounds = (e['rounds'] as List).cast<Json>();
      final r = rounds
          .where((r) => r['id'] == roundId && r['subject']['id'] == subjectId)
          .firstOrNull;
      if (r == null) {
        db.execute('COMMIT');
        return false;
      }
      final subject = r['subject'] as Json;
      if (cover != null) {
        if (db.select('SELECT 1 FROM covers WHERE id=?', [cover]).isEmpty)
          reject('封面尚未保存');
        subject['cover'] = cover;
        subject.remove('coverError');
      } else {
        final current = subject['cover'] as String? ?? '';
        if (current.isNotEmpty &&
            db.select('SELECT 1 FROM covers WHERE id=?', [
              current,
            ]).isNotEmpty) {
          db.execute('COMMIT');
          return false;
        }
        subject['cover'] = '';
        subject['coverError'] = error ?? '封面暂未缓存';
      }
      // Artwork enrichment doesn't change voting rules or admin edit versions.
      _save(e);
      db.execute('COMMIT');
      return true;
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  Json view(String id, {String? token, bool admin = false}) {
    final e = event(id);
    final actor = admin ? null : participant(e, token ?? '');
    final rounds = <Json>[];
    for (final r in (e['rounds'] as List).cast<Json>()) {
      final scores = r['scores'] as Json;
      final values = scores.values.cast<int>().toList();
      final comments = (r['comments'] as List).cast<Json>();
      rounds.add({
        'id': r['id'],
        'subject': r['subject'],
        'status': r['status'],
        'published': r['published'],
        'publicComments': r['publicComments'],
        'count': values.length,
        'myScore': actor == null ? null : scores[actor],
        if (admin || r['published'] == true)
          'stats': {
            'count': values.length,
            'mean': values.isEmpty
                ? null
                : values.reduce((a, b) => a + b) / values.length,
            'distribution': List.generate(
              10,
              (i) => values.where((v) => v == i + 1).length,
            ),
          },
        'comments': [
          for (final c in comments)
            if (admin ||
                c['actor'] == actor ||
                (r['publicComments'] == true && c['hidden'] != true))
              {
                'id': c['id'],
                'text': c['text'],
                'hidden': c['hidden'],
                if (!admin) 'mine': c['actor'] == actor,
              },
        ],
      });
    }
    final current = e['current'];
    final scores = current == null
        ? <String, dynamic>{}
        : _round(e, current)['scores'] as Json;
    return {
      'id': id,
      'title': e['title'],
      'ended': e['ended'],
      'created': e['created'],
      'version': e['version'],
      'current': current,
      'memberCount': (e['members'] as Map).length,
      'rounds': rounds,
      if (actor != null) 'name': e['members'][actor]['name'],
      if (admin) 'invite': e['invite'],
      if (admin)
        'members': [
          for (final entry in (e['members'] as Json).entries)
            {
              'name': entry.value['name'],
              'submitted': scores.containsKey(entry.key),
            },
        ],
    };
  }

  Json export(String id) {
    final data = view(id, admin: true);
    data.remove('invite');
    data.remove('members');
    // Export aggregate results and anonymous comments, never joinable records.
    return data;
  }

  String csv(String id, {bool comments = false}) {
    String cell(Object? v) {
      var s = v?.toString() ?? '';
      if (RegExp(r'^[\s]*[=+@\-\t\r\n]').hasMatch(s)) s = "'$s";
      return '"${s.replaceAll('"', '""')}"';
    }

    final rows = <List<Object?>>[
      comments
          ? ['番剧', '匿名短评', '已隐藏']
          : ['番剧', '人数', '均分', for (var i = 1; i <= 10; i++) '$i 分'],
    ];
    for (final r in export(id)['rounds'] as List) {
      if (comments) {
        for (final c in r['comments']) {
          rows.add([r['subject']['title'], c['text'], c['hidden']]);
        }
      } else {
        rows.add([
          r['subject']['title'],
          r['stats']['count'],
          r['stats']['mean'],
          ...r['stats']['distribution'],
        ]);
      }
    }
    return '\uFEFF${rows.map((r) => r.map(cell).join(',')).join('\r\n')}';
  }
}
