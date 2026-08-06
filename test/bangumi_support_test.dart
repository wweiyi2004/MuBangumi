import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/network/bangumi_support.dart';
import 'package:mubangumi/models/bangumi_models.dart';

void main() {
  test('pageQuery continues beyond first page', () {
    expect(
      BangumiSupport.pageQuery(limit: 24, offset: 0),
      {'limit': 24, 'offset': 0},
    );
    expect(
      BangumiSupport.pageQuery(limit: 24, offset: 24),
      {'limit': 24, 'offset': 24},
    );
    expect(
      BangumiSupport.pageQuery(limit: 24, offset: 48)['offset'],
      greaterThan(24),
    );
  });

  test('collectionUpdatePayload includes rate comment tags private', () {
    final payload = BangumiSupport.collectionUpdatePayload(
      type: CollectionType.doing,
      rate: 12,
      comment: ' 好看 ',
      tags: [' 日常 ', '', '治愈'],
      private: true,
    );
    expect(payload['type'], CollectionType.doing.value);
    expect(payload['rate'], 10); // clamped
    expect(payload['comment'], ' 好看 ');
    expect(payload['tags'], ['日常', '治愈']);
    expect(payload['private'], isTrue);
  });

  test('UserCollection parses rate comment tags private', () {
    final collection = UserCollection.fromJson({
      'subject_id': 12,
      'subject_type': 2,
      'type': 3,
      'rate': 9,
      'ep_status': 4,
      'vol_status': 0,
      'comment': '神作',
      'tags': ['战斗', '热血'],
      'private': true,
      'updated_at': '2026-01-01T00:00:00+08:00',
      'subject': {
        'id': 12,
        'type': 2,
        'name': 'Test',
        'name_cn': '测试',
        'eps': 12,
        'score': 8.0,
      },
    });
    expect(collection.rate, 9);
    expect(collection.comment, '神作');
    expect(collection.tags, ['战斗', '热血']);
    expect(collection.private, isTrue);
  });

  test('progress tooling centers on main episodes only', () {
    final mixed = [
      UserEpisodeCollection(
        episode: const Episode(
          id: 1,
          type: 0,
          number: 1,
          sort: 1,
          name: 'E1',
          nameCn: '第一话',
          airDate: '',
          description: '',
        ),
        type: 2, // watched
        updatedAt: 0,
      ),
      UserEpisodeCollection(
        episode: const Episode(
          id: 2,
          type: 0,
          number: 2,
          sort: 2,
          name: 'E2',
          nameCn: '第二话',
          airDate: '',
          description: '',
        ),
        type: 0, // unwatched main
        updatedAt: 0,
      ),
      UserEpisodeCollection(
        episode: const Episode(
          id: 90,
          type: 2,
          number: 0,
          sort: 0,
          name: 'OP',
          nameCn: '',
          airDate: '',
          description: '',
        ),
        type: 0, // unwatched OP — must not be next
        updatedAt: 0,
      ),
      UserEpisodeCollection(
        episode: const Episode(
          id: 91,
          type: 1,
          number: 0,
          sort: 99,
          name: 'SP',
          nameCn: '',
          airDate: '',
          description: '',
        ),
        type: 0,
        updatedAt: 0,
      ),
    ];

    final next = BangumiSupport.nextUnwatchedMain(mixed);
    expect(next?.episode.id, 2);
    expect(next?.episode.type, 0);

    final unfinished = BangumiSupport.unfinishedMainEpisodeIds(mixed);
    expect(unfinished, [2]);
    expect(unfinished, isNot(contains(90)));
    expect(unfinished, isNot(contains(91)));

    // Mark-next style count: only 本篇.
    expect(BangumiSupport.watchedMainCountAfterMark(mixed, 2), 2);
    // Done auto-complete pool length is main-only.
    expect(BangumiSupport.mainEpisodeCollections(mixed), hasLength(2));
  });

  test('filterEpisodesByType keeps SP/OP/ED correctly', () {
    final episodes = [
      const Episode(
        id: 1,
        type: 0,
        number: 1,
        sort: 1,
        name: 'E1',
        nameCn: '第一话',
        airDate: '',
        description: '',
      ),
      const Episode(
        id: 2,
        type: 2,
        number: 0,
        sort: 0,
        name: 'OP',
        nameCn: '',
        airDate: '',
        description: '',
      ),
      const Episode(
        id: 3,
        type: 1,
        number: 0,
        sort: 99,
        name: 'SP',
        nameCn: '',
        airDate: '',
        description: '',
      ),
    ];
    expect(BangumiSupport.filterEpisodesByType(episodes, null), hasLength(3));
    expect(
      BangumiSupport.filterEpisodesByType(episodes, 0).map((e) => e.id),
      [1],
    );
    expect(
      BangumiSupport.filterEpisodesByType(episodes, 2).map((e) => e.id),
      [2],
    );
    expect(BangumiSupport.episodeTypeLabel(0), '本篇');
    expect(BangumiSupport.episodeTypeLabel(2), 'OP');
  });

  test('parseCharacters persons related subjects from API-shaped json', () {
    final characters = BangumiSupport.parseCharacters([
      {
        'id': 1,
        'name': 'Char',
        'name_cn': '角色',
        'relation': '主角',
        'images': {'large': 'https://example.com/c.jpg'},
        'actors': [
          {'name': '声优A'},
        ],
      },
    ]);
    expect(characters, hasLength(1));
    expect(characters.first.displayName, '角色');
    expect(characters.first.actors, ['声优A']);

    final persons = BangumiSupport.parsePersons([
      {
        'id': 9,
        'name': 'Director',
        'name_cn': '监督',
        'relation': '导演',
        'career': ['director'],
        'images': {'medium': 'https://example.com/p.jpg'},
      },
    ]);
    expect(persons.first.relation, '导演');

    final related = BangumiSupport.parseRelatedSubjects([
      {
        'relation': '续集',
        'subject': {
          'id': 22,
          'type': 2,
          'name': 'Sequel',
          'name_cn': '续作',
          'images': {'common': 'https://example.com/s.jpg'},
        },
      },
    ]);
    expect(related.first.id, 22);
    expect(related.first.toSubject().displayName, '续作');
  });

  test('parseCalendar maps weekday and subjects', () {
    final days = BangumiSupport.parseCalendar([
      {
        'weekday': {'id': 1, 'cn': '星期一'},
        'items': [
          {
            'id': 100,
            'type': 2,
            'name': 'Show',
            'name_cn': '节目',
            'images': {
              'large': 'https://lain.bgm.tv/pic/cover/l/xx.jpg',
            },
            'rating': {'score': 7.5},
            'collection': {},
            'eps': 12,
          },
        ],
      },
      {
        'weekday': {'id': 3, 'cn': '星期三'},
        'items': [],
      },
    ]);
    expect(days, hasLength(2));
    expect(days.first.weekday, 1);
    expect(days.first.weekdayLabel, '星期一');
    expect(days.first.subjects.first.id, 100);
    expect(days.first.subjects.first.displayName, '节目');
  });

  test('parseSubjectCommentsHtml extracts text blocks', () {
    const html = '''
<div id="item_12" class="item">
  <span class="avatarNeue" style="background-image:url('//lain.bgm.tv/pic/user/l/a.jpg')"></span>
  <a class="l">测试用户</a>
  <span class="starlight stars8"></span>
  <div class="comment">这部真的不错</div>
</div>
''';
    final comments = BangumiSupport.parseSubjectCommentsHtml(html);
    expect(comments, isNotEmpty);
    expect(comments.first.userName, '测试用户');
    expect(comments.first.comment, contains('不错'));
    expect(comments.first.rate, 8);
  });
}
