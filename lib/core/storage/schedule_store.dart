import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

import '../../models/schedule_models.dart';

/// Persists user-arranged seasonal schedules locally.
class ScheduleStore {
  ScheduleStore._();

  @visibleForTesting
  ScheduleStore.test();

  static final shared = ScheduleStore._();

  Database? _database;
  Future<Database>? _opening;
  static bool _ffiReady = false;

  Future<SeasonSchedule> load(SeasonKey season) async {
    final database = await _open();
    final rows = await database.query(
      'season_schedule',
      columns: const ['payload'],
      where: 'season_key = ?',
      whereArgs: [season.id],
      limit: 1,
    );
    if (rows.isEmpty) return SeasonSchedule.empty(season);
    try {
      final decoded = jsonDecode(rows.first['payload']! as String);
      if (decoded is! Map) return SeasonSchedule.empty(season);
      final schedule = SeasonSchedule.fromJson(
        Map<String, dynamic>.from(decoded),
      );
      // Keep requested season key even if payload is older/corrupt.
      return schedule.copyWith(season: season);
    } catch (_) {
      return SeasonSchedule.empty(season);
    }
  }

  Future<void> save(SeasonSchedule schedule) async {
    final database = await _open();
    await database.insert('season_schedule', {
      'season_key': schedule.season.id,
      'payload': jsonEncode(schedule.toJson()),
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// All season keys the user has ever saved (newest first).
  Future<List<SeasonKey>> listSeasons() async {
    final database = await _open();
    final rows = await database.query(
      'season_schedule',
      columns: const ['season_key', 'updated_at'],
      orderBy: 'updated_at DESC',
    );
    final result = <SeasonKey>[];
    final seen = <String>{};
    for (final row in rows) {
      final raw = row['season_key']?.toString() ?? '';
      if (raw.isEmpty || !seen.add(raw)) continue;
      result.add(SeasonKey.fromId(raw));
    }
    return result;
  }

  Future<void> deleteSeason(SeasonKey season) async {
    final database = await _open();
    await database.delete(
      'season_schedule',
      where: 'season_key = ?',
      whereArgs: [season.id],
    );
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
    final databasePath = path.join(root, 'mubangumi_schedule.sqlite');
    return openDatabase(
      databasePath,
      version: 1,
      onCreate: (database, _) async {
        await database.execute('''
          CREATE TABLE season_schedule (
            season_key TEXT PRIMARY KEY NOT NULL,
            payload TEXT NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
      },
    );
  }
}
