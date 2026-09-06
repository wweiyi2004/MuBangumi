import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

typedef CommunityDraftData = ({String title, String content});

/// JSON encoding prevents collisions between account and target identifiers.
String? communityDraftKey(String? username, List<Object> target) {
  final account = username?.trim().toLowerCase() ?? '';
  return account.isEmpty ? null : jsonEncode([account, ...target]);
}

abstract class CommunityDraftRepository {
  Future<CommunityDraftData?> load(String key);
  Future<void> save(String key, CommunityDraftData draft);
}

class CommunityDraftStore implements CommunityDraftRepository {
  CommunityDraftStore({this.databasePath});

  static final shared = CommunityDraftStore();
  final String? databasePath;
  Future<Database>? _database;
  Future<void> _writes = Future.value();

  @override
  Future<CommunityDraftData?> load(String key) async {
    await _writes;
    final db = await _open();
    final rows = await db.query(
      'draft',
      where: 'draft_key = ?',
      whereArgs: [key],
    );
    if (rows.isEmpty) return null;
    return (
      title: rows.single['title'] as String,
      content: rows.single['content'] as String,
    );
  }

  @override
  Future<void> save(String key, CommunityDraftData draft) {
    // Snapshot values are immutable. A pending autosave cannot overtake the
    // deletion after sending or a newer editor's save.
    final future = _writes.then((_) async {
      final db = await _open();
      if (draft.title.isEmpty && draft.content.isEmpty) {
        await db.delete('draft', where: 'draft_key = ?', whereArgs: [key]);
      } else {
        await db.insert('draft', {
          'draft_key': key,
          'title': draft.title,
          'content': draft.content,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
    _writes = future.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return future;
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
            'mubangumi_community_drafts.sqlite',
          ),
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) => db.execute('''
          CREATE TABLE draft (
            draft_key TEXT PRIMARY KEY NOT NULL,
            title TEXT NOT NULL,
            content TEXT NOT NULL,
            updated_at INTEGER NOT NULL
          )
        '''),
      ),
    );
  }

  Future<void> close() async {
    await _writes;
    await (await _database)?.close();
    _database = null;
  }
}
