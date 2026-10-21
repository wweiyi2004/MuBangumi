import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'sqlite_support.dart';
import 'serial_task_queue.dart';

Map<String, dynamic>? _decodeCacheMap(String source) {
  final value = jsonDecode(source);
  return value is Map ? Map<String, dynamic>.from(value) : null;
}

String _encodeCacheMap(Map<String, dynamic> value) => jsonEncode(value);

class CommunityCache {
  CommunityCache._() : _connection = SqliteConnection();

  CommunityCache.test({required Database connection, DateTime Function()? now})
    : _connection = SqliteConnection(connection: connection) {
    _now = now ?? DateTime.now;
  }

  static final shared = CommunityCache._();

  final SqliteConnection _connection;
  final _writes = SerialTaskQueue();
  DateTime Function() _now = DateTime.now;
  DateTime? _lastPruned;
  int _writesSincePrune = 0;
  Future<void>? _pruning;
  static const maxAge = Duration(days: 30);
  static const maxEntries = 2000;
  static const maxPayloadBytes = 64 * 1024 * 1024;

  Future<Map<String, dynamic>?> readJson(String key) =>
      readDecoded(key, _decodeCacheMap);

  /// Decode a whole payload in one worker, including typed model construction.
  Future<T?> readDecoded<T>(String key, T? Function(String) decode) async {
    try {
      await _writes.done;
      final database = await _open();
      final payload = await _readPayload(database, key);
      if (payload == null) return null;
      return payload.length >= 64 * 1024
          ? await compute(decode, payload, debugLabel: 'cache.decode')
          : decode(payload);
    } catch (_) {
      return null;
    }
  }

