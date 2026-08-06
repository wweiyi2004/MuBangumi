import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

class CommunityCache {
  CommunityCache._();

  static final shared = CommunityCache._();

  Database? _database;
  Future<Database>? _opening;
  static bool _ffiReady = false;

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
        'updated_at': DateTime.now().millisecondsSinceEpoch,
        'account_scoped': accountScoped ? 1 : 0,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
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
