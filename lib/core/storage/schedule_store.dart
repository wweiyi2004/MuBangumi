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
  Future<void> _writes = Future.value();
  Future<void> flushWrites() async => _writes;
  Future<T> _write<T>(Future<T> Function() action) {
    final next = _writes.then((_) => action());
    _writes = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<String> databaseForBackup() async {
    await _writes;
    return (await _open()).path;
  }

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
    return _decode(rows.first['payload'], season);
  }

  SeasonSchedule _decode(Object? payload, SeasonKey season) {
    try {
      final raw = jsonDecode(payload as String);
      if (raw is! Map || raw['season'] is! Map || raw['items'] is! List) {
        throw const FormatException();
      }
      final key = raw['season'] as Map;
      if (key['year'] != season.year || key['quarter'] != season.quarter) {
        throw const FormatException();
      }
      final ids = <int>{};
      for (final item in raw['items'] as List) {
        if (item is! Map ||
            item['subjectId'] is! int ||
            (item['subjectId'] as int) <= 0 ||
            !ids.add(item['subjectId'] as int)) {
          throw const FormatException();
        }
        final day = item['weekday'];
        if (day != null && (day is! int || day < 1 || day > 7)) {
          throw const FormatException();
        }
      }
      return SeasonSchedule.fromJson(Map<String, dynamic>.from(raw));
    } catch (_) {
      throw StateError('${season.label}数据损坏，原内容已保留。请从备份恢复后重试');
    }
  }

  Future<void> save(SeasonSchedule schedule) => _write(() async {
    final database = await _open();
    final payload = jsonEncode(schedule.toJson());
    _decode(payload, schedule.season);
    await database.transaction((transaction) async {
      final old = await transaction.query(
        'season_schedule',
        columns: ['payload'],
        where: 'season_key = ?',
        whereArgs: [schedule.season.id],
      );
      if (old.isNotEmpty) _decode(old.single['payload'], schedule.season);
      await transaction.insert('season_schedule', {
        'season_key': schedule.season.id,
        'payload': payload,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  });

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

  /// Fail closed so damaged data cannot silently cancel existing reminders.
  Future<List<SeasonSchedule>> loadAllSchedules() async {
    final database = await _open();
    final rows = await database.query(
      'season_schedule',
      columns: const ['season_key', 'payload'],
      orderBy: 'updated_at DESC',
    );
    final result = <SeasonSchedule>[];
    for (final row in rows) {
      final rawKey = row['season_key']?.toString() ?? '';
      if (!RegExp(r'^\d+-Q[0-3]$').hasMatch(rawKey)) {
        throw StateError('季度索引损坏，原内容已保留');
      }
      result.add(_decode(row['payload'], SeasonKey.fromId(rawKey)));
    }
    return result;
  }

  Future<void> deleteSeason(SeasonKey season) => _write(() async {
    final database = await _open();
    await database.transaction((transaction) async {
      final old = await transaction.query(
        'season_schedule',
        columns: ['payload'],
        where: 'season_key = ?',
        whereArgs: [season.id],
      );
      if (old.isNotEmpty) _decode(old.single['payload'], season);
      await transaction.delete(
        'season_schedule',
        where: 'season_key = ?',
        whereArgs: [season.id],
      );
    });
  });

  /// Notification ownership survives deleted seasons and application restarts.
  /// Null identifies installations that predate notification ID tracking.
  Future<Set<int>?> readReminderIds() async {
    final database = await _open();
    final rows = await database.query('schedule_reminder_state');
    if (rows.isEmpty) return null;
    final ids = jsonDecode(rows.single['ids_json']! as String) as List;
    return {for (final id in ids) id as int};
  }

  Future<void> writeReminderIds(Set<int> ids) => _write(() async {
    final database = await _open();
    await database.insert('schedule_reminder_state', {
      'id': 1,
      'ids_json': jsonEncode(ids.toList()),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  });

  @visibleForTesting
  Future<void> close() async {
    await _writes;
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
      onConfigure: (db) async {
        await db.rawQuery('PRAGMA journal_mode=DELETE');
      },
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