  Future<String?> _readPayload(Database database, String key) async {
    final rows = await database.query(
      'community_cache',
      columns: const ['payload'],
      where: 'cache_key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['payload'] as String;
  }

  Future<void> writeJson(
    String key,
    Map<String, dynamic> value, {
    bool accountScoped = false,
  }) => updateEncoded(key, (_) async {
    final large = value.values.any(
      (entry) =>
          entry is List && entry.length >= 100 ||
          entry is Map && entry.length >= 100 ||
          entry is String && entry.length >= 64 * 1024,
    );
    return large ? compute(_encodeCacheMap, value) : _encodeCacheMap(value);
  }, accountScoped: accountScoped);

  /// Reserve write order before any asynchronous encoding. Logout/removal is
  /// queued behind prior writes so their workers cannot recreate cleared data.
  Future<void> updateEncoded(
    String key,
    Future<String?> Function(String?) update, {
    bool readExisting = false,
    bool accountScoped = false,
  }) => _writes.run(() async {
    try {
      final database = await _open();
      final previous = readExisting ? await _readPayload(database, key) : null;
      final payload = await update(previous);
      if (readExisting && payload == previous) return;
      if (payload == null) {
        await database.delete(
          'community_cache',
          where: 'cache_key = ?',
          whereArgs: [key],
        );
        return;
      }
      await database.insert('community_cache', {
        'cache_key': key,
        'payload': payload,
        'updated_at': _now().millisecondsSinceEpoch,
        'account_scoped': accountScoped ? 1 : 0,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      _writesSincePrune++;
      unawaited(_pruneIfNeeded(database));
    } catch (_) {
      // Cache is best-effort; network success must not depend on it.
    }
  });

  Future<void> remove(String key) => _writes.run(() async {
    try {
      final database = await _open();
      await database.delete(
        'community_cache',
        where: 'cache_key = ?',
        whereArgs: [key],
      );
    } catch (_) {}
  });

  Future<void> removePrefix(String prefix) => _writes.run(() async {
    try {
      final database = await _open();
      await database.delete(
        'community_cache',
        where: 'substr(cache_key,1,?) = ?',
        whereArgs: [prefix.length, prefix],
      );
    } catch (_) {
      /* Disposable cache cleanup must not invalidate credential cleanup. */
    }
  });

  Future<void> clearAccountData() => _writes.run(() async {
    try {
      final database = await _open();
      await database.delete(
        'community_cache',
        where: 'account_scoped = ?',
        whereArgs: [1],
      );
    } catch (_) {}
  });

  /// Removes only disposable cache rows. SQLite reuses the freed pages.
  Future<void> prune() async {
    await _writes.done;
    await _pruneIfNeeded(await _open(), force: true);
  }

  Future<void> _pruneIfNeeded(Database database, {bool force = false}) {
    final pending = _pruning;
    if (pending != null) return pending;
    final now = _now();
    if (!force &&
        _lastPruned != null &&
        _writesSincePrune < 50 &&
        now.difference(_lastPruned!) < const Duration(hours: 6)) {
      return Future.value();
    }
    late final Future<void> operation;
    operation = database
        .transaction((txn) async {
          // Personal collection/episode snapshots remain readable offline even
          // when old. They still share the bounded entry/byte budget below.
          await txn.delete(
            'community_cache',
            where: '''cache_key != ? AND updated_at < ?
              AND cache_key NOT GLOB 'collections_snapshot:*'
              AND cache_key NOT GLOB 'episode_collections_snapshot:*' ''',
            whereArgs: [
              'session_last_user',
              now.subtract(maxAge).millisecondsSinceEpoch,
            ],
          );
          final rows = await txn.rawQuery(
            '''
        SELECT cache_key, length(CAST(payload AS BLOB)) AS bytes
        FROM community_cache WHERE cache_key != ?
        ORDER BY CASE WHEN cache_key GLOB 'collections_snapshot:*'
          OR cache_key GLOB 'episode_collections_snapshot:*' THEN 0 ELSE 1 END,
          updated_at DESC, cache_key ASC
      ''',
            ['session_last_user'],
          );
          var kept = 0;
          var bytes = 0;
          final batch = txn.batch();
          for (final row in rows) {
            final size = (row['bytes'] as num).toInt();
            if (kept >= maxEntries || bytes + size > maxPayloadBytes) {
              batch.delete(
                'community_cache',
                where: 'cache_key = ?',
                whereArgs: [row['cache_key']],
              );
            } else {
              kept++;
              bytes += size;
            }
          }
          await batch.commit(noResult: true);
        })
        .then((_) {
          _lastPruned = now;
          _writesSincePrune = 0;
        })
        .catchError((Object _) {
          // Cleanup failure cannot turn a successful read or write into an error.
        })
        .whenComplete(() {
          if (identical(_pruning, operation)) _pruning = null;
        });
    _pruning = operation;
    return operation;
  }

  Future<Database> _open() => _connection.open(_createDatabase);

  Future<Database> _createDatabase() async {
    final factory = sqliteFactory;
    // Android / iOS use the sqflite plugin factory from package:sqflite.
    // Never reopen a cache shipped next to an old Windows executable. This is
    // disposable data; personal schedules, drafts and pending writes live in
    // separate stores and are deliberately not migrated or removed here.
    final root = Platform.isWindows
        ? path.join((await getApplicationSupportDirectory()).path, 'cache-v2')
        : await factory.getDatabasesPath();
    final databasePath = path.join(root, 'mubangumi.sqlite');
    final database = await factory.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 3,
        onUpgrade: (database, oldVersion, newVersion) async {
          if (oldVersion < 2) await discardLegacyAccountCache(database);
          if (oldVersion < 3) await discardUnscopedCommunitySnapshots(database);
        },
        onCreate: (database, _) async {
          await database.execute('''
          CREATE TABLE community_cache (
            cache_key TEXT PRIMARY KEY NOT NULL,
            payload TEXT NOT NULL,
            updated_at INTEGER NOT NULL,
            account_scoped INTEGER NOT NULL DEFAULT 0
          )
        ''');
        },
      ),
    );
    unawaited(_pruneIfNeeded(database));
    return database;
  }
}

/// These disposable snapshots predate per-account namespaces. Their owner is
/// unknown, so do not assign them to whichever account opens the new version.
Future<void> discardUnscopedCommunitySnapshots(
  DatabaseExecutor database,
) async {
  await database.delete(
    'community_cache',
    where:
        "cache_key GLOB 'topics:*' OR cache_key GLOB 'groups:*' OR cache_key GLOB 'group:*' OR cache_key GLOB 'timeline:*'",
  );
}

/// Account cache from releases without credential-bound identities cannot be
/// trusted. This migration never touches durable personal-data tables.
Future<void> discardLegacyAccountCache(DatabaseExecutor database) async {
  await database.delete(
    'community_cache',
    where:
        'account_scoped = 1 OR cache_key = ? '
        'OR cache_key LIKE ? OR cache_key LIKE ?',
    whereArgs: [
      'session_last_user',
      'collections_snapshot:%',
      'episode_collections_snapshot:%',
    ],
  );
}
