import 'dart:io';

import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

bool _ffiReady = false;

/// Select the platform backend without changing sqflite's global factory.
DatabaseFactory get sqliteFactory {
  if (Platform.isWindows || Platform.isLinux) {
    if (!_ffiReady) {
      ffi.sqfliteFfiInit();
      _ffiReady = true;
    }
    return ffi.databaseFactoryFfi;
  }
  return databaseFactory;
}

/// Bound transient lock waits and retain rollback journals for atomic backups.
Future<void> configurePersonalDatabase(Database database) async {
  await database.rawQuery('PRAGMA busy_timeout=5000');
  await database.rawQuery('PRAGMA journal_mode=DELETE');
}

/// Share one opening attempt and allow a later retry if opening fails.
class SqliteConnection {
  SqliteConnection({Database? connection})
    : _database = connection == null ? null : Future.value(connection);

  Future<Database>? _database;

  Future<Database> open(Future<Database> Function() create) =>
      _database ??= Future<Database>.sync(create).catchError((
        Object error,
        StackTrace stack,
      ) {
        _database = null;
        Error.throwWithStackTrace(error, stack);
      });

  /// The owning repository drains its writes before closing the connection.
  Future<void> close() async {
    await (await _database)?.close();
    _database = null;
  }
}
