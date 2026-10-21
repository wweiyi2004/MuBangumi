import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'serial_task_queue.dart';
import 'sqlite_support.dart';

class LocalUserPreference {
  const LocalUserPreference({
    required this.username,
    this.note = '',
    this.blocked = false,
    this.updatedAt,
  });

  final String username;
  final String note;
  final bool blocked;
  final DateTime? updatedAt;

  String get key => username.trim().toLowerCase();

  LocalUserPreference copyWith({String? note, bool? blocked}) =>
      LocalUserPreference(
        username: username,
        note: note ?? this.note,
        blocked: blocked ?? this.blocked,
        updatedAt: DateTime.now(),
      );
}

abstract class UserPreferenceRepository {
  Future<List<LocalUserPreference>> loadAll();
  Future<void> save(LocalUserPreference preference);
}

class UserPreferenceStore implements UserPreferenceRepository {
  UserPreferenceStore._() : databasePath = null;
  UserPreferenceStore.test({this.databasePath});
  final String? databasePath;

  static final shared = UserPreferenceStore._();

  final _connection = SqliteConnection();
  final _writes = SerialTaskQueue();
  Future<T> _write<T>(Future<T> Function() action) => _writes.run(action);

  Future<String> databaseForBackup() async {
    await _writes.done;
    return (await _open()).path;
  }

  @override
  Future<List<LocalUserPreference>> loadAll() async {
    final database = await _open();
    final rows = await database.query(
      'user_preference',
      orderBy: 'updated_at DESC',
    );
    return [
      for (final row in rows)
        LocalUserPreference(
          username: row['username']?.toString() ?? '',
          note: row['note']?.toString() ?? '',
          blocked: row['blocked'] == 1,
          updatedAt: DateTime.fromMillisecondsSinceEpoch(
            (row['updated_at'] as num?)?.toInt() ?? 0,
          ),
        ),
    ];
  }

  @override
  Future<void> save(LocalUserPreference preference) => _write(() async {
    final key = preference.key;
    if (key.isEmpty) return;
    final database = await _open();
    await database.insert('user_preference', {
      'username': key,
      'note': preference.note.trim(),
      'blocked': preference.blocked ? 1 : 0,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  });

  Future<void> close() async {
    await _writes.done;
    await _connection.close();
  }

  Future<Database> _open() => _connection.open(_createDatabase);

  Future<Database> _createDatabase() async {
    final factory = sqliteFactory;
    final root = await factory.getDatabasesPath();
    return factory.openDatabase(
      databasePath ?? path.join(root, 'mubangumi_user_preferences.sqlite'),
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: configurePersonalDatabase,
        onCreate: (database, _) async {
          await database.execute('''
          CREATE TABLE user_preference (
            username TEXT PRIMARY KEY NOT NULL,
            note TEXT NOT NULL DEFAULT '',
            blocked INTEGER NOT NULL DEFAULT 0,
            updated_at INTEGER NOT NULL
          )
        ''');
        },
      ),
    );
  }
}
