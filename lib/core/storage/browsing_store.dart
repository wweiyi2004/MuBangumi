import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

import '../../models/bangumi_models.dart';

class RecentSearch {
  const RecentSearch({
    required this.keyword,
    this.target = 'subject',
    this.subjectType = SubjectType.anime,
  });
  final String keyword;
  final String target;
  final SubjectType subjectType;
  String get key => jsonEncode([
    target,
    target == 'subject' ? subjectType.value : 0,
    keyword.trim().toLowerCase(),
  ]);
  String get label =>
      '${switch (target) {
        'character' => '角色',
        'person' => '人物',
        _ => subjectType.label,
      }} · ${keyword.trim()}';
}

abstract class BrowsingRepository {
  Future<Map<String, dynamic>?> readLibrary(String account);
  Future<void> saveLibrary(String account, Map<String, dynamic> settings);
  Future<List<RecentSearch>> readSearches(String account);
  Future<void> rememberSearch(String account, RecentSearch search);
  Future<void> clearSearches(String account);
}

final browsingRepositoryProvider = Provider<BrowsingRepository>(
  (ref) => BrowsingStore.shared,
);
final recentSearchesProvider = FutureProvider.autoDispose
    .family<List<RecentSearch>, String>(
      (ref, account) =>
          ref.watch(browsingRepositoryProvider).readSearches(account),
    );

/// Durable browsing preferences are separate from the disposable cache.
class BrowsingStore implements BrowsingRepository {
  BrowsingStore({this.databasePath});
  static final shared = BrowsingStore();
  static const historyLimit = 12;
  final String? databasePath;
  Future<Database>? _database;
  Future<void> _writes = Future<void>.value();
  String _account(String value) => value.trim().toLowerCase();

  Future<void> _write(Future<void> Function(Database db) action) {
    final future = _writes.then((_) async => action(await _open()));
    _writes = future.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return future;
  }

  @override
  Future<Map<String, dynamic>?> readLibrary(String account) async {
    if (_account(account).isEmpty) return null;
    await _writes;
    final rows = await (await _open()).query(
      'library_preferences',
      where: 'account = ?',
      whereArgs: [_account(account)],
    );
    if (rows.isEmpty) return null;
    try {
      final data = jsonDecode(rows.single['payload'] as String);
      return data is Map<String, dynamic> ? data : null;
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> saveLibrary(String account, Map<String, dynamic> settings) {
    final key = _account(account);
    if (key.isEmpty) return Future.value();
    final payload = jsonEncode(settings);
    return _write((db) async {
      await db.insert('library_preferences', {
        'account': key,
        'payload': payload,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  @override
  Future<List<RecentSearch>> readSearches(String account) async {
    if (_account(account).isEmpty) return const [];
    await _writes;
    final rows = await (await _open()).query(
      'recent_search',
      where: 'account = ?',
      whereArgs: [_account(account)],
      orderBy: 'id DESC',
      limit: historyLimit,
    );
    return [
      for (final row in rows)
        if (const ['subject', 'character', 'person'].contains(row['target']) &&
            (row['keyword'] as String).trim().isNotEmpty)
          RecentSearch(
            keyword: row['keyword'] as String,
            target: row['target'] as String,
            subjectType: SubjectType.fromValue(row['subject_type'] as int),
          ),
    ];
  }

  @override
  Future<void> rememberSearch(String account, RecentSearch search) {
    final key = _account(account);
    final keyword = search.keyword.trim();
    if (key.isEmpty ||
        keyword.isEmpty ||
        !const ['subject', 'character', 'person'].contains(search.target)) {
      return Future.value();
    }
    return _write(
      (db) => db.transaction((transaction) async {
        await transaction.insert('recent_search', {
          'account': key,
          'search_key': search.key,
          'keyword': keyword,
          'target': search.target,
          'subject_type': search.subjectType.value,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        await transaction.rawDelete(
          '''DELETE FROM recent_search WHERE account = ? AND id NOT IN
        (SELECT id FROM recent_search WHERE account = ? ORDER BY id DESC LIMIT ?)''',
          [key, key, historyLimit],
        );
      }),
    );
  }

  @override
  Future<void> clearSearches(String account) {
    final key = _account(account);
    if (key.isEmpty) return Future.value();
    return _write((db) async {
      await db.delete('recent_search', where: 'account = ?', whereArgs: [key]);
    });
  }

  Future<Database> _open() =>
      _database ??= _create().catchError((Object error) {
        _database = null;
        throw error;
      });

  Future<Database> _create() async {
    final DatabaseFactory factory;
    if (Platform.isWindows || Platform.isLinux) {
      ffi.sqfliteFfiInit();
      factory = ffi.databaseFactoryFfi;
    } else {
      factory = databaseFactory;
    }
    return factory.openDatabase(
      databasePath ??
          path.join(
            await factory.getDatabasesPath(),
            'mubangumi_browsing.sqlite',
          ),
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE library_preferences (account TEXT PRIMARY KEY NOT NULL, payload TEXT NOT NULL)',
          );
          await db.execute(
            '''CREATE TABLE recent_search (id INTEGER PRIMARY KEY AUTOINCREMENT,
          account TEXT NOT NULL, search_key TEXT NOT NULL, keyword TEXT NOT NULL,
          target TEXT NOT NULL, subject_type INTEGER NOT NULL, UNIQUE(account, search_key))''',
          );
        },
      ),
    );
  }

  Future<void> close() async {
    await _writes;
    await (await _database)?.close();
    _database = null;
  }
}
