import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'serial_task_queue.dart';
import 'sqlite_support.dart';

typedef CommunityDraftData = ({String title, String content});

class CommunityDraftSlot {
  const CommunityDraftSlot({this.data, this.revision = 0});
  final CommunityDraftData? data;
  final int revision;
}

class CommunityDraftConflict implements Exception {
  const CommunityDraftConflict();
  @override
  String toString() => '草稿已在其他操作中更新，请保留当前输入并重新打开';
}

/// JSON encoding prevents collisions between account and target identifiers.
String? communityDraftKey(String? username, List<Object> target) {
  final account = username?.trim().toLowerCase() ?? '';
  return account.isEmpty ? null : jsonEncode([account, ...target]);
}

abstract class CommunityDraftRepository {
  Future<CommunityDraftData?> load(String key);
  Future<void> save(String key, CommunityDraftData draft);
  Future<CommunityDraftSlot> loadVersioned(String key) async =>
      CommunityDraftSlot(data: await load(key));
  Future<int> saveVersioned(
    String key,
    CommunityDraftData draft, {
    required int expectedRevision,
  }) async {
    await save(key, draft);
    return expectedRevision + 1;
  }
}

class CommunityDraftStore implements CommunityDraftRepository {
  CommunityDraftStore({this.databasePath});

  static final shared = CommunityDraftStore();
  final String? databasePath;
  final _connection = SqliteConnection();
  final _writes = SerialTaskQueue();

  @override
  Future<CommunityDraftData?> load(String key) async {
    return (await loadVersioned(key)).data;
  }

  @override
  Future<CommunityDraftSlot> loadVersioned(String key) async {
    await _writes.done;
    final db = await _open();
    final rows = await db.query(
      'draft',
      where: 'draft_key = ?',
      whereArgs: [key],
    );
    if (rows.isEmpty) return const CommunityDraftSlot();
    final row = rows.single;
    return CommunityDraftSlot(
      revision: row['revision'] as int,
      data: row['deleted'] == 1
          ? null
          : (title: row['title'] as String, content: row['content'] as String),
    );
  }

  @override
  Future<void> save(String key, CommunityDraftData draft) {
    // Snapshot values are immutable. A pending autosave cannot overtake the
    // deletion after sending or a newer editor's save.
    return _save(key, draft).then((_) {});
  }

  @override
  Future<int> saveVersioned(
    String key,
    CommunityDraftData draft, {
    required int expectedRevision,
  }) => _save(key, draft, expectedRevision: expectedRevision);

  Future<int> _save(
    String key,
    CommunityDraftData draft, {
    int? expectedRevision,
  }) {
    return _writes.run(
      () async => (await _open()).transaction((txn) async {
        final rows = await txn.query(
          'draft',
          columns: ['revision'],
          where: 'draft_key = ?',
          whereArgs: [key],
        );
        final revision = rows.isEmpty ? 0 : rows.single['revision'] as int;
        if (expectedRevision != null && expectedRevision != revision) {
          throw const CommunityDraftConflict();
        }
        await txn.insert('draft', {
          'draft_key': key,
          'title': draft.title,
          'content': draft.content,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
          'revision': revision + 1,
          'deleted': draft.title.isEmpty && draft.content.isEmpty ? 1 : 0,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        return revision + 1;
      }),
    );
  }

  Future<String> databaseForBackup() async {
    await _writes.done;
    return (await _open()).path;
  }

  Future<Database> _open() => _connection.open(_create);

  Future<Database> _create() async {
    final factory = sqliteFactory;
    return factory.openDatabase(
      databasePath ??
          await PersonalDatabasePaths.resolve(
            'mubangumi_community_drafts.sqlite',
          ),
      options: OpenDatabaseOptions(
        onConfigure: configurePersonalDatabase,
        version: 2,
        onUpgrade: (db, old, _) async {
          if (old < 2) {
            await db.execute(
              'ALTER TABLE draft ADD COLUMN revision INTEGER NOT NULL DEFAULT 1',
            );
            await db.execute(
              'ALTER TABLE draft ADD COLUMN deleted INTEGER NOT NULL DEFAULT 0',
            );
          }
        },
        onCreate: (db, _) => db.execute('''
          CREATE TABLE draft (
            draft_key TEXT PRIMARY KEY NOT NULL,
            title TEXT NOT NULL,
            content TEXT NOT NULL,
            updated_at INTEGER NOT NULL,
            revision INTEGER NOT NULL DEFAULT 1,
            deleted INTEGER NOT NULL DEFAULT 0
          )
        '''),
      ),
    );
  }

  Future<void> close() async {
    await _writes.done;
    await _connection.close();
  }
}
