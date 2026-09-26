import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:banjian_server/banjian_server.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

String _encodeRoomCache(Json value) => jsonEncode(value);
Json _decodeRoomCache(String value) =>
    RoomSnapshot.fromJson(jsonDecode(value) as Json).toJson();

abstract class ParticipationStorage {
  Future<Json?> read();
  Future<void> write(Json value);
}

abstract interface class ArchivedParticipationStorage {
  Future<Json?> readRoom(String identity);
}

abstract interface class RoomSecretVault {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class PlatformRoomSecretVault implements RoomSecretVault {
  const PlatformRoomSecretVault();
  static const _storage = FlutterSecureStorage();
  @override
  Future<String?> read(String key) => _storage.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Credentials stay in the platform vault. Journal writes are transactional;
/// snapshots are independently evictable. Archived journals are loaded on demand
/// and never deleted merely to meet the optional snapshot-cache budget.
class RoomLocalStorage
    implements ParticipationStorage, ArchivedParticipationStorage {
  RoomLocalStorage({
    this.key = 'banjian_participation_v1',
    RoomSecretVault? vault,
    this._database,
    this._databasePath,
    this._databaseOpener,
  }) : vault = vault ?? const PlatformRoomSecretVault();
  final String key;
  final RoomSecretVault vault;
  final Future<String> Function()? _databasePath;
  final Future<Database> Function(String, OpenDatabaseOptions)? _databaseOpener;
  Database? _database;
  Future<Database>? _opening;
  Future<void> _tail = Future.value();
  bool _migrated = false;
  int? _knownRevision;
  static const snapshotBudget = 16 * 1024 * 1024;
  static const snapshotCount = 8;
  final _credentials = <String, String>{};

  Future<T> _serial<T>(Future<T> Function() action) {
    final next = _tail.then((_) => action());
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<Database> _open() async {
    if (_database != null) {
      await _schema(_database!);
      return _database!;
    }
    if (_opening != null) return _opening!;
    final opening = () async {
      final factory = Platform.isWindows || Platform.isLinux
          ? ffi.databaseFactoryFfi
          : databaseFactory;
      if (Platform.isWindows || Platform.isLinux) ffi.sqfliteFfiInit();
      final file =
          await (_databasePath?.call() ??
              () async {
                final directory = Directory(
                  path.join(
                    (await getApplicationSupportDirectory()).path,
                    'banjian',
                  ),
                );
                await directory.create(recursive: true);
                return path.join(directory.path, 'participation.sqlite');
              }());
      final options = OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) async {
          await db.rawQuery('PRAGMA journal_mode=WAL');
          await db.execute('PRAGMA synchronous=FULL');
        },
        onCreate: (db, _) => _schema(db),
      );
      final db =
          await (_databaseOpener?.call(file, options) ??
              factory.openDatabase(file, options: options));
      _database = db;
      return db;
    }();
    _opening = opening;
    try {
      return await opening;
    } catch (_) {
      // onCreate may have run inside a transaction that the platform rolled
      // back. Both the pending Future and schema flag must be retryable.
      _schemaReady = false;
      rethrow;
    } finally {
      if (identical(_opening, opening)) _opening = null;
    }
  }

  bool _schemaReady = false;
  Future<void> _schema(DatabaseExecutor db) async {
    if (_schemaReady) return;
    await db.execute(
      'CREATE TABLE IF NOT EXISTS room_client_meta(namespace TEXT PRIMARY KEY,payload TEXT NOT NULL,revision INTEGER NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS room_client_journal(namespace TEXT,identity TEXT,payload TEXT NOT NULL,updated INTEGER NOT NULL,PRIMARY KEY(namespace,identity))',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS room_client_cache(namespace TEXT,identity TEXT,payload TEXT NOT NULL,bytes INTEGER NOT NULL,updated INTEGER NOT NULL,PRIMARY KEY(namespace,identity))',
    );
    _schemaReady = true;
  }

  String _credentialKey(String identity) => '$key:identity:$identity';
  Future<void> _migrate(Database db) async {
    if (_migrated) return;
    await _schema(db);
    final existing = await db.query(
      'room_client_meta',
      where: 'namespace=?',
      whereArgs: [key],
    );
    if (existing.isEmpty) {
      final legacy = await vault.read(key);
      if (legacy != null) {
        final value = jsonDecode(legacy);
        if (value is! Json) throw const FormatException('本地参与记录格式无效');
        await _write(db, value, checkRevision: false);
      }
    }
    final rows = await db.query(
      'room_client_meta',
      where: 'namespace=?',
      whereArgs: [key],
    );
    _knownRevision = rows.isEmpty ? 0 : rows.single['revision'] as int;
    // The legacy key is removed only after the SQLite commit and all vault
    // identities succeeded. Interrupted migrations can therefore be retried.
    if (rows.isNotEmpty) await vault.delete(key);
    _migrated = true;
  }

  Future<Json?> _room(
    Database db,
    String identity, {
    bool snapshot = true,
  }) async {
    final rows = await db.query(
      'room_client_journal',
      where: 'namespace=? AND identity=?',
      whereArgs: [key, identity],
    );
    final secret = await vault.read(_credentialKey(identity));
    if (rows.isEmpty) {
      if (secret == null) return null;
      return {
        ...jsonDecode(secret) as Json,
        'active': false,
        'op': newSecret(),
        'pending': <dynamic>[],
        'drafts': <String, dynamic>{},
      };
    }
    if (secret == null) throw const FormatException('活动身份读取失败，已保留待确认记录');
    final credentials = jsonDecode(secret) as Json;
    _credentials[identity] = secret;
    final value = jsonDecode(rows.single['payload'] as String) as Json;
    value.addAll(credentials);
    if (snapshot) {
      final caches = await db.query(
        'room_client_cache',
        where: 'namespace=? AND identity=?',
        whereArgs: [key, identity],
      );
      if (caches.isNotEmpty) {
        try {
          value['snapshot'] = await compute(
            _decodeRoomCache,
            caches.single['payload'] as String,
          );
        } catch (_) {
          /* Disposable cache; journal remains authoritative. */
        }
      }
    }
    return value;
  }

