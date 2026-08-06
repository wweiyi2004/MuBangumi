import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/network/community_service.dart';
import 'package:mubangumi/models/bangumi_models.dart';

void main() {
  test('parses a real episode collection shape', () {
    final item = UserEpisodeCollection.fromJson({
      'type': 2,
      'updated_at': 1700000000,
      'episode': {
        'id': 123,
        'type': 0,
        'ep': 3,
        'sort': 3,
        'name': 'Episode 3',
        'name_cn': '第三话',
        'airdate': '2026-07-18',
        'desc': '',
      },
    });

    expect(item.episode.id, 123);
    expect(item.episode.number, 3);
    expect(item.isWatched, isTrue);
  });

  test('parses subject platform official site and nsfw', () {
    final subject = Subject.fromJson({
      'id': 8,
      'type': 2,
      'name': 'Code Geass R2',
      'name_cn': '反叛的鲁路修R2',
      'platform': 'TV',
      'nsfw': false,
      'meta_tags': ['TV', '日本'],
      'date': '2008-04-06',
      'eps': 25,
      'summary': 'summary',
      'images': {'large': 'https://example.com/c.jpg'},
      'rating': {'score': 8.2, 'total': 10, 'rank': 100, 'count': {}},
      'collection': {},
      'infobox': [
        {'key': '官方网站', 'value': 'http://www.geass.jp/r2/'},
        {'key': '话数', 'value': '25'},
      ],
      'tags': [
        {'name': '机战'},
      ],
    });
    expect(subject.platform, 'TV');
    expect(subject.officialSite, 'http://www.geass.jp/r2/');
    expect(subject.nsfw, isFalse);
    expect(subject.metaTags, contains('TV'));
    expect(subject.tags, contains('机战'));
  });

  test('parses multi-type collections and type-aware labels', () {
    final book = UserCollection.fromJson({
      'subject_id': 123478,
      'subject_type': 1,
      'type': 3,
      'rate': 8,
      'ep_status': 0,
      'vol_status': 2,
      'updated_at': '2025-09-21T00:25:15+08:00',
      'subject': {
        'id': 123478,
        'type': 1,
        'name': 'Book',
        'name_cn': '书籍',
        'eps': 0,
        'volumes': 12,
        'score': 8.5,
      },
    });
    final game = UserCollection.fromJson({
      'subject_id': 548128,
      'subject_type': 4,
      'type': 1,
      'rate': 0,
      'ep_status': 0,
      'vol_status': 0,
      'updated_at': '2026-07-04T14:37:28+08:00',
      'subject': {
        'id': 548128,
        'type': 4,
        'name': 'Game',
        'name_cn': '游戏',
        'eps': 0,
        'volumes': 0,
        'score': 7.9,
      },
    });

    expect(book.subject.type, SubjectType.book);
    expect(book.volumeStatus, 2);
    expect(book.type.labelFor(SubjectType.book), '在读');
    expect(game.subject.type, SubjectType.game);
    expect(game.type.labelFor(SubjectType.game), '想玩');
    expect(CollectionType.done.labelFor(SubjectType.music), '听过');
  });

  test('parses reply ids from html post markers', () {
    expect(CommunityService.parseReplyId('3999409'), 3999409);
    expect(CommunityService.parseReplyId('post_3999409'), 3999409);
    expect(CommunityService.parseReplyId(''), isNull);
  });

  test('parses bangumi user profiles for friends', () {
    final user = BangumiUser.fromJson({
      'id': 7,
      'username': 'sai',
      'nickname': 'Sai',
      'sign': 'hello',
      'avatar': {
        'large': 'https://lain.bgm.tv/pic/user/l/000/00/00/1.jpg',
        'medium': 'https://lain.bgm.tv/pic/user/m/000/00/00/1.jpg',
      },
    });

    expect(user.username, 'sai');
    expect(user.displayName, 'Sai');
    expect(user.avatarUrl, contains('lain.bgm.tv'));
  });
}
