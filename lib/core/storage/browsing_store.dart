import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

import '../../models/bangumi_models.dart';
import '../../models/schedule_view.dart';
import '../../models/recommendation_feedback.dart';
import '../../models/topic_reading_position.dart';

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

abstract class HomePinsRepository {
  Future<List<int>> readHomePins(int ownerId);
  Future<void> saveHomePins(int ownerId, List<int> ids);
}

abstract class ScheduleViewRepository {
  Future<ScheduleView?> readScheduleView(int ownerId);
  Future<void> saveScheduleView(int ownerId, ScheduleView view);
}

abstract class RecommendationFeedbackRepository {
  Future<List<HiddenRecommendation>> readHiddenRecommendations(int ownerId);
  Future<void> hideRecommendation(int ownerId, HiddenRecommendation item);
  Future<void> restoreRecommendation(int ownerId, int subjectId);
}

final recommendationFeedbackRepositoryProvider =
    Provider<RecommendationFeedbackRepository>((ref) => BrowsingStore.shared);

final scheduleViewRepositoryProvider = Provider<ScheduleViewRepository>(
  (ref) => BrowsingStore.shared,
);

final homePinsRepositoryProvider = Provider<HomePinsRepository>(
  (ref) => BrowsingStore.shared,
);

final topicReadingRepositoryProvider = Provider<TopicReadingRepository>(
  (ref) => BrowsingStore.shared,
);

final browsingRepositoryProvider = Provider<BrowsingRepository>(
  (ref) => BrowsingStore.shared,
);
final recentSearchesProvider = FutureProvider.autoDispose
    .family<List<RecentSearch>, String>(
      (ref, account) =>
          ref.watch(browsingRepositoryProvider).readSearches(account),
    );

