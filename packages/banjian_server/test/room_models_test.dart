import 'dart:convert';
import 'dart:io';
import 'package:banjian_server/banjian_server.dart';
import 'package:test/test.dart';

void main() {
  Json fixture() =>
      jsonDecode(File('test/fixtures/room_snapshot.json').readAsStringSync())
          as Json;
  test(
    'typed snapshot accepts the shared browser fixture and keeps immutable rounds',
    () {
      final s = RoomSnapshot.fromJson(fixture());
      expect(s.current!.status, RoundStatus.open);
      expect(s.current!.statistics!.mean, 8);
      expect(() => s.toJson()['rounds'].clear(), throwsUnsupportedError);
    },
  );
  test('comment wall flag falls back to the host switch for old servers', () {
    RoundSnapshot round(Json json) =>
        RoomSnapshot.fromJson(json).rounds.single;
    final old = fixture()..['rounds'] = [fixture()['rounds'][0]];
    old['rounds'][0]['publicComments'] = false;
    expect(round(old).commentsOpen, false);
    final scored = fixture()..['rounds'] = [fixture()['rounds'][0]];
    scored['rounds'][0]['commentsOpen'] = true;
    expect(round(scored).commentsOpen, true);
    scored['rounds'][0]['commentsOpen'] = 'yes';
    expect(() => RoomSnapshot.fromJson(scored), throwsFormatException);
  });
  test('invalid states, distributions and foreign deltas fail explicitly', () {
    final bad = fixture();
    bad['rounds'][0]['status'] = 'bogus';
    expect(() => RoomSnapshot.fromJson(bad), throwsFormatException);
    final counts = fixture();
    counts['rounds'][0]['stats']['count'] = 2;
    expect(() => RoomSnapshot.fromJson(counts), throwsFormatException);
    final old = fixture();
    expect(
      () => mergeRoomSnapshot(old, {
        'type': 'delta',
        'id': 'event-1',
        'baseRevision': 1,
        'revision': 4,
        'rounds': [],
      }),
      throwsFormatException,
    );
    expect(
      () => mergeRoomSnapshot(old, {
        ...old,
        'type': 'delta',
        'serverEpoch': 'server-2',
        'baseRevision': 3,
        'revision': 4,
        'rounds': [],
      }),
      throwsFormatException,
    );
  });
  test('delta replaces a round projection, removing withdrawn results', () {
    final old = fixture(),
        round = Map<String, dynamic>.from(fixture()['rounds'][0])
          ..remove('stats');
    round['published'] = false;
    final result = mergeRoomSnapshot(old, {
      ...old,
      'type': 'delta',
      'baseRevision': 3,
      'revision': 4,
      'rounds': [round],
    });
    expect(result['rounds'][0].containsKey('stats'), false);
  });
  test('commands validate role without changing the idempotency payload', () {
    final value = {
      'op': 'same-operation',
      'event': 'event-1',
      'round': 'round-1',
      'action': 'score',
      'score': 8,
    };
    expect(
      jsonEncode(RoomCommand.fromJson(value, participant: true).toJson()),
      jsonEncode(value),
    );
    expect(
      () => RoomCommand.fromJson(value, participant: false),
      throwsFormatException,
    );
  });
}