  @override
  Future<Json?> read() => _serial(() async {
    final db = await _open();
    await _migrate(db);
    final rows = await db.query(
      'room_client_meta',
      where: 'namespace=?',
      whereArgs: [key],
    );
    if (rows.isEmpty) return null;
    _knownRevision = rows.single['revision'] as int;
    final meta = jsonDecode(rows.single['payload'] as String) as Json;
    if (meta['current'] is! String) return meta['value'] as Json?;
    final identity = meta['current'] as String;
    final value = await _room(db, identity);
    if (value == null) return null;
    final archives = <String, dynamic>{};
    final old = await db.query(
      'room_client_journal',
      columns: ['identity'],
      where: 'namespace=? AND identity!=?',
      whereArgs: [key, identity],
      orderBy: 'updated DESC',
      limit: 64,
    );
    for (final row in old) {
      final id = row['identity'] as String;
      final secret = await vault.read(_credentialKey(id));
      if (secret != null) {
        archives[id] = {...jsonDecode(secret) as Json, 'stored': true};
      }
    }
    value['archives'] = archives;
    return value;
  });

  @override
  Future<Json?> readRoom(String identity) => _serial(() async {
    final db = await _open();
    await _migrate(db);
    return _room(db, identity);
  });
  @override
  Future<void> write(Json value) => _serial(() async {
    final db = await _open();
    await _migrate(db);
    await _write(db, value);
  });

  Future<void> _write(
    Database db,
    Json value, {
    bool checkRevision = true,
  }) async {
    final invite = RoomInvite.parse(value['url'] as String? ?? '');
    if (invite == null &&
        (value.containsKey('token') ||
            value.containsKey('url') ||
            value.containsKey('archives'))) {
      throw const FormatException('参与身份格式无效，未写入普通存储');
    }
    final records = <String, Json>{};
    if (invite != null) {
      records[invite.identityKey] = value;
      for (final entry in ((value['archives'] as Json?) ?? {}).entries) {
        if (entry.value is Json && entry.value['stored'] != true) {
          records[entry.key] = entry.value as Json;
        }
      }
    }
    // Store secrets before the transaction, without rewriting unchanged keys
    // for each keystroke. Orphan keys after a disk failure are harmless.
    for (final entry in records.entries) {
      final secret = jsonEncode({
        'url': entry.value['url'],
        'token': entry.value['token'],
      });
      if (_credentials[entry.key] != secret) {
        final existing = await vault.read(_credentialKey(entry.key));
        if (checkRevision &&
            existing != null &&
            (jsonDecode(existing) as Json)['token'] != entry.value['token']) {
          throw const FormatException('此活动已有本机身份，请重新连接以恢复原记录');
        }
        await vault.write(_credentialKey(entry.key), secret);
        _credentials[entry.key] = secret;
      }
    }
    final snapshots = <String, ({String payload, int bytes})>{};
    for (final entry in records.entries) {
      if (entry.value['snapshot'] case final Json raw) {
        final encoded = await compute(_encodeRoomCache, raw);
        final bytes = utf8.encode(encoded).length;
        if (bytes <= RoomLimits.snapshotBytes) {
          snapshots[entry.key] = (payload: encoded, bytes: bytes);
        }
      }
    }
    final next = await db.transaction((tx) async {
      final rows = await tx.query(
        'room_client_meta',
        where: 'namespace=?',
        whereArgs: [key],
      );
      final revision = rows.isEmpty ? 0 : rows.single['revision'] as int;
      if (checkRevision &&
          _knownRevision != null &&
          revision != _knownRevision) {
        throw const FormatException('参与记录已在另一窗口更新，请重新连接；输入未被覆盖');
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final entry in records.entries) {
        final data = Map<String, dynamic>.of(entry.value)
          ..remove('url')
          ..remove('token')
          ..remove('archives')
          ..remove('snapshot')
          ..remove('stored');
        final encoded = jsonEncode(data);
        await tx.insert('room_client_journal', {
          'namespace': key,
          'identity': entry.key,
          'payload': encoded,
          'updated': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        if (snapshots[entry.key] case final snapshot?) {
          await tx.insert('room_client_cache', {
            'namespace': key,
            'identity': entry.key,
            'payload': snapshot.payload,
            'bytes': snapshot.bytes,
            'updated': now,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
      final meta = invite == null
          ? {'value': value}
          : {'current': invite.identityKey};
      await tx.insert('room_client_meta', {
        'namespace': key,
        'payload': jsonEncode(meta),
        'revision': revision + 1,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      final caches = await tx.query(
        'room_client_cache',
        columns: ['identity', 'bytes'],
        where: 'namespace=?',
        whereArgs: [key],
        orderBy: 'updated DESC',
      );
      var bytes = 0, count = 0;
      for (final cache in caches) {
        bytes += cache['bytes'] as int;
        count++;
        if (bytes > snapshotBudget || count > snapshotCount) {
          await tx.delete(
            'room_client_cache',
            where: 'namespace=? AND identity=?',
            whereArgs: [key, cache['identity']],
          );
        }
      }
      return revision + 1;
    });
    _knownRevision = next;
  }
}

/// Kept as a source-compatible name; the implementation now separates secrets
/// from durable journals and optional snapshots.
class SecureParticipationStorage extends RoomLocalStorage {
  SecureParticipationStorage({super.key});
}
