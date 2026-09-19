import 'dart:convert';
import 'dart:io';
import 'package:sqlite3/sqlite3.dart';
import 'protocol.dart';

/// Runs in the service isolate. Every acknowledgement follows a FULL SQLite
/// transaction, including the operation receipt. Public projections never
/// serialize the internal identity / score relation.
class RoomStore {
  RoomStore(String path) : _path = path, db = sqlite3.open(path) {
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
    _migrate(path);
  }
  final Database db;
  final String? _path;
  final _metadataCache = <String, ({int version, Json data})>{};
  RoomStore._reader(this.db) : _path = null;
  void close() => db.close();

  void _migrate(String path) {
    final version =
        db.select('PRAGMA user_version').single.values.single as int;
    if (version >= 4) return;
    if (path != ':memory:' &&
        db.select('SELECT 1 FROM events LIMIT 1').isNotEmpty) {
      final backup = '$path.pre-v${version < 2 ? 2 : 4}.sqlite';
      if (!File(backup).existsSync()) db.execute('VACUUM INTO ?', [backup]);
    }
    db.execute('BEGIN IMMEDIATE');
    try {
      if (!db
          .select('PRAGMA table_info(events)')
          .any((r) => r['name'] == 'revision')) {
        db.execute(
          'ALTER TABLE events ADD COLUMN revision INTEGER NOT NULL DEFAULT 0',
        );
      }
      db.execute(
        'CREATE TABLE IF NOT EXISTS room_members (event TEXT NOT NULL, actor TEXT NOT NULL, name TEXT NOT NULL, PRIMARY KEY(event,actor))',
      );
      db.execute(
        'CREATE TABLE IF NOT EXISTS room_scores (event TEXT NOT NULL, round TEXT NOT NULL, actor TEXT NOT NULL, score INTEGER NOT NULL, PRIMARY KEY(event,round,actor))',
      );
      db.execute(
        'CREATE INDEX IF NOT EXISTS room_score_distribution ON room_scores(event,round,score)',
      );
      db.execute(
        'CREATE TABLE IF NOT EXISTS room_comments (seq INTEGER PRIMARY KEY AUTOINCREMENT, event TEXT NOT NULL, round TEXT NOT NULL, id TEXT NOT NULL UNIQUE, actor TEXT NOT NULL, text TEXT NOT NULL, time INTEGER NOT NULL, hidden INTEGER NOT NULL)',
      );
      db.execute(
        'CREATE INDEX IF NOT EXISTS room_comment_page ON room_comments(event,round,seq DESC)',
      );
      db.execute(
        'CREATE INDEX IF NOT EXISTS room_comment_owner ON room_comments(event,round,actor,seq DESC)',
      );
      db.execute(
        'CREATE TABLE IF NOT EXISTS room_changes(event TEXT NOT NULL,revision INTEGER NOT NULL,round TEXT,PRIMARY KEY(event,revision))',
      );
      if (version < 3)
        for (final row in db.select('SELECT id,data,revision FROM events')) {
          final e = jsonDecode(row['data'] as String) as Json;
          for (final entry in (e['members'] as Json).entries) {
            db.execute('INSERT OR IGNORE INTO room_members VALUES(?,?,?)', [
              e['id'],
              entry.key,
              entry.value['name'],
            ]);
          }
          for (final r in (e['rounds'] as List).cast<Json>()) {
            for (final score in (r['scores'] as Json).entries) {
              db.execute('INSERT OR IGNORE INTO room_scores VALUES(?,?,?,?)', [
                e['id'],
                r['id'],
                score.key,
                score.value,
              ]);
            }
            for (final c in r['comments'] as List) {
              db.execute(
                'INSERT OR IGNORE INTO room_comments(event,round,id,actor,text,time,hidden) VALUES(?,?,?,?,?,?,?)',
                [
                  e['id'],
                  r['id'],
                  c['id'],
                  c['actor'],
                  c['text'],
                  c['time'],
                  c['hidden'] == true ? 1 : 0,
                ],
              );
            }
          }
          db.execute('UPDATE events SET data=?,revision=? WHERE id=?', [
            jsonEncode(_metadataOnly(e)),
            (row['revision'] as int) >
                    (e['revision'] as int? ?? e['version'] as int? ?? 1)
                ? row['revision']
                : e['revision'] ?? e['version'] ?? 1,
            e['id'],
          ]);
        }
      // Keep frequent revisions out of the wide metadata row: even updating
      // one column in that row can rewrite its SQLite overflow pages.
      db.execute(
        'CREATE TABLE IF NOT EXISTS room_revisions(event TEXT PRIMARY KEY, revision INTEGER NOT NULL, metadata_version INTEGER NOT NULL)',
      );
      db.execute(
        'INSERT OR IGNORE INTO room_revisions SELECT id,revision,1 FROM events',
      );
      db.execute('PRAGMA user_version=4');
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  Json _metadataOnly(Json e) => {
    ...e,
    'members': <String, dynamic>{},
    'rounds': [
      for (final r in (e['rounds'] as List).cast<Json>())
        {...r, 'scores': <String, dynamic>{}, 'comments': <dynamic>[]},
    ],
  };

  Json _metadata(String id) {
    final rows = db.select(
      'SELECT revision,metadata_version FROM room_revisions WHERE event=?',
      [id],
    );
    if (rows.isEmpty) reject('活动不存在', 404);
    final version = rows.single['metadata_version'] as int;
    var cached = _metadataCache.remove(id);
    if (cached == null || cached.version != version) {
      cached = (
        version: version,
        data:
            jsonDecode(
                  db.select('SELECT data FROM events WHERE id=?', [
                        id,
                      ]).single['data']
                      as String,
                )
                as Json,
      );
    }
    _metadataCache[id] = cached;
    if (_metadataCache.length > 8)
      _metadataCache.remove(_metadataCache.keys.first);
    return {...cached.data, 'revision': rows.single['revision']};
  }

  /// Independent mutable metadata for structural edits and diagnostic callers.
  Json info(String id) => clone(_metadata(id));

  /// Small header for live notifications; never exposes cached nested values.
  Json header(String id) {
    final e = _metadata(id);
    return {'version': e['version'], 'revision': e['revision']};
  }

  int revision(String id) {
    final rows = db.select(
      'SELECT revision FROM room_revisions WHERE event=?',
      [id],
    );
    if (rows.isEmpty) reject('活动不存在', 404);
    return rows.single['revision'] as int;
  }

  /// Full diagnostic/export representation, retained for callers of v1 store.
  Json event(String id) {
    final e = info(id);
    e['members'] = {
      for (final m in db.select(
        'SELECT actor,name FROM room_members WHERE event=?',
        [id],
      ))
        m['actor'] as String: {'name': m['name']},
    };
    for (final r in e['rounds'] as List) {
      r['scores'] = {
        for (final score in db.select(
          'SELECT actor,score FROM room_scores WHERE event=? AND round=?',
          [id, r['id']],
        ))
          score['actor'] as String: score['score'],
      };
      r['comments'] = [
        for (final c in db.select(
          'SELECT * FROM room_comments WHERE event=? AND round=? ORDER BY seq',
          [id, r['id']],
        ))
          {
            'id': c['id'],
            'actor': c['actor'],
            'text': c['text'],
            'time': c['time'],
            'hidden': c['hidden'] == 1,
          },
      ];
    }
    return e;
  }

  List<Json> history() => db
      .select(
        "SELECT id, json_extract(data, '\$.title') AS title, json_extract(data, '\$.ended') AS ended, json_extract(data, '\$.created') AS created, json_array_length(data, '\$.rounds') AS rounds FROM events ORDER BY ended ASC, created DESC, id DESC",
      )
      .map((row) {
        return <String, dynamic>{
          'id': row['id'],
          'title': row['title'],
          'ended': row['ended'] == 1,
          'created': row['created'],
          'rounds': row['rounds'],
        };
      })
      .toList();

  void _save(Json e) {
    final existing = db.select(
      'SELECT revision,metadata_version FROM room_revisions WHERE event=?',
      [e['id']],
    );
    final revision = existing.isEmpty
        ? 1
        : (existing.single['revision'] as int) + 1;
    e['revision'] = revision;
    db.execute(
      'INSERT INTO events(id,data,revision) VALUES(?,?,?) ON CONFLICT(id) DO UPDATE SET data=excluded.data,revision=excluded.revision',
      [e['id'], jsonEncode(_metadataOnly(e)), revision],
    );
    db.execute('INSERT OR REPLACE INTO room_revisions VALUES(?,?,?)', [
      e['id'],
      revision,
      existing.isEmpty ? 1 : (existing.single['metadata_version'] as int) + 1,
    ]);
    _metadataCache.remove(e['id']);
    _recordChange(e['id'], revision, null);
  }

  void _recordChange(String id, int revision, String? round) {
    db.execute('INSERT INTO room_changes VALUES(?,?,?)', [id, revision, round]);
    db.execute('DELETE FROM room_changes WHERE event=? AND revision<?', [
      id,
      revision - 127,
    ]);
  }

  void _touch(String id, {String? round}) {
    db.execute('UPDATE room_revisions SET revision=revision+1 WHERE event=?', [
      id,
    ]);
    _recordChange(id, revision(id), round);
  }

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
    final e = _metadata(id);
    verifyInvite(e, invite);
    return {
      'id': id,
      'title': e['title'],
      'ended': e['ended'],
      'count': _memberCount(id),
      'created': e['created'],
    };
  }

  Json join(Json c) {
    final id = textField(c, 'event');
    final token = textField(c, 'token', max: 128);
    if (!RegExp(r'^[A-Za-z0-9_-]{32,128}$').hasMatch(token)) reject('参与凭据无效');
    final actor = digest(token);
    // Always validate the invitation, even when replaying a registration.
    verifyInvite(_metadata(id), textField(c, 'invite'));
    return once('join:$id:$actor', c, () {
      final e = _metadata(id);

      final exists = db.select(
        'SELECT 1 FROM room_members WHERE event=? AND actor=?',
        [id, actor],
      ).isNotEmpty;
      if (!exists && e['ended'] == true) reject('活动已经结束', 409);
      if (!exists && _memberCount(id) >= 500) reject('活动参与人数已达上限', 409);
      if (!exists) {
        db.execute('INSERT INTO room_members VALUES(?,?,?)', [
          id,
          actor,
          textField(c, 'name', max: 40),
        ]);
        _touch(id);
      }
      return {'joined': true};
    });
  }

  int _memberCount(String id) =>
      db.select('SELECT count(*) AS n FROM room_members WHERE event=?', [
            id,
          ]).single['n']
          as int;
  String participant(Json e, String token) {
    final actor = digest(token);
    if (db.select('SELECT 1 FROM room_members WHERE event=? AND actor=?', [
      e['id'],
      actor,
    ]).isEmpty)
      reject('请先加入活动', 401);
    return actor;
  }

  Json submit(String token, Json c) {
    final id = textField(c, 'event');
    final actor = participant(_metadata(id), token);
    return once('$id:$actor', c, () {
      final e = _metadata(id);
      final rid = textField(c, 'round');
      final r = _round(e, rid);
      if (e['ended'] == true || e['current'] != rid || r['status'] != 'open')
        reject('本轮已暂停、截止或切换，未提交到其他番剧', 409);
      switch (c['action']) {
        case 'score':
          final score = intField(c, 'score', min: 1, max: 10);
          db.execute(
            'INSERT INTO room_scores VALUES(?,?,?,?) ON CONFLICT(event,round,actor) DO UPDATE SET score=excluded.score',
            [id, rid, actor, score],
          );
        case 'comment':
          final count =
              db.select(
                    'SELECT count(*) AS n FROM room_comments WHERE event=? AND round=?',
                    [id, rid],
                  ).single['n']
                  as int;
          if (count >= 5000) reject('本轮评论已达上限', 409);
          final last = db.select(
            'SELECT time FROM room_comments WHERE event=? AND round=? AND actor=? ORDER BY seq DESC LIMIT 1',
            [id, rid, actor],
          );
          final now = DateTime.now().millisecondsSinceEpoch;
          if (last.isNotEmpty && now - (last.single['time'] as int) < 3000)
            reject('请稍等 3 秒再发短评', 429);
          db.execute(
            'INSERT INTO room_comments(event,round,id,actor,text,time,hidden) VALUES(?,?,?,?,?,?,0)',
            [id, rid, newSecret(16), actor, textField(c, 'text'), now],
          );
        default:
          reject('未知参与操作');
      }
      _touch(id, round: rid);
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
      final e = info(textField(c, 'event'));
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

          if (c['value'] is! bool) reject('开关无效');
          final found = db.select(
            'SELECT 1 FROM room_comments WHERE event=? AND round=? AND id=?',
            [e['id'], r['id'], c['comment']],
          );
          if (found.isEmpty) reject('评论不存在', 404);
          db.execute(
            'UPDATE room_comments SET hidden=? WHERE event=? AND round=? AND id=?',
            [c['value'] == true ? 1 : 0, e['id'], r['id'], c['comment']],
          );
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
      final e = info(eventId);
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

  Json commentsPage(
    String id,
    String roundId, {
    String? token,
    bool admin = false,
    int? before,
    int limit = 50,
  }) {
    if (limit < 1 || limit > 100 || (before != null && before < 1))
      reject('分页参数无效');
    final e = _metadata(id);
    final r = _round(e, roundId);
    final actor = admin ? null : participant(e, token ?? '');
    return _comments(
      e,
      r,
      actor: actor,
      admin: admin,
      before: before,
      limit: limit,
    );
  }

  Json _comments(
    Json e,
    Json r, {
    String? actor,
    required bool admin,
    int? before,
    int limit = 20,
  }) {
    final id = e['id'], roundId = r['id'];
    final visible = admin
        ? ''
        : r['publicComments'] == true
        ? ' AND (hidden=0 OR actor=?)'
        : ' AND actor=?';
    final args = <Object?>[id, roundId, if (!admin) actor];
    final total = db
        .select(
          'SELECT count(*) AS n FROM room_comments WHERE event=? AND round=?$visible',
          args,
        )
        .single['n'];
    final rows = db.select(
      'SELECT seq,id,actor,text,hidden FROM room_comments WHERE event=? AND round=?$visible${before == null ? '' : ' AND seq<?'} ORDER BY seq DESC LIMIT ?',
      [...args, if (before != null) before, limit + 1],
    );
    final page = rows.take(limit).toList();
    return {
      'event': id,
      'round': roundId,
      'revision': e['revision'],
      'total': total,
      'nextCursor': rows.length > limit ? page.last['seq'] : null,
      'comments': [
        for (final c in page)
          {
            'id': c['id'],
            'text': c['text'],
            'hidden': c['hidden'] == 1,
            if (!admin) 'mine': c['actor'] == actor,
          },
      ],
    };
  }

  Json view(
    String id, {
    String? token,
    bool admin = false,
    bool allComments = false,
    Set<String>? onlyRounds,
  }) {
    final e = _metadata(id);
    final actor = admin ? null : participant(e, token ?? '');
    final grouped = onlyRounds?.isEmpty == true
        ? <Map<String, Object?>>[]
        : db.select(
            'SELECT round,score,count(*) AS n FROM room_scores WHERE event=?${onlyRounds == null ? '' : ' AND round IN (${List.filled(onlyRounds.length, '?').join(',')})'} GROUP BY round,score',
            [id, if (onlyRounds != null) ...onlyRounds],
          );
    final histograms = <String, List<int>>{};
    for (final row in grouped) {
      (histograms[row['round'] as String] ??= List.filled(
        10,
        0,
      ))[(row['score'] as int) - 1] = row['n'] as int;
    }
    final mine = actor == null
        ? <String, int>{}
        : {
            for (final row in db.select(
              'SELECT round,score FROM room_scores WHERE event=? AND actor=?',
              [id, actor],
            ))
              row['round'] as String: row['score'] as int,
          };
    final rounds = <Json>[];
    for (final r in (e['rounds'] as List).cast<Json>()) {
      if (onlyRounds != null && !onlyRounds.contains(r['id'])) continue;
      final dist = histograms[r['id']] ?? List<int>.filled(10, 0);
      final count = dist.fold<int>(0, (a, b) => a + b);
      final page = _comments(e, r, actor: actor, admin: admin);
      final comments = <Json>[];
      if (allComments) {
        int? cursor;
        do {
          final p = _comments(
            e,
            r,
            actor: actor,
            admin: admin,
            before: cursor,
            limit: 100,
          );
          comments.addAll((p['comments'] as List).cast<Json>());
          cursor = p['nextCursor'] as int?;
        } while (cursor != null);
      } else {
        comments.addAll((page['comments'] as List).cast<Json>());
      }
      rounds.add({
        'id': r['id'],
        'subject': {...r['subject'] as Json},
        'status': r['status'],
        'published': r['published'],
        'publicComments': r['publicComments'],
        'count': count,
        'myScore': mine[r['id']],
        if (admin || r['published'] == true)
          'stats': {
            'count': count,
            'mean': count == 0
                ? null
                : List.generate(
                        10,
                        (i) => (i + 1) * dist[i],
                      ).reduce((a, b) => a + b) /
                      count,
            'distribution': dist,
          },
        'comments': comments.reversed.toList(),
        'commentsTotal': page['total'],
        'commentsMore': !allComments && page['nextCursor'] != null,
      });
    }
    final current = e['current'];
    final submitted = current == null
        ? <String>{}
        : db
              .select(
                'SELECT actor FROM room_scores WHERE event=? AND round=?',
                [id, current],
              )
              .map((r) => r['actor'] as String)
              .toSet();
    return {
      'id': id,
      'title': e['title'],
      'ended': e['ended'],
      'created': e['created'],
      'version': e['version'],
      'revision': e['revision'],
      'current': current,
      'memberCount': _memberCount(id),
      'rounds': rounds,
      if (actor != null)
        'name': db.select(
          'SELECT name FROM room_members WHERE event=? AND actor=?',
          [id, actor],
        ).single['name'],
      if (admin) 'invite': e['invite'],
      if (admin)
        'members': [
          for (final m in db.select(
            'SELECT actor,name FROM room_members WHERE event=?',
            [id],
          ))
            {'name': m['name'], 'submitted': submitted.contains(m['actor'])},
        ],
    };
  }

  Json export(String id) {
    final data = view(id, admin: true, allComments: true);
    data.remove('invite');
    data.remove('members');
    // Export aggregate results and anonymous comments, never joinable records.
    return data;
  }

  /// A separate WAL reader pins an export snapshot without holding the server's
  /// writer connection or materializing the whole comment history in memory.
  Stream<String> exportStream(String id, {required String format}) async* {
    if (_path == null || _path == ':memory:') {
      yield format == 'json'
          ? jsonEncode(export(id))
          : csv(id, comments: format == 'comments');
      return;
    }
    final reader = RoomStore._reader(
      sqlite3.open(_path, mode: OpenMode.readOnly),
    );
    reader.db.execute('BEGIN');
    try {
      for (final chunk
          in format == 'json'
              ? reader._jsonChunks(id)
              : reader._csvChunks(id, comments: format == 'comments')) {
        yield chunk;
      }
    } finally {
      reader.db.execute('ROLLBACK');
      reader.close();
    }
  }

  Iterable<Json> _exportComments(String id, String round) sync* {
    var after = 0;
    while (true) {
      final rows = db.select(
        'SELECT seq,id,text,hidden FROM room_comments WHERE event=? AND round=? AND seq>? ORDER BY seq LIMIT 100',
        [id, round, after],
      );
      if (rows.isEmpty) return;
      for (final c in rows)
        yield {'id': c['id'], 'text': c['text'], 'hidden': c['hidden'] == 1};
      after = rows.last['seq'] as int;
    }
  }

  Iterable<String> _jsonChunks(String id) sync* {
    final header = view(id, admin: true)
      ..remove('invite')
      ..remove('members');
    final rounds = (header.remove('rounds') as List).cast<Json>();
    final encoded = jsonEncode(header);
    yield '${encoded.substring(0, encoded.length - 1)},"rounds":[';
    var firstRound = true;
    for (final r in rounds) {
      if (!firstRound) yield ',';
      firstRound = false;
      final metadata = {...r, 'commentsMore': false}..remove('comments');
      final prefix = jsonEncode(metadata);
      yield '${prefix.substring(0, prefix.length - 1)},"comments":[';
      var first = true;
      for (final c in _exportComments(id, r['id'])) {
        if (!first) yield ',';
        first = false;
        yield jsonEncode(c);
      }
      yield ']}';
    }
    yield ']}';
  }

  String _csvCell(Object? value) {
    var text = value?.toString() ?? '';
    if (RegExp(r'^[\s]*[=+@\-\t\r\n]').hasMatch(text)) text = "'$text";
    return '"${text.replaceAll('"', '""')}"';
  }

  Iterable<String> _csvChunks(String id, {bool comments = false}) sync* {
    final columns = comments
        ? ['番剧', '匿名短评', '已隐藏']
        : ['番剧', '人数', '均分', for (var i = 1; i <= 10; i++) '$i 分'];
    yield '\uFEFF${columns.map(_csvCell).join(',')}';
    for (final r in view(id, admin: true)['rounds'] as List) {
      if (comments) {
        for (final c in _exportComments(id, r['id']))
          yield '\r\n${[r['subject']['title'], c['text'], c['hidden']].map(_csvCell).join(',')}';
      } else {
        yield '\r\n${[r['subject']['title'], r['stats']['count'], r['stats']['mean'], ...r['stats']['distribution']].map(_csvCell).join(',')}';
      }
    }
  }

  Json viewSince(String id, int? since, {String? token, bool admin = false}) {
    if (since == null) return view(id, token: token, admin: admin);
    final latest = revision(id);
    if (since < 1 || since > latest)
      return view(id, token: token, admin: admin);
    final changes = db.select(
      'SELECT revision,round FROM room_changes WHERE event=? AND revision>? ORDER BY revision',
      [id, since],
    );
    if (since != latest &&
        (changes.isEmpty ||
            changes.first['revision'] != since + 1 ||
            changes.any((r) => r['round'] == null)))
      return view(id, token: token, admin: admin);
    final result = view(
      id,
      token: token,
      admin: admin,
      onlyRounds: {for (final c in changes) c['round'] as String},
    );
    return {...result, 'type': 'delta', 'baseRevision': since};
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
