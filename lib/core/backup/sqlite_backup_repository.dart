import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

import '../storage/browsing_store.dart';
import '../storage/community_draft_store.dart';
import '../storage/pm_draft_store.dart';
import '../storage/rss_store.dart';
import '../storage/schedule_store.dart';
import '../storage/user_preference_store.dart';
import 'backup_archive.dart';
import 'backup_plan.dart';
import 'backup_repository.dart';

/// Identifiers and paths come from the application, never from an archive.
enum BackupDatabase { schedules, rss, people, browsing, community, pm }

BackupDatabase _databaseFor(BackupCategory category) => switch (category) {
  BackupCategory.schedules => BackupDatabase.schedules,
  BackupCategory.rss => BackupDatabase.rss,
  BackupCategory.people => BackupDatabase.people,
  BackupCategory.communityDrafts => BackupDatabase.community,
  BackupCategory.privateDrafts => BackupDatabase.pm,
  _ => BackupDatabase.browsing,
};

class SqliteBackupRepository implements BackupRepository {
  SqliteBackupRepository({
    required this.coordinatorPath,
    required this.databasePaths,
    this.afterCategoryWritten,
  });

  final String coordinatorPath;
  final Map<BackupDatabase, Future<String> Function()> databasePaths;

  /// Failure/crash injection for integration tests; absent in the application.
  final Future<void> Function(BackupCategory)? afterCategoryWritten;
  Future<void> _operations = Future.value();

  static Future<SqliteBackupRepository> shared() async {
    final factory = _factory();
    return SqliteBackupRepository(
      coordinatorPath: path.join(
        await factory.getDatabasesPath(),
        'mubangumi_backup_import.sqlite',
      ),
      databasePaths: {
        BackupDatabase.schedules: ScheduleStore.shared.databaseForBackup,
        BackupDatabase.rss: RssStore.shared.databaseForBackup,
        BackupDatabase.people: UserPreferenceStore.shared.databaseForBackup,
        BackupDatabase.browsing: BrowsingStore.shared.databaseForBackup,
        BackupDatabase.community: CommunityDraftStore.shared.databaseForBackup,
        BackupDatabase.pm: PmDraftStore.shared.databaseForBackup,
      },
    );
  }

  static DatabaseFactory _factory() {
    if (Platform.isWindows || Platform.isLinux) {
      ffi.sqfliteFfiInit();
      return ffi.databaseFactoryFfi;
    }
    return databaseFactory;
  }

