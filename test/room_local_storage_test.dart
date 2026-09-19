import 'dart:convert';
import 'dart:io';
import 'package:banjian_server/banjian_server.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mubangumi/features/anime_appreciation/room_storage.dart';

class Vault implements RoomSecretVault {
  final values = <String, String>{};
  int writes = 0;
  bool fail = false;
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<void> write(String key, String value) async {
    if (fail) throw StateError('vault unavailable');
    writes++;
    values[key] = value;
  }
}

void main() {
  sqfliteFfiInit();
  late Database db;
  late Vault vault;
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    vault = Vault();
  });
  tearDown(() async => db.close());
  Json record([String id = 'event-1']) {
    id = id.padRight(22, 'x');
    final invite = RoomInvite(
      Uri.parse('http://127.0.0.1:43928'),
      id,
      newSecret(),
    );
    final snapshot =
        jsonDecode(
              File(
                'packages/banjian_server/test/fixtures/room_snapshot.json',
              ).readAsStringSync(),
            )
            as Json;
    snapshot['id'] = id;
    return {
      'url': invite.url,
      'token': newSecret(),
      'op': newSecret(),
      'name': '参与者',
      'active': true,
      'pending': [
        {
          'op': newSecret(),
          'action': 'score',
          'event': id,
          'round': 'round-1',
          'score': 8,
        },
      ],
      'drafts': {
        'round-1': {'text': '尚未发送的短评', 'score': 8},
      },
      'snapshot': snapshot,
      'archives': <String, dynamic>{},
    };
  }

  test(
    'migration keeps credentials out of SQLite and preserves current and archived journals',
    () async {
      final value = record(), archive = record('event-2');
      final oldId = RoomInvite.parse(archive['url'])!.identityKey;
      value['archives'] = {oldId: archive};
      vault.values['banjian_participation_v1'] = jsonEncode(value);
      final storage = RoomLocalStorage(database: db, vault: vault);
      final restored = (await storage.read())!;
      expect(restored['pending'], value['pending']);
      expect(restored['drafts'], value['drafts']);
      expect(restored['snapshot'], value['snapshot']);
      expect(vault.values.containsKey('banjian_participation_v1'), false);
      final rows = jsonEncode([
        await db.query('room_client_meta'),
        await db.query('room_client_journal'),
        await db.query('room_client_cache'),
      ]);
      expect(rows, isNot(contains(value['token'])));
      expect(rows, isNot(contains(RoomInvite.parse(value['url'])!.secret)));
      expect(restored['archives'][oldId]['stored'], true);
      expect(restored['archives'][oldId].containsKey('snapshot'), false);
      final oldRoom = (await storage.readRoom(oldId))!;
      expect(oldRoom['pending'], archive['pending']);
      expect(oldRoom['snapshot'], archive['snapshot']);
      final writes = vault.writes;
      restored['drafts']['round-1']['text'] = '继续输入';
      await storage.write(restored);
      expect(
        vault.writes,
        writes,
        reason: 'typing must not rewrite platform credentials',
      );
    },
  );
  test(
    'failed secret migration keeps the legacy record and can resume',
    () async {
      final value = record();
      vault.values['banjian_participation_v1'] = jsonEncode(value);
      vault.fail = true;
      final storage = RoomLocalStorage(database: db, vault: vault);
      await expectLater(storage.read(), throwsStateError);
      expect(vault.values.containsKey('banjian_participation_v1'), true);
      expect(await db.query('room_client_meta'), isEmpty);
      vault.fail = false;
      expect((await storage.read())!['pending'], value['pending']);
    },
  );
  test(
    'snapshot eviction never removes old identity or unconfirmed commands',
    () async {
      final storage = RoomLocalStorage(database: db, vault: vault);
      final first = record();
      await storage.write(first);
      for (var i = 2; i <= 10; i++) {
        await storage.write(record('event-$i'));
      }
      expect(
        await db.query('room_client_cache'),
        hasLength(RoomLocalStorage.snapshotCount),
      );
      final recovered = (await storage.readRoom(
        RoomInvite.parse(first['url'])!.identityKey,
      ))!;
      expect(recovered['token'], first['token']);
      expect(recovered['pending'], first['pending']);
      expect(recovered['drafts'], first['drafts']);
      expect(recovered.containsKey('snapshot'), false);
    },
  );
  test(
    'concurrent windows reject stale writes without overwriting the journal',
    () async {
      final a = RoomLocalStorage(database: db, vault: vault),
          b = RoomLocalStorage(database: db, vault: vault);
      final value = record();
      await a.read();
      await b.read();
      await a.write(value);
      final stale = clone(value);
      stale['pending'] = [];
      await expectLater(b.write(stale), throwsFormatException);
      expect((await a.read())!['pending'], value['pending']);
    },
  );
  test(
    'malformed identities cannot send credentials into the generic command store',
    () async {
      final storage = RoomLocalStorage(database: db, vault: vault);
      await expectLater(
        storage.write({
          'url': 'broken',
          'token': 'secret-token',
          'pending': [],
        }),
        throwsFormatException,
      );
      expect(await db.query('room_client_meta'), isEmpty);
    },
  );
}
