import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;
import '../../models/pm_send_command.dart';
import 'pm_outbox_repository.dart';

enum PmDraftKind { compose, reply }

class PmDraft {
  const PmDraft({
    required this.id,
    required this.ownerId,
    required this.kind,
    this.recipient = '',
    this.title = '',
    this.body = '',
    this.conversationId = '',
    this.threadId = '',
  });
  final String id;
  final int ownerId;
  final PmDraftKind kind;
  final String recipient;
  final String title;
  final String body;
  final String conversationId;
  final String threadId;
  bool get isEmpty => kind == PmDraftKind.reply
      ? body.isEmpty
      : recipient.trim().isEmpty && title.isEmpty && body.isEmpty;
  PmDraft edited({
    required String recipient,
    required String title,
    required String body,
  }) => PmDraft(
    id: id,
    ownerId: ownerId,
    kind: kind,
    recipient: recipient,
    title: title,
    body: body,
    conversationId: conversationId,
    threadId: threadId,
  );
  Map<String, dynamic> toJson() => {
    'recipient': recipient,
    'title': title,
    'body': body,
    'conversation_id': conversationId,
    'thread_id': threadId,
  };
  static String newId() => base64UrlEncode(
    List<int>.generate(18, (_) => Random.secure().nextInt(256)),
  );
  static String replyId(String conversation, String thread) =>
      jsonEncode(['reply', conversation, thread]);
}

class PmDraftSlot {
  const PmDraftSlot({this.draft, this.revision = 0});
  final PmDraft? draft;
  final int revision;
}

class PmDraftConflict implements Exception {
  const PmDraftConflict();
  @override
  String toString() => '草稿已在另一处更新，请保留当前输入并重新打开草稿';
}

abstract class PmDraftRepository {
  Future<PmDraftSlot> read(int ownerId, String id);
  Future<PmDraftSlot?> findCompose(int ownerId, {String? recipient});
  Future<List<PmDraft>> listCompose(int ownerId);
  Future<int> save(PmDraft draft, {required int expectedRevision});
  Future<int> clear(int ownerId, String id, {required int expectedRevision});
}

final pmDraftRepositoryProvider = Provider<PmDraftRepository>(
  (ref) => PmDraftStore.shared,
);

class PmDraftStore implements PmDraftRepository, PmOutboxRepository {
  PmDraftStore({this.databasePath});
  static final shared = PmDraftStore();
  final String? databasePath;
  Future<Database>? _database;
  Future<void> _writes = Future.value();

