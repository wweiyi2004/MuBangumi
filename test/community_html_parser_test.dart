import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/network/community_html_parser.dart';
import 'package:mubangumi/models/community_models.dart';

void main() {
  final parser = CommunityHtmlParser();

  test(
    'classic subject heading, floor anchors and UTC+8 dates survive fallback',
    () {
      const topic = CommunityTopic(
        kind: CommunityTopicKind.subject,
        title: '分享讨论 #42',
        url: '',
        webUrl: 'https://bgm.tv/subject/topic/42',
      );
      final detail = parser.parseTopicDetail('''
      <h1 class="nameSingle"><a href="/subject/9">作品</a></h1>
      <h1 class="title">实际标题</h1>
      <div class="postTopic" id="post_1">
        <div class="post_actions re_info"><small>#1 - 2026-10-21 18:30</small></div>
        <div class="topic_content">正文</div>
      </div>
      <div class="row_reply" id="post_2">
        <div class="post_actions re_info"><a class="floor-anchor">#2</a> - 2026-10-21 18:31</div>
        <div class="reply_content"><div class="message">回复</div></div>
      </div>''', topic);
      expect(detail.title, '实际标题');
      expect(detail.sourceTitle, '作品');
      expect(detail.sourceUrl, 'https://bgm.tv/subject/9');
      expect(detail.posts.last.meta, '#2 · 2026-10-21 18:31');
      expect(detail.posts.last.createdAt, DateTime.utc(2026, 10, 21, 10, 31));
    },
  );

  test('fallback retains nested OP replies and read-only rich markup', () {
    const topic = CommunityTopic(
      kind: CommunityTopicKind.group,
      title: '旧标题',
      url: '',
      webUrl: 'https://bgm.tv/group/topic/42',
    );
    final detail = parser.parseTopicDetail('''
      <h1><span><a href="/group/demo">小组</a> » 讨论</span><br>新标题</h1>
      <div class="postTopic" id="post_1">
        <div class="topic_content">开头<a href="/subject/9">条目</a><span style="background-color:#555; color:#555">结局</span></div>
        <div class="sub_reply_bg" id="post_2">
          <strong class="userName"><a href="/user/bob">Bob</a></strong>
          <div class="cmt_sub_content">楼主下的回复</div>
        </div>
      </div>''', topic);
    expect(detail.title, '新标题');
    expect(detail.posts.map((p) => p.id), ['post_1', 'post_2']);
    expect(detail.posts.first.htmlBody, contains('background-color:#555'));
    expect(detail.posts.first.canEdit, isFalse);
    expect(detail.posts.first.rawBody, isEmpty);
    expect(detail.posts.last.isNested, isTrue);
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

  test('parseFormhash reads hidden inputs regardless of attribute order', () {
    expect(
      parser.parseFormhash(
        '<input type="hidden" name="formhash" value="41ed512d">',
      ),
      '41ed512d',
    );
    expect(
      parser.parseFormhash(
        '<input type="hidden" name="formhash" id="formhash" value="abc12345">',
      ),
      'abc12345',
    );
    expect(
      parser.parseFormhash(
        "<input type='hidden' value='deadbeef' name='formhash'>",
      ),
      'deadbeef',
    );
  });

  test('parseFormhash falls back to the logout link', () {
    expect(
      parser.parseFormhash('<a href="/logout/41ed512d">登出</a>'),
      '41ed512d',
    );
    expect(
      parser.parseFormhash('<a href="https://bgm.tv/logout/cafebabe99">退出</a>'),
      'cafebabe99',
    );
  });

  test('parseFormhash is null on a logged-out topic page', () {
    expect(
      parser.parseFormhash(
        '<a href="https://bgm.tv/login">登录</a>'
        '<a href="https://bgm.tv/signup">注册</a>'
        '<input id="search_text" name="search_text" type="text">',
      ),
      isNull,
    );
  });
}