/// Durable browsing preferences are separate from the disposable cache.
class BrowsingStore
    implements
        BrowsingRepository,
        HomePinsRepository,
        ScheduleViewRepository,
        TopicReadingRepository,
        RecommendationFeedbackRepository {
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

  @override
  Future<List<int>> readHomePins(int ownerId) async {
    if (ownerId <= 0) return const [];
    await _writes;
    final rows = await (await _open()).query(
      'home_pins',
      where: 'owner_id = ?',
      whereArgs: [ownerId],
    );
    if (rows.isEmpty) return const [];
    final data = jsonDecode(rows.single['payload'] as String);
    if (data is! List || data.any((id) => id is! int || id <= 0)) {
      throw const FormatException('Invalid home pins');
    }
    return data.cast<int>().toSet().toList();
  }

  @override
  Future<void> saveHomePins(int ownerId, List<int> ids) {
    if (ownerId <= 0 || ids.any((id) => id <= 0)) {
      throw ArgumentError('Invalid owner or subject');
    }
    final payload = jsonEncode(ids.toSet().toList());
    return _write((db) async {
      await db.insert('home_pins', {
        'owner_id': ownerId,
        'payload': payload,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<void> _createHomePins(Database db) => db.execute(
    'CREATE TABLE home_pins (owner_id INTEGER PRIMARY KEY NOT NULL, payload TEXT NOT NULL)',
  );

  @override
  Future<ScheduleView?> readScheduleView(int ownerId) async {
    await _writes;
    final rows = await (await _open()).query(
      'schedule_view',
      where: 'owner_id = ?',
      whereArgs: [ownerId],
    );
    if (rows.isEmpty) return null;
    return ScheduleView.values
        .where((mode) => mode.name == rows.single['view'])
        .firstOrNull;
  }

  @override
  Future<void> saveScheduleView(int ownerId, ScheduleView view) =>
      _write((db) async {
        await db.insert('schedule_view', {
          'owner_id': ownerId,
          'view': view.name,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      });
  Future<void> _createScheduleView(Database db) => db.execute(
    'CREATE TABLE schedule_view (owner_id INTEGER PRIMARY KEY NOT NULL, view TEXT NOT NULL)',
  );

  @override
  Future<List<HiddenRecommendation>> readHiddenRecommendations(
    int ownerId,
  ) async {
    await _writes;
    final rows = await (await _open()).query(
      'recommendation_hidden',
      where: 'owner_id = ?',
      whereArgs: [ownerId],
      orderBy: 'id DESC',
    );
    return [
      for (final row in rows)
        HiddenRecommendation(
          subjectId: row['subject_id'] as int,
          title: row['title'] as String,
          type: SubjectType.fromValue(row['subject_type'] as int),
          hiddenAt: DateTime.fromMillisecondsSinceEpoch(
            row['hidden_at'] as int,
          ),
        ),
    ];
  }

  @override
  Future<void> hideRecommendation(int ownerId, HiddenRecommendation item) {
    if (ownerId < 0 || item.subjectId <= 0) {
      throw ArgumentError('Invalid feedback owner or subject');
    }
    return _write((db) async {
      await db.insert('recommendation_hidden', {
        'owner_id': ownerId,
        'subject_id': item.subjectId,
        'title': item.title,
        'subject_type': item.type.value,
        'hidden_at': item.hiddenAt.millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  @override
  Future<void> restoreRecommendation(int ownerId, int subjectId) =>
      _write((db) async {
        await db.delete(
          'recommendation_hidden',
          where: 'owner_id = ? AND subject_id = ?',
          whereArgs: [ownerId, subjectId],
        );
      });
  Future<void> _createRecommendationFeedback(Database db) => db.execute(
    '''CREATE TABLE recommendation_hidden (
    id INTEGER PRIMARY KEY AUTOINCREMENT, owner_id INTEGER NOT NULL, subject_id INTEGER NOT NULL,
    title TEXT NOT NULL, subject_type INTEGER NOT NULL, hidden_at INTEGER NOT NULL, UNIQUE(owner_id, subject_id))''',
  );

  Future<String> databaseForBackup() async {
    await _writes;
    return (await _open()).path;
  }

  @override
  Future<TopicReadingPosition?> readTopicPosition(
    String account,
    String topic,
  ) async {
    if (_account(account).isEmpty) return null;
    await _writes;
    final rows = await (await _open()).query(
      'topic_reading',
      where: 'account = ? AND topic = ?',
      whereArgs: [_account(account), topic],
    );
    if (rows.isEmpty) return null;
    return TopicReadingPosition(
      postId: rows.single['post_id'] as String,
      index: rows.single['post_index'] as int,
    );
  }

  @override
  Future<void> saveTopicPosition(
    String account,
    String topic,
    TopicReadingPosition position,
  ) {
    if (_account(account).isEmpty ||
        topic.isEmpty ||
        position.postId.isEmpty ||
        position.index < 0) {
      return Future.value();
    }
    return _write((db) async {
      await db.transaction((txn) async {
        await txn.insert('topic_reading', {
          'account': _account(account),
          'topic': topic,
          'post_id': position.postId,
          'post_index': position.index,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        await txn.rawDelete(
          'DELETE FROM topic_reading WHERE account = ? AND topic NOT IN '
          '(SELECT topic FROM topic_reading WHERE account = ? ORDER BY updated_at DESC LIMIT 200)',
          [_account(account), _account(account)],
        );
      });
    });
  }

  Future<void> _createTopicReading(Database db) => db.execute(
    '''CREATE TABLE topic_reading (
    account TEXT NOT NULL, topic TEXT NOT NULL, post_id TEXT NOT NULL,
    post_index INTEGER NOT NULL, updated_at INTEGER NOT NULL, PRIMARY KEY(account, topic))''',
  );

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
        onConfigure: (db) async {
          await db.rawQuery('PRAGMA journal_mode=DELETE');
        },
        version: 5,
        onUpgrade: (db, oldVersion, _) async {
          if (oldVersion < 2) await _createHomePins(db);
          if (oldVersion < 3) await _createScheduleView(db);
          if (oldVersion < 4) await _createRecommendationFeedback(db);
          if (oldVersion < 5) await _createTopicReading(db);
        },
        onCreate: (db, _) async {
          await _createTopicReading(db);
          await _createHomePins(db);
          await _createScheduleView(db);
          await _createRecommendationFeedback(db);
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
