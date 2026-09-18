import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

import '../../features/sync/domain/pending_mutation.dart';

// Keep existing callers source-compatible while the model lives with sync.
export '../../features/sync/domain/pending_mutation.dart';

typedef _SubjectVersions = ({int anyId, int collectionId, int completionId});

class BangumiSyncStore {
  BangumiSyncStore({this.databasePath});

  static final shared = BangumiSyncStore();

  Database? _database;
  Future<Database>? _opening;
  final String? databasePath;
  static bool _ffiReady = false;

  Future<void> enqueue({
    required String username,
    required BangumiMutationKind kind,
    required String mutationKey,
    required Map<String, dynamic> payload,
  }) async {
    final database = await _open();
    final now = DateTime.now().millisecondsSinceEpoch;
    await database.transaction((transaction) async {
      final existing = await transaction.query(
        'bangumi_sync_queue',
        columns: const ['id', 'revision', 'created_at', 'payload', 'kind'],
        where: 'username = ? AND mutation_key = ?',
        whereArgs: [username, mutationKey],
        limit: 1,
      );
      final values = <String, Object?>{
        'kind': kind.name,
        'payload': jsonEncode(payload),
        'updated_at': now,
        'attempts': 0,
        'blocked': 0,
        'last_error': null,
      };
      if (existing.isNotEmpty) {
        final prior = jsonDecode(existing.first['payload'] as String) as Map;
        if (mutationKey.startsWith('collection:') &&
            existing.first['kind'] == BangumiMutationKind.collection.name &&
            prior['complete_episodes'] == true) {
          // A previous completion also carries chapter work. Keep its original
          // position so a later status/metadata change cannot erase or reorder it.
          await transaction.update(
            'bangumi_sync_queue',
            {'mutation_key': '$mutationKey:completion:${existing.first['id']}'},
            where: 'id = ?',
            whereArgs: [existing.first['id']],
          );
        } else {
          await transaction.delete(
            'bangumi_sync_queue',
            where: 'id = ?',
            whereArgs: [existing.first['id']],
          );
        }
      }
      // A replacement receives a new monotonic ID: its final intent must run
      // after edits to other keys, regardless of timestamp precision or clock changes.
      final insertedId = await transaction.insert('bangumi_sync_queue', {
        'username': username,
        'mutation_key': mutationKey,
        'created_at': existing.isEmpty ? now : existing.first['created_at'],
        'revision': existing.isEmpty
            ? 1
            : (existing.first['revision'] as num).toInt() + 1,
        ...values,
      });
      final subjectId = (payload['subject_id'] as num?)?.toInt();
      if (subjectId != null && subjectId > 0) {
        final old = await _versionFor(transaction, username, subjectId);
        await transaction.insert('bangumi_sync_versions', {
          'username': username,
          'subject_id': subjectId,
          'any_id': insertedId,
          'collection_id': kind == BangumiMutationKind.collection
              ? insertedId
              : old?.collectionId ?? 0,
          'completion_id':
              kind == BangumiMutationKind.collection &&
                  payload['complete_episodes'] == true
              ? insertedId
              : old?.completionId ?? 0,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<List<PendingBangumiMutation>> pendingFor(
    String username, {
    bool includeBlocked = false,
  }) async {
    final database = await _open();
    final rows = await database.query(
      'bangumi_sync_queue',
      where: includeBlocked ? 'username = ?' : 'username = ? AND blocked = 0',
      whereArgs: [username],
      orderBy: 'id ASC',
    );
    final versions = await _versionsFor(database, username);
    return [for (final row in rows) _decode(row, versions)];
  }

  Future<List<PendingBangumiMutation>> blockedFor(String username) async {
    final database = await _open();
    final rows = await database.query(
      'bangumi_sync_queue',
      where: 'username = ? AND blocked = 1',
      whereArgs: [username],
      orderBy: 'updated_at DESC, id DESC',
    );
    final versions = await _versionsFor(database, username);
    return [for (final row in rows) _decode(row, versions)];
  }

  Future<int> countFor(String username) async {
    final database = await _open();
    final rows = await database.rawQuery(
      'SELECT COUNT(*) AS count FROM bangumi_sync_queue WHERE username = ?',
      [username],
    );
    return (rows.first['count'] as num?)?.toInt() ?? 0;
  }

  Future<int> blockedCountFor(String username) async {
    final database = await _open();
    final rows = await database.rawQuery(
      '''SELECT COUNT(*) AS count FROM bangumi_sync_queue
         WHERE username = ? AND blocked = 1''',
      [username],
    );
    return (rows.first['count'] as num?)?.toInt() ?? 0;
  }

  Future<bool> removeIfUnchanged(PendingBangumiMutation mutation) async {
    final database = await _open();
    final removed = await database.delete(
      'bangumi_sync_queue',
      where: 'id = ? AND revision = ?',
      whereArgs: [mutation.id, mutation.revision],
    );
    return removed > 0;
  }

  Future<bool> markFailure(
    PendingBangumiMutation mutation,
    String message, {
    required bool blocked,
  }) async {
    final database = await _open();
    final updated = await database.rawUpdate(
      '''UPDATE bangumi_sync_queue
         SET attempts = attempts + 1, last_error = ?, blocked = ?, updated_at = ?
         WHERE id = ? AND revision = ?''',
      [
        message,
        blocked ? 1 : 0,
        DateTime.now().millisecondsSinceEpoch,
        mutation.id,
        mutation.revision,
      ],
    );
    return updated > 0;
  }

  Future<void> retryBlocked(String username) async {
    final database = await _open();
    await database.transaction((txn) async {
      final versions = await _versionsFor(txn, username);
      final rows = await txn.query(
        'bangumi_sync_queue',
        where: 'username = ? AND blocked = 1',
        whereArgs: [username],
      );
      for (final row in rows) {
        if (_decode(row, versions).superseded) continue;
        await txn.update(
          'bangumi_sync_queue',
          {'blocked': 0, 'last_error': null, 'attempts': 0},
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      }
    });
  }

  Future<bool> retryIfUnchanged(PendingBangumiMutation mutation) async {
    final database = await _open();
    return database.transaction((txn) async {
      final rows = await txn.query(
        'bangumi_sync_queue',
        where: 'id = ? AND username = ? AND revision = ? AND blocked = 1',
        whereArgs: [mutation.id, mutation.username, mutation.revision],
      );
      if (rows.isEmpty ||
          _decode(
            rows.single,
            await _versionsFor(txn, mutation.username),
          ).superseded) {
        return false;
      }
      final updated = await txn.update(
        'bangumi_sync_queue',
        {
          'blocked': 0,
          'last_error': null,
          'attempts': 0,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [mutation.id],
      );
      return updated > 0;
    });
  }

  Future<bool> discardIfUnchanged(PendingBangumiMutation mutation) async {
    final database = await _open();
    final removed = await database.delete(
      'bangumi_sync_queue',
      where: 'id = ? AND username = ? AND revision = ? AND blocked = 1',
      whereArgs: [mutation.id, mutation.username, mutation.revision],
    );
    return removed > 0;
  }

  Future<void> close() async {
    final database = _database;
    _database = null;
    if (database != null) await database.close();
  }

  Future<Database> _open() async {
    final current = _database;
    if (current != null) return current;
    final opening = _opening;
    if (opening != null) return opening;
    final future = _createDatabase();
    _opening = future;
    try {
      final database = await future;
      _database = database;
      return database;
    } finally {
      _opening = null;
    }
  }

  Future<Database> _createDatabase() async {
    if (Platform.isWindows || Platform.isLinux) {
      if (!_ffiReady) {
        ffi.sqfliteFfiInit();
        databaseFactory = ffi.databaseFactoryFfi;
        _ffiReady = true;
      }
    }
    final root = await getDatabasesPath();
    final resolvedPath =
        databasePath ?? path.join(root, 'mubangumi_sync.sqlite');
    return openDatabase(
      resolvedPath,
      version: 3,
      onUpgrade: (database, oldVersion, _) async {
        if (oldVersion < 2) {
          final rows = await database.query(
            'bangumi_sync_queue',
            columns: ['id'],
            orderBy: 'updated_at ASC, id ASC',
          );
          var nextId = rows.fold<int>(
            0,
            (largest, row) =>
                (row['id'] as int) > largest ? row['id'] as int : largest,
          );
          for (final row in rows) {
            await database.update(
              'bangumi_sync_queue',
              {'id': ++nextId},
              where: 'id = ?',
              whereArgs: [row['id']],
            );
          }
        }
        if (oldVersion < 3) {
          await _createVersions(database);
          final rows = await database.query(
            'bangumi_sync_queue',
            orderBy: 'id ASC',
          );
          for (final row in rows) {
            final payload = jsonDecode(row['payload'] as String) as Map;
            final subjectId = (payload['subject_id'] as num?)?.toInt();
            if (subjectId == null || subjectId <= 0) continue;
            final username = row['username'] as String;
            final old = await _versionFor(database, username, subjectId);
            final collection =
                row['kind'] == BangumiMutationKind.collection.name;
            await database.insert(
              'bangumi_sync_versions',
              {
                'username': username,
                'subject_id': subjectId,
                'any_id': row['id'],
                'collection_id': collection
                    ? row['id']
                    : old?.collectionId ?? 0,
                'completion_id':
                    collection && payload['complete_episodes'] == true
                    ? row['id']
                    : old?.completionId ?? 0,
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        }
      },
      onCreate: (database, _) async {
        await _createVersions(database);
        await database.execute('''
          CREATE TABLE bangumi_sync_queue (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username TEXT NOT NULL,
            mutation_key TEXT NOT NULL,
            kind TEXT NOT NULL,
            payload TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            attempts INTEGER NOT NULL DEFAULT 0,
            revision INTEGER NOT NULL DEFAULT 1,
            blocked INTEGER NOT NULL DEFAULT 0,
            last_error TEXT
          )
        ''');
        await database.execute('''
          CREATE UNIQUE INDEX bangumi_sync_queue_account_key
          ON bangumi_sync_queue(username, mutation_key)
        ''');
      },
    );
  }

  Future<void> _createVersions(Database db) => db.execute(
    'CREATE TABLE bangumi_sync_versions (username TEXT NOT NULL, subject_id INTEGER NOT NULL, any_id INTEGER NOT NULL, collection_id INTEGER NOT NULL, completion_id INTEGER NOT NULL, PRIMARY KEY(username, subject_id))',
  );

  Future<_SubjectVersions?> _versionFor(
    DatabaseExecutor db,
    String username,
    int subjectId,
  ) async {
    final rows = await db.query(
      'bangumi_sync_versions',
      where: 'username = ? AND subject_id = ?',
      whereArgs: [username, subjectId],
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    return (
      anyId: row['any_id'] as int,
      collectionId: row['collection_id'] as int,
      completionId: row['completion_id'] as int,
    );
  }

  Future<Map<int, _SubjectVersions>> _versionsFor(
    DatabaseExecutor db,
    String username,
  ) async {
    final rows = await db.query(
      'bangumi_sync_versions',
      where: 'username = ?',
      whereArgs: [username],
    );
    return {
      for (final row in rows)
        row['subject_id'] as int: (
          anyId: row['any_id'] as int,
          collectionId: row['collection_id'] as int,
          completionId: row['completion_id'] as int,
        ),
    };
  }

  PendingBangumiMutation _decode(
    Map<String, Object?> row,
    Map<int, _SubjectVersions> versions,
  ) {
    final kind = BangumiMutationKind.values.firstWhere(
      (value) => value.name == row['kind'],
      orElse: () => BangumiMutationKind.episode,
    );
    final decoded = jsonDecode(row['payload']! as String) as Map;
    final version = versions[(decoded['subject_id'] as num?)?.toInt()];
    final latest = kind == BangumiMutationKind.episode
        ? version?.completionId ?? 0
        : kind == BangumiMutationKind.collection &&
              decoded['complete_episodes'] != true
        ? version?.collectionId ?? 0
        : version?.anyId ?? 0;
    return PendingBangumiMutation(
      id: (row['id'] as num).toInt(),
      username: row['username']! as String,
      kind: kind,
      mutationKey: row['mutation_key']! as String,
      payload: Map<String, dynamic>.from(decoded),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (row['created_at'] as num).toInt(),
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        (row['updated_at'] as num).toInt(),
      ),
      revision: (row['revision'] as num).toInt(),
      attempts: (row['attempts'] as num).toInt(),
      blocked: (row['blocked'] as num).toInt() != 0,
      lastError: row['last_error']?.toString(),
      superseded: row['blocked'] != 0 && latest > (row['id'] as int),
    );
  }
}
