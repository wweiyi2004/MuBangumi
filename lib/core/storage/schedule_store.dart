import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

import '../../models/schedule_models.dart';

/// Persists user-arranged seasonal schedules locally.
class ScheduleStore {
  ScheduleStore._() : databasePath = null;

  @visibleForTesting
  ScheduleStore.test({this.databasePath});

  static final shared = ScheduleStore._();

  final String? databasePath;

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

  /// All saved schedules, newest first. Corrupt rows are ignored.
  Future<List<SeasonSchedule>> loadAllSchedules() async {
    final database = await _open();
    final rows = await database.query(
      'season_schedule',
      columns: const ['season_key', 'payload'],
      orderBy: 'updated_at DESC',
    );
    final result = <SeasonSchedule>[];
    for (final row in rows) {
      try {
        final rawKey = row['season_key']?.toString() ?? '';
        final decoded = jsonDecode(row['payload']! as String);
        if (rawKey.isEmpty || decoded is! Map) continue;
        result.add(
          SeasonSchedule.fromJson(
            Map<String, dynamic>.from(decoded),
          ).copyWith(season: SeasonKey.fromId(rawKey)),
        );
      } catch (_) {
        // One broken quarter must not prevent reminders for the other quarters.
      }
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

  /// Notification ownership survives deleted seasons and application restarts.
  /// Null identifies installations that predate notification ID tracking.
  Future<Set<int>?> readReminderIds() async {
    final database = await _open();
    final rows = await database.query('schedule_reminder_state');
    if (rows.isEmpty) return null;
    final ids = jsonDecode(rows.single['ids_json']! as String) as List;
    return {for (final id in ids) id as int};
  }

  Future<void> writeReminderIds(Set<int> ids) async {
    final database = await _open();
    await database.insert('schedule_reminder_state', {
      'id': 1,
      'ids_json': jsonEncode(ids.toList()),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @visibleForTesting
  Future<void> close() async {
    final database = _database;
    _database = null;
    await database?.close();
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
    final resolvedPath =
        databasePath ??
        path.join(await getDatabasesPath(), 'mubangumi_schedule.sqlite');
    return openDatabase(
      resolvedPath,
      version: 2,
      onCreate: (database, _) async {
        await database.execute('''
          CREATE TABLE season_schedule (
            season_key TEXT PRIMARY KEY NOT NULL,
            payload TEXT NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
        await _createReminderIdsTable(database);
      },
      onUpgrade: (database, oldVersion, _) async {
        if (oldVersion < 2) await _createReminderIdsTable(database);
      },
    );
  }

  Future<void> _createReminderIdsTable(Database database) =>
      database.execute('''
    CREATE TABLE schedule_reminder_state (
      id INTEGER PRIMARY KEY NOT NULL CHECK (id = 1),
      ids_json TEXT NOT NULL
    )
  ''');
}
