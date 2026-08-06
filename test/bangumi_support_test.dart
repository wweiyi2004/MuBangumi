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
    expect(payload.containsKey('vol_status'), isFalse);
    expect(payload.containsKey('ep_status'), isFalse);
  });

  test('collectionUpdatePayload includes book progress only when set', () {
    final book = BangumiSupport.collectionUpdatePayload(
      type: CollectionType.doing,
      rate: 8,
      volumeStatus: 3,
      episodeStatus: 12,
    );
    expect(book['vol_status'], 3);
    expect(book['ep_status'], 12);

    final anime = BangumiSupport.collectionUpdatePayload(
      type: CollectionType.doing,
      rate: 8,
    );
    expect(anime.containsKey('vol_status'), isFalse);
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
          {'id': 99, 'name': '声优A', 'images': {'large': 'https://a.jpg'}},
        ],
      },
    ]);
    expect(characters, hasLength(1));
    expect(characters.first.displayName, '角色');
    expect(characters.first.actorNames, ['声优A']);
    expect(characters.first.actors.first.id, 99);

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

  test('parse character and person detail mono graph from API-shaped json', () {
    final character = BangumiSupport.parseCharacterDetail({
      'id': 1,
      'name': 'ルルーシュ',
      'summary': '主角',
      'gender': 'male',
      'type': 1,
      'images': {'large': 'https://example.com/c.jpg'},
      'infobox': [
        {'key': '简体中文名', 'value': '鲁路修'},
      ],
      'stat': {'comments': 10, 'collects': 20},
    });
    expect(character.displayName, '鲁路修');
    expect(character.summary, '主角');
    expect(character.collectCount, 20);

    final person = BangumiSupport.parsePersonDetail({
      'id': 3818,
      'name': '福山潤',
      'summary': '声优',
      'gender': 'male',
      'type': 1,
      'career': ['seiyu', 'artist'],
      'images': {'large': 'https://example.com/p.jpg'},
      'infobox': [
        {'key': '简体中文名', 'value': '福山润'},
      ],
      'stat': {'comments': 3, 'collects': 5},
    });
    expect(person.displayName, '福山润');
    expect(person.career, ['seiyu', 'artist']);

    final subjects = BangumiSupport.parseMonoSubjects([
      {
        'id': 8,
        'name': 'Code Geass R2',
        'name_cn': '反叛的鲁路修R2',
        'image': 'https://example.com/s.jpg',
        'type': 2,
        'staff': '主角',
      },
    ]);
    expect(subjects, hasLength(1));
    expect(subjects.first.displayName, '反叛的鲁路修R2');
    expect(subjects.first.toSubject().id, 8);

    final cast = BangumiSupport.parseCharacterPersons([
      {
        'id': 3818,
        'name': '福山潤',
        'staff': '主角',
        'subject_id': 8,
        'subject_name': 'R2',
        'subject_name_cn': 'R2中文',
        'images': {'large': 'https://p.jpg'},
      },
      {
        'id': 3818,
        'name': '福山潤',
        'staff': '主角',
        'subject_id': 793,
        'subject_name': 'R1',
        'subject_name_cn': '',
        'images': {'large': 'https://p.jpg'},
      },
    ]);
    expect(cast, hasLength(1));
    expect(cast.first.subjectName, 'R2中文');

    final roles = BangumiSupport.parsePersonCharacters([
      {
        'id': 1,
        'name': 'ルルーシュ',
        'staff': '主角',
        'subject_name': 'Code',
        'subject_name_cn': '鲁路修',
        'images': {'large': 'https://c.jpg'},
      },
    ]);
    expect(roles.first.name, 'ルルーシュ');
    expect(roles.first.subjectName, '鲁路修');
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
            'air_date': '2026-07-06',
            'images': {
              'large': 'https://lain.bgm.tv/pic/cover/l/xx.jpg',
            },
            'rating': {'score': 7.5},
            'collection': {'doing': 12},
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
    expect(days.first.subjects.first.date, '2026-07-06');
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

  test('parseSubjectCommentsHtml captures profile username', () {
    const html = '''
<div id="item_99" class="item">
  <span class="avatarNeue" style="background-image:url('//lain.bgm.tv/pic/user/l/b.jpg')"></span>
  <a href="/user/alice" class="l">爱丽丝</a>
  <span class="starlight stars9"></span>
  <div class="comment">神作无疑</div>
</div>
''';
    final comments = BangumiSupport.parseSubjectCommentsHtml(html);
    expect(comments, isNotEmpty);
    expect(comments.first.userName, '爱丽丝');
    expect(comments.first.username, 'alice');
    expect(comments.first.profileUsername, 'alice');
    expect(comments.first.rate, 9);
  });
}
