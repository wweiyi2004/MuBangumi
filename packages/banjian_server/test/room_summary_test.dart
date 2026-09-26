import 'package:banjian_server/banjian_server.dart';
import 'package:test/test.dart';

void main() {
  late RoomStore store;
  late String id;
  final members = [newSecret(), newSecret()];
  Json admin(String action, [Json extra = const {}]) => store.admin({
    'op': newSecret(),
    'event': id,
    'version': store.event(id)['version'],
    'action': action,
    ...extra,
  });
  List rounds() => store.event(id)['rounds'] as List;
  void score(String token, String round, int value) => store.submit(token, {
    'op': newSecret(),
    'event': id,
    'round': round,
    'action': 'score',
    'score': value,
  });

  setUp(() {
    store = RoomStore(':memory:');
    id = store.admin({
      'op': newSecret(),
      'action': 'create',
      'title': '周五',
    })['id'];
    for (final (i, title) in ['甲', '乙', '丙', '丁'].indexed) {
      admin('add', {
        'subject': {'id': i + 1, 'title': title, 'summary': '', 'cover': ''},
      });
    }
    final invite = store.event(id)['invite'];
    for (final token in members) {
      store.join({
        'op': newSecret(),
        'event': id,
        'invite': invite,
        'token': token,
        'name': '成员',
      });
    }
    // 甲 7 + 8, 乙 9, 丙 starts without ratings, 丁 never starts.
    for (final (i, scores) in [
      [7, 8],
      [9],
      <int>[],
    ].indexed) {
      final round = rounds()[i]['id'] as String;
      admin('start', {'round': round});
      for (final (m, value) in scores.indexed) {
        score(members[m], round, value);
      }
    }
  });
  tearDown(() => store.close());

  test('participants see statistics only after the activity ends', () {
    final member = members.first;
    expect(
      (store.view(id, token: member)['rounds'] as List).where(
        (r) => r.containsKey('stats'),
      ),
      isEmpty,
    );
    expect(roomSummary(store.view(id, token: member)), isEmpty);
    admin('end');
    final view = store.view(id, token: member);
    final withStats = (view['rounds'] as List)
        .where((r) => r.containsKey('stats'))
        .map((r) => r['subject']['title']);
    // 丁 never started, so it stays unpublished.
    expect(withStats, ['甲', '乙', '丙']);
    // The typed client model still accepts the ended projection.
    expect(() => RoomSnapshot.fromJson(view), returnsNormally);
  });

  test('ranking sorts by mean, shares ranks on ties, skips unrated', () {
    Json round(String title, double? mean, int count, {int? mine}) => {
      'id': title,
      'subject': {'title': title, 'cover': ''},
      'myScore': mine,
      if (mean != null || count == 0) 'stats': {'count': count, 'mean': mean},
    };
    final summary = roomSummary({
      'rounds': [
        round('甲', 7.5, 2, mine: 7),
        round('乙', 9, 1),
        round('丙', 7.5, 1),
        round('丁', null, 0),
        {
          'id': '戊',
          'subject': {'title': '戊'},
        },
      ],
    });
    expect(summary.map((e) => '${e.rank} ${e.title} ${e.mean} ${e.count}'), [
      '1 乙 9.0 1',
      '2 甲 7.5 2',
      '2 丙 7.5 1',
    ]);
    expect(summary[1].myScore, 7);
    expect(summary.first.myScore, isNull);
  });

  test('ended ranking from the store matches the scores', () {
    admin('end');
    final summary = roomSummary(store.view(id, token: members.first));
    expect(summary.map((e) => (e.title, e.mean, e.count)), [
      ('乙', 9.0, 1),
      ('甲', 7.5, 2),
    ]);
    expect(summary.map((e) => e.myScore), [9, 7]);
  });
}