  Future<T> _write<T>(Future<T> Function(Database db) action) {
    final next = _writes.then((_) async => action(await _open()));
    _writes = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  @override
  Future<PmDraftSlot> read(int ownerId, String id) async {
    await _writes;
    final rows = await (await _open()).query(
      'pm_draft',
      where: 'owner_id = ? AND draft_id = ?',
      whereArgs: [ownerId, id],
    );
    return rows.isEmpty ? const PmDraftSlot() : _slot(rows.single);
  }

  @override
  Future<PmDraftSlot?> findCompose(int ownerId, {String? recipient}) async {
    await _writes;
    final target = recipient?.trim().toLowerCase() ?? '';
    final rows = await (await _open()).query(
      'pm_draft',
      where:
          'owner_id = ? AND kind = ? AND deleted = 0${target.isEmpty ? '' : ' AND recipient_key = ?'}',
      whereArgs: [
        ownerId,
        PmDraftKind.compose.name,
        if (target.isNotEmpty) target,
      ],
      orderBy: 'change_id DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : _slot(rows.single);
  }

  @override
  Future<List<PmDraft>> listCompose(int ownerId) async {
    await _writes;
    final rows = await (await _open()).query(
      'pm_draft',
      where: 'owner_id = ? AND kind = ? AND deleted = 0',
      whereArgs: [ownerId, PmDraftKind.compose.name],
      orderBy: 'change_id DESC',
    );
    return [for (final row in rows) _slot(row).draft!];
  }

  @override
  Future<int> save(PmDraft draft, {required int expectedRevision}) {
    if (draft.ownerId <= 0 || draft.id.isEmpty) {
      throw ArgumentError('Draft requires a verified owner and ID');
    }
    if (draft.isEmpty) {
      return clear(draft.ownerId, draft.id, expectedRevision: expectedRevision);
    }
    return _write(
      (db) => db.transaction((txn) async {
        final revision = await _nextRevision(
          txn,
          draft.ownerId,
          draft.id,
          expectedRevision,
        );
        await txn.insert('pm_draft', {
          'owner_id': draft.ownerId,
          'draft_id': draft.id,
          'kind': draft.kind.name,
          'recipient_key': draft.recipient.trim().toLowerCase(),
          'payload': jsonEncode(draft.toJson()),
          'revision': revision,
          'deleted': 0,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        return revision;
      }),
    );
  }

  @override
  Future<int> clear(
    int ownerId,
    String id, {
    required int expectedRevision,
  }) => _write(
    (db) => db.transaction((txn) async {
      final revision = await _nextRevision(txn, ownerId, id, expectedRevision);
      // A tombstone rejects saves from older editors, including editors opened
      // before this draft was first written. It contains no message text.
      await txn.insert('pm_draft', {
        'owner_id': ownerId,
        'draft_id': id,
        'kind': '',
        'recipient_key': '',
        'payload': '{}',
        'revision': revision,
        'deleted': 1,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      return revision;
    }),
  );

  Future<int> _nextRevision(
    Transaction txn,
    int ownerId,
    String id,
    int expected,
  ) async {
    final rows = await txn.query(
      'pm_draft',
      columns: ['revision'],
      where: 'owner_id = ? AND draft_id = ?',
      whereArgs: [ownerId, id],
    );
    final actual = rows.isEmpty ? 0 : rows.single['revision'] as int;
    if (actual != expected) throw const PmDraftConflict();
    return actual + 1;
  }

  PmDraftSlot _slot(Map<String, Object?> row) {
    final revision = row['revision'] as int;
    if (row['deleted'] == 1) return PmDraftSlot(revision: revision);
    final data = jsonDecode(row['payload'] as String) as Map<String, dynamic>;
    return PmDraftSlot(
      revision: revision,
      draft: PmDraft(
        id: row['draft_id'] as String,
        ownerId: row['owner_id'] as int,
        kind: PmDraftKind.values.byName(row['kind'] as String),
        recipient: data['recipient'] as String,
        title: data['title'] as String,
        body: data['body'] as String,
        conversationId: data['conversation_id'] as String,
        threadId: data['thread_id'] as String,
      ),
    );
  }

  Future<String> databaseForBackup() async {
    await _writes;
    return (await _open()).path;
  }

  @override
  Future<PmEnqueuedDraft> enqueueDraft(
    PmDraft draft, {
    required int expectedRevision,
    required String receiver,
    required String related,
  }) {
    if (draft.ownerId <= 0 ||
        receiver.trim().isEmpty ||
        draft.body.trim().isEmpty ||
        (draft.kind == PmDraftKind.compose && draft.title.trim().isEmpty) ||
        (draft.kind == PmDraftKind.reply && draft.conversationId.isEmpty)) {
      throw const FormatException('账号、收件人或消息内容不完整');
    }
    return _write(
      (db) => db.transaction((txn) async {
        final duplicate = await txn.query(
          'pm_send_queue',
          where: 'owner_id = ? AND draft_id = ? AND draft_revision = ?',
          whereArgs: [draft.ownerId, draft.id, expectedRevision],
        );
        if (duplicate.isNotEmpty) {
          final command = _command(duplicate.single);
          if (command.body != draft.body.trim() ||
              command.receiver != receiver.trim() ||
              command.title != draft.title.trim() ||
              command.related != related ||
              command.compose != (draft.kind == PmDraftKind.compose) ||
              command.conversationId != draft.conversationId ||
              command.threadId != draft.threadId) {
            throw const PmDraftConflict();
          }
          return PmEnqueuedDraft(command, expectedRevision + 1);
        }
        final revision = await _nextRevision(
          txn,
          draft.ownerId,
          draft.id,
          expectedRevision,
        );
        final command = PmSendCommand(
          id: PmDraft.newId(),
          ownerId: draft.ownerId,
          compose: draft.kind == PmDraftKind.compose,
          receiver: receiver.trim(),
          title: draft.title.trim(),
          body: draft.body.trim(),
          conversationId: draft.conversationId,
          threadId: draft.threadId,
          related: related,
          createdAt: DateTime.now(),
        );
        final sequence = await txn.insert('pm_send_queue', {
          'command_id': command.id,
          'owner_id': command.ownerId,
          'draft_id': draft.id,
          'draft_revision': expectedRevision,
          'target_key': command.targetKey,
          'payload': jsonEncode(command.toJson()),
          'status': command.status.name,
          'baseline': -1,
          'created_at': command.createdAt.millisecondsSinceEpoch,
        });
        await txn.insert('pm_draft', {
          'owner_id': draft.ownerId,
          'draft_id': draft.id,
          'kind': '',
          'recipient_key': '',
          'payload': '{}',
          'revision': revision,
          'deleted': 1,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        return PmEnqueuedDraft(command.copyWith(sequence: sequence), revision);
      }),
    );
  }

  PmSendCommand _command(Map<String, Object?> row) => PmSendCommand.fromRow(
    row,
    Map<String, dynamic>.from(jsonDecode(row['payload']! as String) as Map),
  );

  @override
  Future<List<PmSendCommand>> outboxFor(int ownerId) async {
    await _writes;
    final rows = await (await _open()).query(
      'pm_send_queue',
      where: 'owner_id = ?',
      whereArgs: [ownerId],
      orderBy: 'sequence ASC',
    );
    return rows.map(_command).toList();
  }

  @override
  Future<PmSendCommand?> claimNext(int ownerId) => _write(
    (db) => db.transaction((txn) async {
      final rows = await txn.rawQuery(
        '''SELECT q.* FROM pm_send_queue q
      WHERE q.owner_id = ? AND q.status = 'queued' AND NOT EXISTS
      (SELECT 1 FROM pm_send_queue p WHERE p.owner_id = q.owner_id AND p.target_key = q.target_key
        AND p.sequence < q.sequence AND p.status NOT IN ('sent', 'cancelled'))
      ORDER BY q.sequence ASC LIMIT 1''',
        [ownerId],
      );
      if (rows.isEmpty) return null;
      final command = _command(rows.single);
      await txn.update(
        'pm_send_queue',
        {'status': 'preparing', 'error': null, 'attempt': command.attempt + 1},
        where: 'command_id = ? AND owner_id = ? AND status = ?',
        whereArgs: [command.id, ownerId, 'queued'],
      );
      return command.copyWith(
        status: PmSendStatus.preparing,
        attempt: command.attempt + 1,
      );
    }),
  );

  @override
  Future<bool> changeCommand(
    int ownerId,
    String id, {
    required Set<PmSendStatus> from,
    required PmSendStatus to,
    int? baseline,
    int? attempt,
    String? error,
  }) => _write((db) async {
    if (from.isEmpty) return false;
    final changed =
        await db.update(
          'pm_send_queue',
          {'status': to.name, 'error': error, 'baseline': ?baseline},
          where:
              'owner_id = ? AND command_id = ? AND status IN (${List.filled(from.length, '?').join(',')})${attempt == null ? '' : ' AND attempt = ?'}',
          whereArgs: [ownerId, id, ...from.map((s) => s.name), ?attempt],
        ) ==
        1;
    if (changed && (to == PmSendStatus.sent || to == PmSendStatus.cancelled)) {
      try {
        await db.rawDelete(
          '''DELETE FROM pm_send_queue WHERE owner_id = ?
          AND status IN ('sent','cancelled') AND command_id != ? AND sequence NOT IN
          (SELECT sequence FROM pm_send_queue WHERE owner_id = ? AND status IN ('sent','cancelled')
            ORDER BY sequence DESC LIMIT 100)''',
          [ownerId, id, ownerId],
        );
      } catch (_) {
        /* Receipt pruning cannot undo a confirmed send. */
      }
    }
    return changed;
  });

  @override
  Future<void> recoverOutbox(int ownerId) => _write(
    (db) => db.transaction((txn) async {
      await txn.rawUpdate(
        "UPDATE pm_send_queue SET status = 'queued', error = NULL, attempt = attempt + 1 WHERE owner_id = ? AND status = 'preparing'",
        [ownerId],
      );
      await txn.rawUpdate(
        "UPDATE pm_send_queue SET status = 'uncertain', error = ?, attempt = attempt + 1 WHERE owner_id = ? AND status = 'sending'",
        ['上次发送在应用关闭时中断，请核对结果', ownerId],
      );
    }),
  );

  static Future<void> _createOutbox(DatabaseExecutor db) async {
    await db.execute(
      '''CREATE TABLE pm_send_queue (
      sequence INTEGER PRIMARY KEY AUTOINCREMENT, command_id TEXT NOT NULL UNIQUE,
      owner_id INTEGER NOT NULL, draft_id TEXT NOT NULL, draft_revision INTEGER NOT NULL,
      target_key TEXT NOT NULL, payload TEXT NOT NULL, status TEXT NOT NULL, baseline INTEGER NOT NULL,
      attempt INTEGER NOT NULL DEFAULT 0, error TEXT, created_at INTEGER NOT NULL, UNIQUE(owner_id, draft_id, draft_revision))''',
    );
    await db.execute(
      'CREATE INDEX pm_send_owner ON pm_send_queue(owner_id, status, sequence)',
    );
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
            'mubangumi_pm_drafts.sqlite',
          ),
      options: OpenDatabaseOptions(
        onConfigure: (db) async {
          await db.rawQuery('PRAGMA journal_mode=DELETE');
        },
        version: 2,
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) await _createOutbox(db);
        },
        onCreate: (db, _) async {
          await db.execute(
            '''CREATE TABLE pm_draft (change_id INTEGER PRIMARY KEY AUTOINCREMENT,
          owner_id INTEGER NOT NULL, draft_id TEXT NOT NULL, kind TEXT NOT NULL,
          recipient_key TEXT NOT NULL, payload TEXT NOT NULL, revision INTEGER NOT NULL,
          deleted INTEGER NOT NULL, updated_at INTEGER NOT NULL, UNIQUE(owner_id, draft_id))''',
          );
          await _createOutbox(db);
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
