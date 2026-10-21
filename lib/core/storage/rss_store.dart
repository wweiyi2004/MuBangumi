import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../../models/rss_models.dart';
import 'serial_task_queue.dart';
import 'sqlite_support.dart';

/// Local persistence for RSS sources, bindings, and matched items.
class RssStore {
  RssStore._() : databasePath = null;

  @visibleForTesting
  RssStore.test({this.databasePath});
  final String? databasePath;

  static final shared = RssStore._();

  final _connection = SqliteConnection();
  final _writes = SerialTaskQueue();
  Future<void> flushWrites() async => _writes.done;
  Future<T> _write<T>(Future<T> Function() action) => _writes.run(action);

  Future<String> databaseForBackup() async {
    await _writes.done;
    return (await _open()).path;
  }

  Future<List<RssSource>> listSources() async {
    final db = await _open();
    final rows = await db.query('rss_sources', orderBy: 'id ASC');
    return [for (final row in rows) RssSource.fromRow(row)];
  }

  Future<RssSource> upsertSource(RssSource source) => _write(() async {
    final db = await _open();
    if (source.id == 0) {
      final id = await db.insert('rss_sources', source.toRow());
      return source.copyWith(id: id);
    }
    await db.update(
      'rss_sources',
      source.toRow()..remove('id'),
      where: 'id = ?',
      whereArgs: [source.id],
    );
    return source;
  });

  Future<void> deleteSource(int sourceId) => _write(() async {
    final db = await _open();
    await db.delete('rss_items', where: 'source_id = ?', whereArgs: [sourceId]);
    await db.delete(
      'rss_bindings',
      where: 'source_id = ?',
      whereArgs: [sourceId],
    );
    await db.delete('rss_sources', where: 'id = ?', whereArgs: [sourceId]);
  });

  Future<List<RssBinding>> listBindings({int? subjectId, int? sourceId}) async {
    final db = await _open();
    final where = <String>[];
    final args = <Object?>[];
    if (subjectId != null) {
      where.add('subject_id = ?');
      args.add(subjectId);
    }
    if (sourceId != null) {
      where.add('source_id = ?');
      args.add(sourceId);
    }
    final rows = await db.query(
      'rss_bindings',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'id ASC',
    );
    return [for (final row in rows) RssBinding.fromRow(row)];
  }

  Future<RssBinding> upsertBinding(RssBinding binding) => _write(() async {
    final db = await _open();
    return db.transaction((txn) async {
      final RssBinding saved;
      if (binding.id == 0) {
        final id = await txn.insert('rss_bindings', binding.toRow());
        saved = binding.copyWith(id: id);
      } else {
        await txn.update(
          'rss_bindings',
          binding.toRow()..remove('id'),
          where: 'id = ?',
          whereArgs: [binding.id],
        );
        saved = binding;
      }
      // Only matching entries are retained locally, so changed rules need a
      // full feed even when the server's content has not changed.
      await txn.update(
        'rss_sources',
        {'etag': '', 'last_modified': '', 'last_fetch_at': null},
        where: 'id = ?',
        whereArgs: [binding.sourceId],
      );
      return saved;
    });
  });

  /// A response using old rules must not restore validators after a rule edit.
  Future<void> updateSourceAfterFetch(
    RssSource source, {
    required List<RssBinding> bindings,
  }) => _write(() async {
    final db = await _open();
    await db.transaction((txn) async {
      final current = (await txn.query(
        'rss_bindings',
        where: 'source_id = ? AND enabled = 1',
        whereArgs: [source.id],
        orderBy: 'id ASC',
      )).map(RssBinding.fromRow).toList();
      if (current.length != bindings.length ||
          !current.every(
            (rule) => bindings.any(
              (before) =>
                  before.id == rule.id &&
                  before.subjectId == rule.subjectId &&
                  before.subjectName == rule.subjectName &&
                  before.matchKeywords == rule.matchKeywords &&
                  before.excludeKeywords == rule.excludeKeywords &&
                  before.enabled == rule.enabled,
            ),
          )) {
        return;
      }
      await txn.update(
        'rss_sources',
        {
          'etag': source.etag,
          'last_modified': source.lastModified,
          'last_fetch_at': source.lastFetchAt?.millisecondsSinceEpoch,
          'last_error': source.lastError,
        },
        where: 'id = ?',
        whereArgs: [source.id],
      );
    });
  });

  Future<void> deleteBinding(int bindingId) => _write(() async {
    final db = await _open();
    await db.delete('rss_bindings', where: 'id = ?', whereArgs: [bindingId]);
  });

  Future<void> deleteBindingsForSubject(int subjectId) => _write(() async {
    final db = await _open();
    await db.delete(
      'rss_bindings',
      where: 'subject_id = ?',
      whereArgs: [subjectId],
    );
  });