  Future<T> _withDatabase<T>(
    Set<BackupCategory> categories,
    Future<T> Function(Database) action,
  ) {
    final next = _operations.then((_) async {
      if (categories.isEmpty) throw const BackupException('请选择数据类别');
      final files = <BackupDatabase, String>{};
      for (final name in categories.map(_databaseFor).toSet()) {
        files[name] = await databasePaths[name]!();
      }
      if (coordinatorPath == inMemoryDatabasePath ||
          files.values.any((file) => file == inMemoryDatabasePath) ||
          {
                ...files.values.map(path.canonicalize),
                path.canonicalize(coordinatorPath),
              }.length !=
              files.length + 1) {
        throw const BackupException('备份需要独立的持久数据库');
      }
      final db = await _factory().openDatabase(
        coordinatorPath,
        options: OpenDatabaseOptions(
          singleInstance: false,
          version: 1,
          onConfigure: (db) async {
            await db.rawQuery('PRAGMA journal_mode=DELETE');
            await db.execute('PRAGMA synchronous=FULL');
          },
          onCreate: (db, _) => db.execute('''CREATE TABLE import_log (
              id INTEGER PRIMARY KEY AUTOINCREMENT, owner_id INTEGER NOT NULL,
              checksum TEXT NOT NULL, mode TEXT NOT NULL, categories TEXT NOT NULL,
              imported_at INTEGER NOT NULL)'''),
        ),
      );
      try {
        for (final entry in files.entries) {
          await db.execute('ATTACH DATABASE ? AS ${entry.key.name}', [
            entry.value,
          ]);
        }
        // SQLite super-journals need a persistent main file and rollback journals
        // on every participant. Do not silently fall back to WAL or memory.
        for (final name in ['main', ...files.keys.map((key) => key.name)]) {
          final mode = await db.rawQuery('PRAGMA $name.journal_mode');
          if (mode.single.values.single.toString().toLowerCase() != 'delete') {
            throw const BackupException('数据库正使用不兼容的日志模式，请重启后重试');
          }
          await db.execute('PRAGMA $name.synchronous=FULL');
        }
        return await action(db);
      } finally {
        await db.close();
      }
    });
    _operations = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  void _checkOwner(BackupOwner owner, BackupArchive archive) {
    if (owner.id <= 0 || owner.id != archive.owner.id) {
      throw const BackupException('备份属于其他账号，请先切换到对应账号');
    }
  }

  @override
  Future<BackupArchive> export(
    BackupOwner owner,
    Set<BackupCategory> categories,
  ) => _withDatabase(
    categories,
    (db) => db.transaction(
      (txn) async => BackupArchive.create(
        owner: owner,
        data: await _read(txn, owner, categories),
      ),
      exclusive: false,
    ),
  );

  @override
  Future<BackupPreview> preview(
    BackupOwner owner,
    BackupArchive archive,
    Set<BackupCategory> categories,
    BackupImportMode mode,
  ) async {
    _checkOwner(owner, archive);
    return _withDatabase(
      categories,
      (db) => db.transaction(
        (txn) async => BackupPreview.create(
          archive,
          await _read(txn, owner, categories),
          categories,
          mode,
        ),
        exclusive: false,
      ),
    );
  }

  @override
  Future<bool> apply(
    BackupOwner owner,
    BackupPreview preview, {
    required bool Function() isCurrentOwner,
  }) async {
    _checkOwner(owner, preview.archive);
    void guard() {
      if (!isCurrentOwner()) throw const BackupException('账号已变化，请重新打开备份页面');
    }

    guard();
    return _withDatabase(
      preview.categories,
      (db) => db.transaction((txn) async {
        guard();
        final current = await _read(txn, owner, preview.categories);
        if (backupRowsDigest(current, preview.categories) !=
            preview.beforeDigest) {
          throw const BackupException('本地数据在预览后发生了变化，请重新预览');
        }
        final result = mergeBackupRows(
          current,
          preview.archive.data,
          preview.categories,
          preview.mode,
        );
        if (backupRowsDigest(result, preview.categories) !=
            preview.resultDigest) {
          throw const BackupException('导入预览已失效，请重新预览');
        }
        // Validate the combined size and cross-record constraints before any write.
        BackupArchive.create(owner: owner, data: result);
        if (!preview.hasChanges) return false;
        await _insert(txn, 'main.import_log', {
          'owner_id': owner.id,
          'checksum': preview.archive.checksum,
          'mode': preview.mode.name,
          'categories': jsonEncode(
            preview.categories.map((c) => c.name).toList()..sort(),
          ),
          'imported_at': DateTime.now().millisecondsSinceEpoch,
        });
        for (final category in BackupCategory.values.where(
          preview.categories.contains,
        )) {
          guard();
          if (backupRowsDigest(current, {category}) ==
              backupRowsDigest(result, {category})) {
            continue;
          }
          await _write(
            txn,
            owner,
            category,
            current[category]!,
            result[category]!,
          );
          await afterCategoryWritten?.call(category);
        }
        final applied = await _read(txn, owner, preview.categories);
        if (backupRowsDigest(applied, preview.categories) !=
            preview.resultDigest) {
          throw const BackupException('导入核对失败，已回滚本次修改');
        }
        guard();
        return true;
      }),
    );
  }

  Future<BackupRows> _read(
    DatabaseExecutor db,
    BackupOwner owner,
    Set<BackupCategory> categories,
  ) async {
    final data = <BackupCategory, List<Map<String, dynamic>>>{};
    final account = owner.username.trim().toLowerCase();
    for (final category in categories) {
      final rows = <Map<String, dynamic>>[];
      switch (category) {
        case BackupCategory.schedules:
          for (final row in await db.rawQuery(
            'SELECT season_key, payload FROM schedules.season_schedule ORDER BY season_key',
          )) {
            final payload =
                jsonDecode(row['payload'] as String) as Map<String, dynamic>;
            // Pre-2.1 schedules had no reminder fields. Normalize only those
            // known omissions; all other malformed or unknown fields still fail.
            for (final item
                in (payload['items'] as List).cast<Map<String, dynamic>>()) {
              item.putIfAbsent('reminderEnabled', () => false);
              item.putIfAbsent('reminderHour', () => 20);
              item.putIfAbsent('reminderMinute', () => 0);
            }
            if (backupRowKey(category, payload) != row['season_key']) {
              throw const BackupException('本地新番表的季度信息不一致');
            }
            rows.add(payload);
          }
        case BackupCategory.rss:
          final sources = await db.rawQuery(
            'SELECT * FROM rss.rss_sources ORDER BY id',
          );
          final urls = {for (final row in sources) row['id']: row['url']};
          for (var i = 0; i < sources.length; i++) {
            final row = sources[i];
            rows.add({
              'kind': 'source',
              'url': row['url'],
              'name': row['name'],
              'enabled': row['enabled'] == 1,
              'created_at': row['created_at'],
              'position': i,
            });
          }
          final bindings = await db.rawQuery(
            'SELECT * FROM rss.rss_bindings ORDER BY id',
          );
          for (var i = 0; i < bindings.length; i++) {
            final row = bindings[i];
            rows.add({
              'kind': 'binding',
              'source_url': urls[row['source_id']],
              for (final key in _bindingFields) key: row[key],
              'enabled': row['enabled'] == 1,
              'position': i,
            });
          }
        case BackupCategory.people:
          for (final row in await db.rawQuery(
            'SELECT * FROM people.user_preference',
          )) {
            rows.add({...row, 'blocked': row['blocked'] == 1});
          }
        case BackupCategory.pins:
          final pins = await db.rawQuery(
            'SELECT payload FROM browsing.home_pins WHERE owner_id = ?',
            [owner.id],
          );
          if (pins.isNotEmpty) {
            final ids = jsonDecode(pins.single['payload'] as String) as List;
            for (var i = 0; i < ids.length; i++) {
              rows.add({'subject_id': ids[i], 'position': i});
            }
          }
        case BackupCategory.browsing:
          final library = await db.rawQuery(
            'SELECT payload FROM browsing.library_preferences WHERE account = ?',
            [account],
          );
          if (library.isNotEmpty) {
            rows.add({
              'kind': 'library',
              ...jsonDecode(library.single['payload'] as String)
                  as Map<String, dynamic>,
            });
          }
          final view = await db.rawQuery(
            'SELECT view FROM browsing.schedule_view WHERE owner_id = ?',
            [owner.id],
          );
          if (view.isNotEmpty) {
            rows.add({'kind': 'schedule_view', ...view.single});
          }
          final searches = await db.rawQuery(
            'SELECT keyword, target, subject_type FROM browsing.recent_search WHERE account = ? ORDER BY id DESC LIMIT 12',
            [account],
          );
          for (var i = 0; i < searches.length; i++) {
            rows.add({'kind': 'search', ...searches[i], 'position': i});
          }
        case BackupCategory.recommendations:
          rows.addAll(
            await db.rawQuery(
              'SELECT subject_id, title, subject_type, hidden_at FROM browsing.recommendation_hidden WHERE owner_id = ?',
              [owner.id],
            ),
          );
        case BackupCategory.communityDrafts:
          for (final row in await _communityRows(db, account)) {
            if (row['deleted'] == 1) continue;
            rows.add({
              'target': (jsonDecode(row['draft_key'] as String) as List)
                  .skip(1)
                  .toList(),
              'title': row['title'],
              'content': row['content'],
              'updated_at': row['updated_at'],
            });
          }
        case BackupCategory.privateDrafts:
          final drafts = await db.rawQuery(
            'SELECT * FROM pm.pm_draft WHERE owner_id = ? AND deleted = 0 ORDER BY change_id DESC',
            [owner.id],
          );
          for (var i = 0; i < drafts.length; i++) {
            final row = drafts[i];
            rows.add({
              'id': row['draft_id'],
              'kind': row['kind'],
              ...jsonDecode(row['payload'] as String) as Map<String, dynamic>,
              'updated_at': row['updated_at'],
              'position': i,
            });
          }
      }
      data[category] = rows;
    }
    // Never silently discard corrupt personal data during an export or preview.
    return BackupArchive.create(owner: owner, data: data).data;
  }

  static const _bindingFields = [
    'subject_id',
    'subject_name',
    'season_key',
    'match_keywords',
    'exclude_keywords',
    'created_at',
  ];

  Future<List<Map<String, Object?>>> _communityRows(
    DatabaseExecutor db,
    String account,
  ) {
    final encoded = jsonEncode([account]);
    final prefix = '${encoded.substring(0, encoded.length - 1)},';
    return db.rawQuery(
      'SELECT * FROM community.draft WHERE substr(draft_key, 1, ?) = ?',
      [prefix.length, prefix],
    );
  }

  Future<int> _insert(
    DatabaseExecutor db,
    String table,
    Map<String, Object?> values,
  ) => db.rawInsert(
    'INSERT OR REPLACE INTO $table (${values.keys.map((key) => '"$key"').join(',')}) VALUES (${List.filled(values.length, '?').join(',')})',
    values.values.toList(),
  );

  Future<void> _write(
    DatabaseExecutor db,
    BackupOwner owner,
    BackupCategory category,
    List<Map<String, dynamic>> before,
    List<Map<String, dynamic>> rows,
  ) async {
    final account = owner.username.trim().toLowerCase();
    switch (category) {
      case BackupCategory.schedules:
        await db.execute('DELETE FROM schedules.season_schedule');
        for (final row in rows) {
          await _insert(db, 'schedules.season_schedule', {
            'season_key': backupRowKey(category, row),
            'payload': jsonEncode(row),
            'updated_at': DateTime.now().millisecondsSinceEpoch,
          });
        }
      case BackupCategory.rss:
        await _writeRss(db, before, rows);
      case BackupCategory.people:
        await db.execute('DELETE FROM people.user_preference');
        for (final row in rows) {
          await _insert(db, 'people.user_preference', {
            ...row,
            'username': backupRowKey(category, row),
            'blocked': row['blocked'] == true ? 1 : 0,
          });
        }
      case BackupCategory.pins:
        final ordered = _ordered(rows);
        await _insert(db, 'browsing.home_pins', {
          'owner_id': owner.id,
          'payload': jsonEncode(
            ordered.map((row) => row['subject_id']).toList(),
          ),
        });
      case BackupCategory.browsing:
        await db.execute(
          'DELETE FROM browsing.library_preferences WHERE account = ?',
          [account],
        );
        await db.execute(
          'DELETE FROM browsing.recent_search WHERE account = ?',
          [account],
        );
        await db.execute(
          'DELETE FROM browsing.schedule_view WHERE owner_id = ?',
          [owner.id],
        );
        for (final row in rows.where((row) => row['kind'] != 'search')) {
          if (row['kind'] == 'library') {
            await _insert(db, 'browsing.library_preferences', {
              'account': account,
              'payload': jsonEncode({...row}..remove('kind')),
            });
          } else {
            await _insert(db, 'browsing.schedule_view', {
              'owner_id': owner.id,
              'view': row['view'],
            });
          }
        }
        for (final row in _ordered(
          rows.where((row) => row['kind'] == 'search'),
        ).reversed) {
          await _insert(db, 'browsing.recent_search', {
            'account': account,
            'search_key': jsonEncode([
              row['target'],
              row['target'] == 'subject' ? row['subject_type'] : 0,
              (row['keyword'] as String).trim().toLowerCase(),
            ]),
            'keyword': row['keyword'],
            'target': row['target'],
            'subject_type': row['subject_type'],
          });
        }
      case BackupCategory.recommendations:
        await db.execute(
          'DELETE FROM browsing.recommendation_hidden WHERE owner_id = ?',
          [owner.id],
        );
        final chronological = rows.toList()
          ..sort(
            (a, b) => (a['hidden_at'] as int).compareTo(b['hidden_at'] as int),
          );
        for (final row in chronological) {
          await _insert(db, 'browsing.recommendation_hidden', {
            'owner_id': owner.id,
            ...row,
          });
        }
      case BackupCategory.communityDrafts:
        final old = {
          for (final row in await _communityRows(db, account))
            row['draft_key']: row,
        };
        final targets = {
          for (final row in rows)
            communityDraftKey(account, (row['target'] as List).cast<Object>())!:
                row,
        };
        for (final entry in old.entries) {
          if (entry.value['deleted'] == 1 || targets.containsKey(entry.key)) {
            continue;
          }
          await _insert(db, 'community.draft', {
            'draft_key': entry.key,
            'title': '',
            'content': '',
            'deleted': 1,
            'revision': (entry.value['revision'] as int) + 1,
            'updated_at': DateTime.now().millisecondsSinceEpoch,
          });
        }
        for (final entry in targets.entries) {
          final previous = old[entry.key];
          final row = entry.value;
          if (previous != null &&
              previous['deleted'] == 0 &&
              [
                'title',
                'content',
                'updated_at',
              ].every((key) => previous[key] == row[key])) {
            continue;
          }
          await _insert(db, 'community.draft', {
            'draft_key': entry.key,
            'title': row['title'],
            'content': row['content'],
            'updated_at': row['updated_at'],
            'deleted': 0,
            'revision': ((previous?['revision'] as int?) ?? 0) + 1,
          });
        }
      case BackupCategory.privateDrafts:
        final old = {
          for (final row in await db.rawQuery(
            'SELECT * FROM pm.pm_draft WHERE owner_id = ?',
            [owner.id],
          ))
            row['draft_id']: row,
        };
        final active = {for (final row in rows) row['id']};
        for (final entry in old.entries) {
          if (entry.value['deleted'] == 1 || active.contains(entry.key)) {
            continue;
          }
          await _insert(db, 'pm.pm_draft', {
            'owner_id': owner.id,
            'draft_id': entry.key,
            'kind': '',
            'recipient_key': '',
            'payload': '{}',
            'deleted': 1,
            'revision': (entry.value['revision'] as int) + 1,
            'updated_at': DateTime.now().millisecondsSinceEpoch,
          });
        }
        for (final row in _ordered(rows).reversed) {
          final previous = old[row['id']];
          final payload = {
            for (final key in [
              'recipient',
              'title',
              'body',
              'conversation_id',
              'thread_id',
            ])
              key: row[key],
          };
          final unchanged =
              previous != null &&
              previous['deleted'] == 0 &&
              previous['kind'] == row['kind'] &&
              previous['updated_at'] == row['updated_at'] &&
              canonicalBackupJson(jsonDecode(previous['payload'] as String)) ==
                  canonicalBackupJson(payload);
          await _insert(db, 'pm.pm_draft', {
            'owner_id': owner.id,
            'draft_id': row['id'],
            'kind': row['kind'],
            'recipient_key': (row['recipient'] as String).trim().toLowerCase(),
            'payload': jsonEncode(payload),
            'updated_at': row['updated_at'],
            'deleted': 0,
            'revision':
                ((previous?['revision'] as int?) ?? 0) + (unchanged ? 0 : 1),
          });
        }
    }
  }

  List<Map<String, dynamic>> _ordered(Iterable<Map<String, dynamic>> rows) =>
      rows.toList()..sort(
        (a, b) => (a['position'] as int).compareTo(b['position'] as int),
      );

  Future<void> _writeRss(
    DatabaseExecutor db,
    List<Map<String, dynamic>> before,
    List<Map<String, dynamic>> rows,
  ) async {
    final old = {
      for (final row in await db.rawQuery('SELECT * FROM rss.rss_sources'))
        row['url']: row,
    };
    Map<Object?, String> ruleSignatures(List<Map<String, dynamic>> records) {
      final grouped = <Object?, List<Map<String, dynamic>>>{};
      for (final row in _ordered(
        records.where((row) => row['kind'] == 'binding'),
      )) {
        (grouped[row['source_url']] ??= []).add(
          {...row}
            ..remove('position')
            ..remove('created_at'),
        );
      }
      return {
        for (final entry in grouped.entries)
          entry.key: canonicalBackupJson(entry.value),
      };
    }

    final oldRules = ruleSignatures(before);
    final newRules = ruleSignatures(rows);
    await db.execute('DELETE FROM rss.rss_bindings');
    await db.execute('DELETE FROM rss.rss_sources');
    final newIds = <Object?, int>{};
    for (final row in _ordered(rows.where((row) => row['kind'] == 'source'))) {
      final previous = old[row['url']];
      final keepCache =
          previous != null &&
          previous['enabled'] == (row['enabled'] == true ? 1 : 0) &&
          oldRules[row['url']] == newRules[row['url']];
      final id = await _insert(db, 'rss.rss_sources', {
        'name': row['name'],
        'url': row['url'],
        'enabled': row['enabled'] == true ? 1 : 0,
        'created_at': row['created_at'],
        if (keepCache)
          for (final key in [
            'etag',
            'last_modified',
            'last_fetch_at',
            'last_error',
          ])
            key: previous[key],
      });
      newIds[row['url']] = id;
      if (previous != null) {
        if (keepCache) {
          await db.execute(
            'UPDATE rss.rss_items SET source_id = ? WHERE source_id = ?',
            [id, previous['id']],
          );
        } else {
          await db.execute('DELETE FROM rss.rss_items WHERE source_id = ?', [
            previous['id'],
          ]);
        }
      }
    }
    for (final entry in old.entries.where(
      (entry) => !newIds.containsKey(entry.key),
    )) {
      await db.execute('DELETE FROM rss.rss_items WHERE source_id = ?', [
        entry.value['id'],
      ]);
    }
    for (final row in _ordered(rows.where((row) => row['kind'] == 'binding'))) {
      await _insert(db, 'rss.rss_bindings', {
        'source_id': newIds[row['source_url']],
        for (final key in _bindingFields) key: row[key],
        'enabled': row['enabled'] == true ? 1 : 0,
      });
    }
  }
}
