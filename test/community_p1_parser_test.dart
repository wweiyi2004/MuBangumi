import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/network/community_p1_parser.dart';
import 'package:mubangumi/models/community_models.dart';

void main() {
  final parser = CommunityP1Parser();

  test('parses group and subject topic pages', () {
    final groupTopics = parser.parseGroupTopics({
      'data': [
        {
          'id': 468224,
          'title': '测试小组话题',
          'replyCount': 11,
          'updatedAt': 1785986029,
          'group': {'id': 364, 'name': 'boring', 'title': '靠谱人生茶话会'},
          'creator': {
            'username': 'alice',
            'nickname': '爱丽丝',
            'avatar': {'small': 'https://lain.bgm.tv/alice.jpg'},
          },
        },
      ],
    });
    final subjectTopics = parser.parseSubjectTopics({
      'data': [
        {
          'id': 34882,
          'title': '测试条目话题',
          'replyCount': 3,
          'updatedAt': 1785985000,
          'subject': {'id': 37785, 'name': '原名', 'nameCN': '中文名'},
          'creator': {'username': 'bob', 'nickname': ''},
        },
      ],
    });

    expect(groupTopics.single.kind, CommunityTopicKind.group);
    expect(groupTopics.single.sourceTitle, '靠谱人生茶话会');
    expect(groupTopics.single.author, '爱丽丝');
    expect(groupTopics.single.replyCount, 11);
    expect(groupTopics.single.webUrl, 'https://bgm.tv/group/topic/468224');
    expect(subjectTopics.single.kind, CommunityTopicKind.subject);
    expect(subjectTopics.single.sourceTitle, '中文名');
    expect(subjectTopics.single.author, 'bob');
    expect(subjectTopics.single.sourceUrl, 'https://bgm.tv/subject/37785');
  });

  test('parses group cards', () {
    final groups = parser.parseGroups({
      'data': [
        {
          'name': 'fillgrids',
          'title': '补旧番',
          'members': 16372,
          'icon': {'small': 'https://lain.bgm.tv/group.jpg'},
        },
      ],
    });

    expect(groups.single.name, '补旧番');
    expect(groups.single.url, 'https://bgm.tv/group/fillgrids');
    expect(groups.single.memberText, '16372 位成员');
    expect(groups.single.imageUrl, 'https://lain.bgm.tv/group.jpg');
  });

  test('parses group detail, membership, members and recent topics', () {
    final detail = parser.parseGroupDetail(
      {
        'id': 7,
        'name': 'demo',
        'title': '示例小组',
        'description': '一起聊天',
        'members': 12,
        'topics': 5,
        'posts': 38,
        'accessible': true,
        'membership': {'joinedAt': 1785980000},
        'icon': {'large': 'https://lain.bgm.tv/group-large.jpg'},
      },
      membersPage: {
        'data': [
          {
            'user': {
              'id': 1,
              'username': 'alice',
              'nickname': '爱丽丝',
              'avatar': {'small': 'https://lain.bgm.tv/alice.jpg'},
            },
          },
        ],
      },
      topicsPage: {
        'data': [
          {
            'id': 99,
            'title': '最近的话题',
            'replyCount': 2,
            'creator': {'username': 'alice', 'nickname': '爱丽丝'},
          },
        ],
      },
    );

    expect(detail.group.slug, 'demo');
    expect(detail.description, '一起聊天');
    expect(detail.isJoined, isTrue);
    expect(detail.members.single.displayName, '爱丽丝');
    expect(detail.recentTopics.single.sourceTitle, '示例小组');
  });

  test('parses status and subject collection timeline items', () {
    final items = parser.parseTimeline([
      {
        'id': 101,
        'cat': 5,
        'type': 1,
        'createdAt': 1785980000,
        'replies': 4,
        'user': {'id': 1, 'username': 'alice', 'nickname': '爱丽丝'},
        'memo': {
          'status': {'tsukkomi': '[b]今天看动画[/b]'},
        },
      },
      {
        'id': 102,
        'cat': 3,
        'type': 10,
        'createdAt': 1785981000,
        'user': {'id': 2, 'username': 'bob', 'nickname': ''},
        'memo': {
          'subject': [
            {
              'comment': '很喜欢',
              'subject': {
                'id': 42,
                'name': 'Example',
                'nameCN': '示例动画',
                'images': {'small': 'https://lain.bgm.tv/subject.jpg'},
              },
            },
          ],
        },
      },
    ]);

    expect(items, hasLength(2));
    expect(items.first.description, '发表了吐槽');
    expect(items.first.content, '今天看动画');
    expect(items.first.replyCount, 4);
    expect(items.last.description, '在看 示例动画');
    expect(items.last.content, '很喜欢');
    expect(items.last.imageUrls, ['https://lain.bgm.tv/subject.jpg']);
  });

  test('parses single and batch episode progress timeline items', () {
    final items = parser.parseTimeline([
      {
        'id': 201,
        'cat': 4,
        'type': 2,
        'createdAt': 1785982000,
        'user': {'id': 1, 'username': 'alice', 'nickname': '爱丽丝'},
        'memo': {
          'progress': {
            'single': {
              'episode': {
                'id': 1704892,
                'subjectID': 569116,
                'sort': 5,
                'type': 0,
                'name': 'TV取材',
                'nameCN': '电视采访',
                'airdate': '2026-08-03',
              },
              'subject': {
                'id': 569116,
                'name': 'ぐらんぶる Season 3',
                'nameCN': '碧蓝之海 第三季',
                'type': 2,
                'rating': {'score': 7.07, 'rank': 2316},
                'images': {'small': 'https://lain.bgm.tv/grand-blue.jpg'},
              },
            },
          },
        },
      },
      {
        'id': 202,
        'cat': 4,
        'type': 0,
        'createdAt': 1785982100,
        'user': {'id': 2, 'username': 'bob', 'nickname': '鲍勃'},
        'memo': {
          'progress': {
            'batch': {
              'epsTotal': '12',
              'volsTotal': '??',
              'epsUpdate': 5,
              'volsUpdate': 0,
              'subject': {
                'id': 583862,
                'name': 'Example',
                'nameCN': '示例动画',
                'type': 2,
              },
            },
          },
        },
      },
    ]);

    expect(items.first.description, '看过 碧蓝之海 第三季 EP.5');
    expect(items.first.progress?.subjectId, 569116);
    expect(items.first.progress?.score, 7.07);
    expect(items.first.progress?.episode?.id, 1704892);
    expect(items.first.progress?.episode?.title, '电视采访');
    expect(items.last.description, '观看 示例动画 的进度到第 5 话');
    expect(items.last.progress?.episodeProgress, 5);
    expect(items.last.progress?.episodeTotal, '12');
  });

  test('parses complete timeline replies and nested replies', () {
    final replies = parser.parseTimelineReplies([
      {
        'id': 230330,
        'mainID': 70972536,
        'creatorID': 428068,
        'relatedID': 0,
        'createdAt': 1785989322,
        'content': '[b]完整正文[/b]\n第二行[img]//lain.bgm.tv/reply.jpg[/img]',
        'state': 0,
        'user': {'id': 428068, 'username': '428068', 'nickname': '回复者'},
        'replies': [
          {
            'id': 230331,
            'mainID': 70972536,
            'creatorID': 7,
            'relatedID': 230330,
            'createdAt': 1785989370,
            'content': '嵌套回复的完整内容',
            'state': 0,
            'user': {'id': 7, 'username': 'nested', 'nickname': '楼中楼'},
          },
        ],
      },
    ]);

    expect(replies.single.content, '完整正文\n第二行');
    expect(replies.single.imageUrls, ['https://lain.bgm.tv/reply.jpg']);
    expect(replies.single.replies.single.content, '嵌套回复的完整内容');
    expect(replies.single.replies.single.relatedId, 230330);
    expect(replies.single.replies.single.user.displayName, '楼中楼');
  });

  test('parses topic body, nested replies, bbcode and images', () {
    const topic = CommunityTopic(
      kind: CommunityTopicKind.group,
      title: '旧标题',
      url: 'https://bgm.tv/rakuen/topic/group/12',
      webUrl: 'https://bgm.tv/group/topic/12',
    );
    final detail = parser.parseTopicDetail({
      'title': '新标题',
      'group': {'id': 1, 'name': 'demo', 'title': '示例小组'},
      'replies': [
        {
          'id': 100,
          'content': '[b]正文[/b]\r\n[img]//lain.bgm.tv/a.jpg[/img]',
          'createdAt': 1785980000,
          'state': 0,
          'creator': {
            'username': 'alice',
            'nickname': 'Alice',
            'avatar': {'small': 'https://lain.bgm.tv/avatar.jpg'},
          },
          'replies': [
            {
              'id': 103,
              'content': '楼主楼下的嵌套回复',
              'createdAt': 1785980500,
              'state': 0,
              'creator': {'username': 'dave', 'nickname': 'Dave'},
            },
          ],
        },
        {
          'id': 101,
          'content': '[url=https://example.com]回复正文[/url]',
          'createdAt': 1785981000,
          'state': 0,
          'creator': {'username': 'bob', 'nickname': 'Bob'},
          'reactions': [
            {
              'value': 54,
              'users': [
                {'id': 7, 'username': 'alice', 'nickname': 'Alice'},
                {'id': 8, 'username': 'bob', 'nickname': 'Bob'},
              ],
            },
          ],
          'replies': [
            {
              'id': 102,
              'content': '',
              'createdAt': 1785982000,
              'state': 6,
              'creator': {'username': 'carol', 'nickname': 'Carol'},
            },
          ],
        },
      ],
    }, topic);

    expect(detail.title, '新标题');
    expect(detail.sourceTitle, '示例小组');
    expect(detail.sourceUrl, 'https://bgm.tv/group/demo');
    expect(detail.posts, hasLength(4));
    expect(detail.posts[0].isOriginal, isTrue);
    expect(detail.posts[0].body, '正文');
    expect(detail.posts[0].images, ['https://lain.bgm.tv/a.jpg']);
    expect(detail.posts[1].isNested, isTrue);
    expect(detail.posts[1].body, '楼主楼下的嵌套回复');
    expect(detail.posts[1].meta, startsWith('楼主-1 · '));
    expect(detail.posts[2].body, '回复正文');
    expect(detail.posts[2].meta, startsWith('#1 · '));
    expect(detail.posts[2].reactions.single.value, 54);
    expect(detail.posts[2].reactions.single.count, 2);
    expect(detail.posts[2].reactions.single.isSelectedBy('ALICE'), isTrue);
    expect(detail.posts[3].isNested, isTrue);
    expect(detail.posts[3].meta, startsWith('#1-1 · '));
    expect(detail.posts[3].body, '（该回复已被删除或不可见）');
  });

  test('keeps user-less timeline items when a fallback user is provided', () {
    // /p1/users/{username}/timeline omits the redundant `user` object;
    // only `uid` identifies the owner. The fallback rebuilds the identity.
    final items = parser.parseTimeline(
      [
        {
          'id': 71228734,
          'uid': 763686,
          'cat': 4,
          'type': 2,
          'createdAt': 1786588552,
          'memo': {
            'progress': {
              'single': {
                'episode': {
                  'id': 1656013,
                  'subjectID': 590353,
                  'sort': 6,
                  'type': 0,
                  'name': '私と一緒に',
                  'nameCN': '和我一起',
                  'airdate': '2026-05-12',
                },
                'subject': {
                  'id': 590353,
                  'name': 'マリッジトキシン',
                  'nameCN': '婚姻剧毒',
                  'type': 2,
                },
              },
            },
          },
        },
      ],
      fallbackUsername: 'wweiyi',
      fallbackNickname: '维依',
    );

    expect(items, hasLength(1));
    expect(items.single.user.id, 763686);
    expect(items.single.user.username, 'wweiyi');
    expect(items.single.user.displayName, '维依');
    expect(
      items.single.user.avatarUrl,
      'https://lain.bgm.tv/pic/user/l/000/76/36/763686.jpg',
    );
    expect(items.single.description, '看过 婚姻剧毒 EP.6');
  });

  test('prefers an explicit fallback avatar over the uid path', () {
    final items = parser.parseTimeline(
      [
        {
          'id': 1,
          'uid': 763686,
          'cat': 5,
          'type': 1,
          'createdAt': 1786588552,
          'memo': {
            'status': {'tsukkomi': '你好'},
          },
        },
      ],
      fallbackUsername: 'alice',
      fallbackAvatarUrl: 'https://lain.bgm.tv/pic/user/l/alice.jpg',
    );

    expect(
      items.single.user.avatarUrl,
      'https://lain.bgm.tv/pic/user/l/alice.jpg',
    );
  });

  test('still drops user-less timeline items without a fallback', () {
    final items = parser.parseTimeline([
      {
        'id': 1,
        'uid': 763686,
        'cat': 4,
        'type': 2,
        'createdAt': 1786588552,
        'memo': <String, dynamic>{},
      },
    ]);

    expect(items, isEmpty);
  });

  test('parses notify list page', () {
    final notices = parser.parseNotices({
      'total': 2,
      'data': [
        {
          'id': 42,
          'type': 4,
          'mainID': 1001,
          'relatedID': 2002,
          'title': '测试话题',
          'unread': true,
          'createdAt': 1785986029,
          'sender': {
            'id': 7,
            'username': 'alice',
            'nickname': '爱丽丝',
            'avatar': {'large': 'https://lain.bgm.tv/alice.jpg'},
          },
        },
        {
          'id': 43,
          'type': 14,
          'mainID': 7,
          'relatedID': 0,
          'title': '爱丽丝',
          'unread': false,
          'createdAt': 1785987000,
          'sender': {'id': 7, 'username': 'alice', 'nickname': '爱丽丝'},
        },
      ],
    });
    expect(notices, hasLength(2));
    expect(notices.first.id, 42);
    expect(notices.first.unread, isTrue);
    expect(notices.first.sender?.username, 'alice');
    expect(notices.first.title, '测试话题');
    expect(notices.first.actionText, '爱丽丝在条目讨论中回复了你');
    expect(notices.first.canLoadReplyContent, isTrue);
    expect(notices.first.webUrl, 'https://bgm.tv/rakuen/topic/subject/1001');
    expect(notices.last.isFriendRequest, isTrue);
    expect(notices.last.showsContextTitle, isFalse);
    expect(notices.last.actionText, '爱丽丝请求与你成为好友');
    expect(notices.last.webUrl, 'https://bgm.tv/user/alice');
  });
}
