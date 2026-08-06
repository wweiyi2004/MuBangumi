import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/network/community_html_parser.dart';
import 'package:mubangumi/models/community_models.dart';

void main() {
  final parser = CommunityHtmlParser();

  test('parses Rakuen topic previews and canonical web URL', () {
    const html = '''
      <ul>
        <li id="item_group_468216" class="item_list">
          <a class="avatar" title="Alice"><span class="avatarNeue"
            style="background-image:url('//lain.bgm.tv/a.jpg')"></span></a>
          <div class="inner">
            <a href="/rakuen/topic/group/468216" class="title">测试话题</a>
            <small class="grey">(+15)</small>
            <span class="row"><a href="/group/test">测试小组</a>
              <small class="time">...2m ago</small></span>
          </div>
        </li>
      </ul>
    ''';

    final topics = parser.parseRakuen(html);

    expect(topics, hasLength(1));
    expect(topics.single.kind, CommunityTopicKind.group);
    expect(topics.single.title, '测试话题');
    expect(topics.single.author, 'Alice');
    expect(topics.single.replyCount, 15);
    expect(topics.single.avatarUrl, 'https://lain.bgm.tv/a.jpg');
    expect(topics.single.webUrl, 'https://bgm.tv/group/topic/468216');
    expect(topics.single.id, 468216);
  });

  test('parses latest topics and group cards', () {
    const html = '''
      <table class="topic_list"><tr>
        <td><a href="/group/topic/12" class="l">一个话题</a>
          <small class="grey">(+3)</small></td>
        <td><a href="/group/demo">示例小组</a></td>
        <td><a href="/user/alice">Alice</a></td>
        <td><small>2026-8-6 12:00</small></td>
      </tr></table>
      <ul class="groupsSmall"><li>
        <a href="/group/demo" class="avatar"><img src="//lain.bgm.tv/g.jpg"></a>
        <div class="inner"><a href="/group/demo">示例小组</a>
          <small class="feed">20 位成员</small></div>
      </li></ul>
    ''';

    final landing = parser.parseGroupLanding(html);

    expect(landing.topics.single.url, 'https://bgm.tv/rakuen/topic/group/12');
    expect(landing.topics.single.id, 12);
    expect(landing.topics.single.author, 'Alice');
    expect(landing.groups.single.name, '示例小组');
    expect(landing.groups.single.memberText, '20 位成员');
  });

  test('parses original post, replies, nested replies and images', () {
    const topic = CommunityTopic(
      kind: CommunityTopicKind.group,
      title: '测试话题',
      url: 'https://bgm.tv/rakuen/topic/group/12',
      webUrl: 'https://bgm.tv/group/topic/12',
    );
    const html = '''
      <h1><span><a href="/group/demo">示例小组</a></span><br>测试话题</h1>
      <div id="post_1" class="postTopic">
        <strong><a class="l" href="/user/alice">Alice</a></strong>
        <div class="topic_content">第一行<br>第二行<img src="/image.jpg"></div>
      </div>
      <div id="post_2" class="row row_reply" name="floor-1">
        <strong><a class="l" href="/user/bob">Bob</a></strong>
        <div class="reply_content"><div class="message">回复正文</div>
          <div class="sub_reply_bg" id="post_3" name="floor-1-1">
            <strong class="userName"><a href="/user/c">Carol</a></strong>
            <div class="cmt_sub_content">嵌套回复</div>
          </div>
        </div>
      </div>
    ''';

    final detail = parser.parseTopicDetail(html, topic);

    expect(detail.sourceTitle, '示例小组');
    expect(detail.posts, hasLength(3));
    expect(detail.posts[0].body, '第一行\n第二行');
    expect(detail.posts[0].images, ['https://bgm.tv/image.jpg']);
    expect(detail.posts[1].body, '回复正文');
    expect(detail.posts[2].author, 'Carol');
    expect(detail.posts[2].isNested, isTrue);
  });
}
