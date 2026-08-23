import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

enum BangumiMutationKind { episode, collection, episodesBatch }

class PendingBangumiMutation {
  const PendingBangumiMutation({
    required this.id,
    required this.username,
    required this.kind,
    required this.mutationKey,
    required this.payload,
    required this.createdAt,
    required this.updatedAt,
    required this.revision,
    required this.attempts,
    required this.blocked,
    this.lastError,
  });

  final int id;
  final String username;
  final BangumiMutationKind kind;
  final String mutationKey;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int revision;
  final int attempts;
  final bool blocked;
  final String? lastError;
}

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
        columns: const ['id', 'revision'],
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
      if (existing.isEmpty) {
        await transaction.insert('bangumi_sync_queue', {
          'username': username,
          'mutation_key': mutationKey,
          'created_at': now,
          'revision': 1,
          ...values,
        });
      } else {
        await transaction.update(
          'bangumi_sync_queue',
          {
            ...values,
            'revision': (existing.first['revision'] as num).toInt() + 1,
          },
          where: 'id = ?',
          whereArgs: [existing.first['id']],
        );
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
      orderBy: 'created_at ASC, id ASC',
    );
    return [for (final row in rows) _decode(row)];
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
    await database.update(
      'bangumi_sync_queue',
      const {'blocked': 0, 'last_error': null, 'attempts': 0},
      where: 'username = ?',
      whereArgs: [username],
    );
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
      version: 1,
      onCreate: (database, _) async {
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

  PendingBangumiMutation _decode(Map<String, Object?> row) {
    final kind = BangumiMutationKind.values.firstWhere(
      (value) => value.name == row['kind'],
      orElse: () => BangumiMutationKind.episode,
    );
    final decoded = jsonDecode(row['payload']! as String);
    return PendingBangumiMutation(
      id: (row['id'] as num).toInt(),
      username: row['username']! as String,
      kind: kind,
      mutationKey: row['mutation_key']! as String,
      payload: Map<String, dynamic>.from(decoded as Map),
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
    );
  }
}
