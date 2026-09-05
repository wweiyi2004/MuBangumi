import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

class CommunityCache {
  CommunityCache._();

  CommunityCache.test({required Database connection, DateTime Function()? now})
    : _database = connection {
    _now = now ?? DateTime.now;
  }

  static final shared = CommunityCache._();

  Database? _database;
  Future<Database>? _opening;
  static bool _ffiReady = false;
  DateTime Function() _now = DateTime.now;
  DateTime? _lastPruned;
  int _writesSincePrune = 0;
  Future<void>? _pruning;
  static const maxAge = Duration(days: 30);
  static const maxEntries = 2000;
  static const maxPayloadBytes = 64 * 1024 * 1024;

  Future<Map<String, dynamic>?> readJson(String key) async {
    try {
      final database = await _open();
      final rows = await database.query(
        'community_cache',
        columns: const ['payload'],
        where: 'cache_key = ?',
        whereArgs: [key],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      try {
        final decoded = jsonDecode(rows.first['payload']! as String);
        return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
      } on FormatException {
        await remove(key);
        return null;
      }
    } catch (_) {
      return null;
    }
  }

  Future<void> writeJson(
    String key,
    Map<String, dynamic> value, {
    bool accountScoped = false,
  }) async {
    try {
      final database = await _open();
      await database.insert('community_cache', {
        'cache_key': key,
        'payload': jsonEncode(value),
        'updated_at': _now().millisecondsSinceEpoch,
        'account_scoped': accountScoped ? 1 : 0,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      _writesSincePrune++;
      unawaited(_pruneIfNeeded(database));
    } catch (_) {
      // Cache is best-effort; network success must not depend on it.
    }
  }

  Future<void> remove(String key) async {
    try {
      final database = await _open();
      await database.delete(
        'community_cache',
        where: 'cache_key = ?',
        whereArgs: [key],
      );
    } catch (_) {}
  }

  Future<void> clearAccountData() async {
    try {
      final database = await _open();
      await database.delete(
        'community_cache',
        where: 'account_scoped = ?',
        whereArgs: [1],
      );
    } catch (_) {}
  }

  /// Removes only disposable cache rows. SQLite reuses the freed pages.
  Future<void> prune() async => _pruneIfNeeded(await _open(), force: true);

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
          // This small identity snapshot supports offline session restoration.
          // It is removed by logout, not ordinary cache eviction.
          await txn.delete(
            'community_cache',
            where: 'cache_key != ? AND updated_at < ?',
            whereArgs: [
              'session_last_user',
              now.subtract(maxAge).millisecondsSinceEpoch,
            ],
          );
          final rows = await txn.rawQuery(
            '''
        SELECT cache_key, length(CAST(payload AS BLOB)) AS bytes
        FROM community_cache WHERE cache_key != ?
        ORDER BY updated_at DESC, cache_key ASC
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
      unawaited(_pruneIfNeeded(database));
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
    // Android / iOS use the sqflite plugin factory from package:sqflite.
    final root = await getDatabasesPath();
    final databasePath = path.join(root, 'mubangumi.sqlite');
    return openDatabase(
      databasePath,
      version: 1,
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
    );
  }
}
