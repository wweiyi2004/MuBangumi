import 'dart:convert';
import 'package:sqflite/sqflite.dart';

/// The ledger follows the durable intent. Discarding one intent restores only
/// rows it still owns, and rebases later undo records instead of erasing them.
abstract final class EpisodeActivityLedger {
  static Future<void> configure(Database db) async {
    await db.execute(
      'CREATE TABLE IF NOT EXISTS episode_activity (username TEXT NOT NULL, episode_id INTEGER NOT NULL, subject_id INTEGER NOT NULL, day TEXT NOT NULL, active INTEGER NOT NULL, mutation_id INTEGER, PRIMARY KEY(username, episode_id))',
    );
    final columns = await db.rawQuery('PRAGMA table_info(episode_activity)');
    if (!columns.any((row) => row['name'] == 'mutation_id')) {
      await db.execute(
        'ALTER TABLE episode_activity ADD COLUMN mutation_id INTEGER',
      );
    }
    await db.execute(
      'CREATE INDEX IF NOT EXISTS episode_activity_days ON episode_activity(username, active, day)',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS episode_activity_before (mutation_id INTEGER NOT NULL, username TEXT NOT NULL, episode_id INTEGER NOT NULL, prior TEXT, PRIMARY KEY(mutation_id, username, episode_id))',
    );
  }

  static Future<void> record(
    Transaction txn,
    String username,
    int mutationId,
    Map<String, dynamic> payload,
    DateTime moment, {
    int? replacing,
  }) async {
    final entries = payload['activity_episodes'];
    if (entries is List) {
      for (final entry in entries.whereType<Map>()) {
        await _episode(
          txn,
          username,
          mutationId,
          {
            ...payload,
            'episode_id': entry['episode_id'],
            'activity_before': entry['before'],
            'type': 2,
          },
          moment,
          replacing: replacing,
        );
      }
    } else if (payload.containsKey('activity_before')) {
      await _episode(
        txn,
        username,
        mutationId,
        payload,
        moment,
        replacing: replacing,
      );
    }
  }

  static Future<void> _episode(
    Transaction txn,
    String username,
    int mutationId,
    Map<String, dynamic> payload,
    DateTime moment, {
    int? replacing,
  }) async {
    final owner = username.trim().toLowerCase();
    final episode = payload['episode_id'];
    final type = payload['type'];
    final before = payload['activity_before'];
    if (episode is! int ||
        episode <= 0 ||
        before == null ||
        (before == type && replacing == null)) {
      return;
    }
    final rows = await txn.query(
      'episode_activity',
      where: 'username = ? AND episode_id = ?',
      whereArgs: [owner, episode],
    );
    final current = rows.firstOrNull;
    await txn.insert('episode_activity_before', {
      'mutation_id': mutationId,
      'username': owner,
      'episode_id': episode,
      'prior': current == null ? null : jsonEncode(current),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    if (type != 2) {
      await txn.update(
        'episode_activity',
        {'active': 0, 'mutation_id': mutationId},
        where: 'username = ? AND episode_id = ?',
        whereArgs: [owner, episode],
      );
      return;
    }
    if (before == 2) {
      if (current != null && current['mutation_id'] == replacing) {
        await txn.update(
          'episode_activity',
          {'mutation_id': mutationId},
          where: 'username = ? AND episode_id = ?',
          whereArgs: [owner, episode],
        );
      }
      return;
    }
    final restoring = payload['activity_undo'] == true;
    if (restoring && current == null) return;
    final local = moment.toLocal();
    final day = restoring
        ? current!['day']
        : '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
    await txn.insert('episode_activity', {
      'username': owner,
      'episode_id': episode,
      'subject_id': payload['subject_id'],
      'day': day,
      'active': 1,
      'mutation_id': mutationId,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> confirmed(Transaction txn, int mutationId) => txn.delete(
    'episode_activity_before',
    where: 'mutation_id = ?',
    whereArgs: [mutationId],
  );

  static Future<void> discard(Transaction txn, int mutationId) async {
    final undo = await txn.query(
      'episode_activity_before',
      where: 'mutation_id = ?',
      whereArgs: [mutationId],
    );
    for (final entry in undo) {
      final owner = entry['username'], episode = entry['episode_id'];
      final prior = entry['prior'] as String?;
      final current = await txn.query(
        'episode_activity',
        where: 'username = ? AND episode_id = ? AND mutation_id = ?',
        whereArgs: [owner, episode, mutationId],
      );
      if (current.isNotEmpty) {
        if (prior == null) {
          await txn.delete(
            'episode_activity',
            where: 'username = ? AND episode_id = ?',
            whereArgs: [owner, episode],
          );
        } else {
          await txn.insert(
            'episode_activity',
            Map<String, Object?>.from(jsonDecode(prior) as Map),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
      final later = await txn.query(
        'episode_activity_before',
        where: 'username = ? AND episode_id = ? AND mutation_id <> ?',
        whereArgs: [owner, episode, mutationId],
      );
      for (final child in later) {
        final encoded = child['prior'] as String?;
        if (encoded != null &&
            (jsonDecode(encoded) as Map)['mutation_id'] == mutationId) {
          await txn.update(
            'episode_activity_before',
            {'prior': prior},
            where: 'mutation_id = ? AND username = ? AND episode_id = ?',
            whereArgs: [child['mutation_id'], owner, episode],
          );
        }
      }
    }
    await confirmed(txn, mutationId);
  }
}
