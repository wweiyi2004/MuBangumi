import 'dart:io';
import 'package:flutter/foundation.dart';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

bool _ffiReady = false;

/// Durable stores must not move when a portable installation or its CWD moves.
/// Legacy files are snapshotted, never moved/deleted or merged over newer data.
abstract final class PersonalDatabasePaths {
  static const names = [
    'mubangumi_schedule.sqlite',
    'mubangumi_sync.sqlite',
    'mubangumi_pm_drafts.sqlite',
    'mubangumi_browsing.sqlite',
    'mubangumi_rss.sqlite',
    'mubangumi_user_preferences.sqlite',
    'mubangumi_community_drafts.sqlite',
    'mubangumi_backup_import.sqlite',
  ];
  static final _opening = <String, Future<String>>{};
  static Directory? _testSupport;

  @visibleForTesting
  static void isolateForTests(Directory support) {
    _testSupport = support;
    _opening.clear();
  }

  static List<Directory> get _legacyDirectories => _testSupport != null
      ? []
      : [
          Directory(
            path.join(
              Directory.current.path,
              '.dart_tool',
              'sqflite_common_ffi',
              'databases',
            ),
          ),
          Directory(
            path.join(
              path.dirname(Platform.resolvedExecutable),
              '.dart_tool',
              'sqflite_common_ffi',
              'databases',
            ),
          ),
        ];

  /// Locate old data before opening empty stores; a selected interrupted
  /// migration is retried without overwriting already copied databases.
  static Future<bool> prepare({
    Directory? supportDirectory,
    List<Directory>? legacyDirectories,
  }) async {
    final support =
        supportDirectory ??
        _testSupport ??
        await getApplicationSupportDirectory();
    final ready = File(path.join(support.path, 'databases', 'migration-ready'));
    if (await ready.exists()) return true;
    final pending = File(
      path.join(support.path, 'databases', 'migration-source'),
    );
    if (await pending.exists()) {
      await migrateFrom(
        Directory(await pending.readAsString()),
        supportDirectory: support,
      );
      return true;
    }
    for (final directory in legacyDirectories ?? _legacyDirectories) {
      if (await _containsPersonalFiles(directory)) {
        await migrateFrom(directory, supportDirectory: support);
        return true;
      }
    }
    if (await _containsPersonalFiles(
      Directory(path.join(support.path, 'databases')),
    )) {
      await startFresh(supportDirectory: support);
      return true;
    }
    if (await File(
      path.join(support.path, 'cache-v2', 'mubangumi.sqlite'),
    ).exists()) {
      return false;
    }
    await startFresh(supportDirectory: support);
    return true;
  }

  static Future<bool> _containsPersonalFiles(Directory directory) async {
    for (final name in names) {
      if (await File(path.join(directory.path, name)).exists()) return true;
    }
    return false;
  }

  static Future<void> migrateFrom(
    Directory directory, {
    Directory? supportDirectory,
  }) async {
    final support =
        supportDirectory ??
        _testSupport ??
        await getApplicationSupportDirectory();
    final candidates = [
      directory,
      Directory(
        path.join(
          directory.path,
          '.dart_tool',
          'sqflite_common_ffi',
          'databases',
        ),
      ),
    ];
    if (!await _containsPersonalFiles(candidates[0]) &&
        !await _containsPersonalFiles(candidates[1])) {
      throw StateError('此目录未找到旧版个人数据库，请选择旧程序目录或 databases 目录');
    }
    final root = Directory(path.join(support.path, 'databases'));
    await root.create(recursive: true);
    await File(
      path.join(root.path, 'migration-source'),
    ).writeAsString(directory.absolute.path, flush: true);
    for (final name in names) {
      await migrate(
        name,
        supportDirectory: support,
        legacyDirectories: candidates,
      );
    }
    await startFresh(supportDirectory: support);
  }

  static Future<void> startFresh({Directory? supportDirectory}) async {
    final support =
        supportDirectory ??
        _testSupport ??
        await getApplicationSupportDirectory();
    final root = Directory(path.join(support.path, 'databases'));
    await root.create(recursive: true);
    await File(
      path.join(root.path, 'migration-ready'),
    ).writeAsString('1', flush: true);
    final pending = File(path.join(root.path, 'migration-source'));
    if (await pending.exists()) await pending.delete();
  }

  static Future<String> resolve(String name) => _opening.putIfAbsent(name, () {
    final opening = migrate(name);
    return opening.catchError((Object error, StackTrace stack) {
      _opening.remove(name);
      Error.throwWithStackTrace(error, stack);
    });
  });

  static Future<String> migrate(
    String name, {
    Directory? supportDirectory,
    List<Directory>? legacyDirectories,
  }) async {
    if (path.basename(name) != name ||
        !RegExp(r'^mubangumi_[a-z_]+\.sqlite$').hasMatch(name)) {
      throw ArgumentError.value(name, 'name', 'Invalid personal database');
    }
    if (!(Platform.isWindows || Platform.isLinux) &&
        supportDirectory == null &&
        _testSupport == null) {
      return path.join(await sqliteFactory.getDatabasesPath(), name);
    }
    final support =
        supportDirectory ??
        _testSupport ??
        await getApplicationSupportDirectory();
    final root = Directory(path.join(support.path, 'databases'));
    await root.create(recursive: true);
    final target = path.join(root.path, name);
    if (await File(target).exists()) return target;
    final candidates = legacyDirectories ?? _legacyDirectories;
    for (final directory in candidates) {
      final source = path.join(directory.path, name);
      if (path.equals(path.absolute(source), path.absolute(target)) ||
          !await File(source).exists()) {
        continue;
      }
      final pending =
          '$target.migration-$pid-${DateTime.now().microsecondsSinceEpoch}';
      Database? legacy;
      try {
        legacy = await sqliteFactory.openDatabase(
          source,
          options: OpenDatabaseOptions(singleInstance: false),
        );
        await legacy.rawQuery('PRAGMA busy_timeout=5000');
        // SQLite, rather than a file copy, includes committed WAL contents and
        // recovers a hot rollback journal before creating a consistent snapshot.
        await legacy.execute("VACUUM INTO '${pending.replaceAll("'", "''")}'");
        await legacy.close();
        legacy = null;
        final snapshot = await sqliteFactory.openDatabase(
          pending,
          options: OpenDatabaseOptions(singleInstance: false, readOnly: true),
        );
        try {
          final check = await snapshot.rawQuery('PRAGMA quick_check');
          if (check.length != 1 || check.single.values.single != 'ok') {
            throw StateError('旧数据校验失败，请保留旧目录并重试迁移');
          }
        } finally {
          await snapshot.close();
        }
        if (!await File(target).exists()) await File(pending).rename(target);
      } finally {
        await legacy?.close();
        if (await File(pending).exists()) await File(pending).delete();
      }
      return target;
    }
    return target;
  }
}

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
