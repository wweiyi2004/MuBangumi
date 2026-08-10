import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

class LocalUserPreference {
  const LocalUserPreference({
    required this.username,
    this.note = '',
    this.blocked = false,
    this.updatedAt,
  });

  final String username;
  final String note;
  final bool blocked;
  final DateTime? updatedAt;

  String get key => username.trim().toLowerCase();

  LocalUserPreference copyWith({String? note, bool? blocked}) =>
      LocalUserPreference(
        username: username,
        note: note ?? this.note,
        blocked: blocked ?? this.blocked,
        updatedAt: DateTime.now(),
      );
}

abstract class UserPreferenceRepository {
  Future<List<LocalUserPreference>> loadAll();
  Future<void> save(LocalUserPreference preference);
}

class UserPreferenceStore implements UserPreferenceRepository {
  UserPreferenceStore._();

  static final shared = UserPreferenceStore._();

  Database? _database;
  Future<Database>? _opening;
  static bool _ffiReady = false;

  @override
  Future<List<LocalUserPreference>> loadAll() async {
    final database = await _open();
    final rows = await database.query(
      'user_preference',
      orderBy: 'updated_at DESC',
    );
    return [
      for (final row in rows)
        LocalUserPreference(
          username: row['username']?.toString() ?? '',
          note: row['note']?.toString() ?? '',
          blocked: row['blocked'] == 1,
          updatedAt: DateTime.fromMillisecondsSinceEpoch(
            (row['updated_at'] as num?)?.toInt() ?? 0,
          ),
        ),
    ];
  }

  @override
  Future<void> save(LocalUserPreference preference) async {
    final key = preference.key;
    if (key.isEmpty) return;
    final database = await _open();
    await database.insert('user_preference', {
      'username': key,
      'note': preference.note.trim(),
      'blocked': preference.blocked ? 1 : 0,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
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
    return openDatabase(
      path.join(root, 'mubangumi_user_preferences.sqlite'),
      version: 1,
      onCreate: (database, _) async {
        await database.execute('''
          CREATE TABLE user_preference (
            username TEXT PRIMARY KEY NOT NULL,
            note TEXT NOT NULL DEFAULT '',
            blocked INTEGER NOT NULL DEFAULT 0,
            updated_at INTEGER NOT NULL
          )
        ''');
      },
    );
  }
}