  /// Insert matched items; ignore duplicates by (source_id, guid).
  Future<int> insertItemsIgnoreDup(
    List<RssItem> items, {
    bool validateBindings = false,
  }) => _write(() async {
    if (items.isEmpty) return 0;
    final db = await _open();
    return db.transaction((txn) async {
      // A network response can arrive after its source was deleted. Check
      // existence in the same transaction as insertion so it stays deleted.
      final sources = await txn.query('rss_sources', columns: ['id']);
      final sourceIds = {for (final row in sources) row['id']};
      final bindings = validateBindings
          ? (await txn.query(
              'rss_bindings',
              where: 'enabled = 1',
            )).map(RssBinding.fromRow).toList()
          : const <RssBinding>[];
      var added = 0;
      final batch = txn.batch();
      for (final item in items) {
        if (!sourceIds.contains(item.sourceId)) continue;
        if (validateBindings &&
            !bindings.any(
              (binding) =>
                  binding.sourceId == item.sourceId &&
                  binding.subjectId == item.subjectId &&
                  binding.matchesTitle(item.title),
            )) {
          continue;
        }
        batch.insert(
          'rss_items',
          item.toRow(),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      final results = await batch.commit(noResult: false);
      for (final result in results) {
        if (result is int && result > 0) added++;
      }
      return added;
    });
  });

  Future<List<RssItem>> listItems({
    int? subjectId,
    bool unreadOnly = false,
    int limit = 100,
  }) async {
    final db = await _open();
    final where = <String>[];
    final args = <Object?>[];
    if (subjectId != null) {
      where.add('subject_id = ?');
      args.add(subjectId);
    }
    if (unreadOnly) {
      where.add('read = 0');
    }
    final rows = await db.query(
      'rss_items',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'COALESCE(published_at, first_seen_at) DESC',
      limit: limit,
    );
    return [for (final row in rows) RssItem.fromRow(row)];
  }

  Future<Map<int, int>> unreadCountsBySubject() async {
    final db = await _open();
    final rows = await db.rawQuery('''
      SELECT subject_id, COUNT(*) AS c
      FROM rss_items
      WHERE read = 0
      GROUP BY subject_id
    ''');
    return {
      for (final row in rows)
        (row['subject_id'] as num).toInt(): (row['c'] as num).toInt(),
    };
  }

  Future<int> totalUnread() async {
    final db = await _open();
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM rss_items WHERE read = 0',
    );
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  Future<void> markRead(int itemId, {bool read = true}) => _write(() async {
    final db = await _open();
    await db.update(
      'rss_items',
      {'read': read ? 1 : 0},
      where: 'id = ?',
      whereArgs: [itemId],
    );
  });

  Future<void> markSubjectRead(int subjectId) => _write(() async {
    final db = await _open();
    await db.update(
      'rss_items',
      {'read': 1},
      where: 'subject_id = ?',
      whereArgs: [subjectId],
    );
  });

  Future<void> markAllRead() => _write(() async {
    final db = await _open();
    await db.update('rss_items', {'read': 1});
  });

  Future<void> close() async {
    await _writes.done;
    await _connection.close();
  }

  Future<Database> _open() => _connection.open(_createDatabase);

  Future<Database> _createDatabase() async {
    final factory = sqliteFactory;
    final root = await factory.getDatabasesPath();
    final resolvedPath =
        databasePath ?? path.join(root, 'mubangumi_rss.sqlite');
    return factory.openDatabase(
      resolvedPath,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: configurePersonalDatabase,
        onCreate: (database, _) async {
          await database.execute('''
          CREATE TABLE rss_sources (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            url TEXT NOT NULL UNIQUE,
            enabled INTEGER NOT NULL DEFAULT 1,
            etag TEXT NOT NULL DEFAULT '',
            last_modified TEXT NOT NULL DEFAULT '',
            last_fetch_at INTEGER,
            last_error TEXT NOT NULL DEFAULT '',
            created_at INTEGER NOT NULL
          )
        ''');
          await database.execute('''
          CREATE TABLE rss_bindings (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            source_id INTEGER NOT NULL,
            subject_id INTEGER NOT NULL,
            subject_name TEXT NOT NULL,
            season_key TEXT NOT NULL DEFAULT '',
            match_keywords TEXT NOT NULL DEFAULT '',
            exclude_keywords TEXT NOT NULL DEFAULT '',
            enabled INTEGER NOT NULL DEFAULT 1,
            created_at INTEGER NOT NULL,
            UNIQUE(source_id, subject_id)
          )
        ''');
          await database.execute('''
          CREATE TABLE rss_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            source_id INTEGER NOT NULL,
            subject_id INTEGER NOT NULL,
            guid TEXT NOT NULL,
            title TEXT NOT NULL,
            link TEXT NOT NULL,
            published_at INTEGER,
            read INTEGER NOT NULL DEFAULT 0,
            first_seen_at INTEGER NOT NULL,
            UNIQUE(source_id, guid)
          )
        ''');
          await database.execute(
            'CREATE INDEX idx_rss_items_subject ON rss_items(subject_id, read)',
          );
        },
      ),
    );
  }
}
