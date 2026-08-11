import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/network/pm_html_parser.dart';

void main() {
  final parser = PmHtmlParser();

  test('parses conversation list v2 markup', () {
    const html = '''
<div class="pm-conversation-list">
  <a class="pm-conversation-item pm_new" href="/pm/conversation/123.chii">
    <span class="avatarNeue" style="background-image:url('//lain.bgm.tv/pic/user/l/000/01/23/123.jpg')"></span>
    <div class="pm-conversation-name">Alice</div>
    <div class="pm-conversation-date">2026-8-11</div>
    <div class="pm-conversation-desc">Re: 标题 / 预览内容</div>
  </a>
</div>
<div id="pm_pager"></div>
''';
    final list = parser.parseConversationList(html);
    expect(list, hasLength(1));
    expect(list.first.id, '123');
    expect(list.first.peerName, 'Alice');
    expect(list.first.title, '标题');
    expect(list.first.preview, contains('预览内容'));
    expect(list.first.isUnread, isTrue);
    expect(list.first.avatarUrl, contains('lain.bgm.tv'));
  });

  test('parses conversation detail messages and form', () {
    const html = '''
<div class="pm-chat-panel">
  <div class="pm-chat-title"><strong><a class="l" href="/user/bob">Bob</a></strong></div>
  <div class="pm-thread-filter">
    <a class="focus" href="?thread=9">主题A</a>
  </div>
  <div class="pm-message-list">
    <div class="pm-thread-label">主题A</div>
    <div class="pm-message">
      <a class="avatar" href="/user/bob"></a>
      <span class="avatarNeue" style="background-image:url('/img/b.jpg')"></span>
      <div class="pm-message-body">你好<br>世界</div>
      <div class="pm-message-info"><small>昨天 12:00</small></div>
    </div>
    <div class="pm-message pm-message-self">
      <a class="avatar" href="/user/me"></a>
      <div class="pm-message-body">收到</div>
      <div class="pm-message-info"><small>今天 01:00</small></div>
    </div>
  </div>
  <input name="formhash" value="hash1" />
  <input name="msg_receivers" value="42" />
  <input name="related" value="123" />
  <input name="msg_title" value="Re: 标题" />
</div>
<div id="footer"></div>
''';
    final detail = parser.parseConversationDetail(html);
    expect(detail.peerName, 'Bob');
    expect(detail.peerUserId, 'bob');
    expect(detail.messages, hasLength(2));
    expect(detail.messages.first.isSelf, isFalse);
    expect(detail.messages.first.contentText, contains('你好'));
    expect(detail.messages.last.isSelf, isTrue);
    expect(detail.form.formhash, 'hash1');
    expect(detail.form.msgReceivers, '42');
    expect(detail.form.related, '123');
  });

  test('detects login page', () {
    expect(
      parser.looksLikeLoginPage('<form id="loginForm"><input name="password">'),
      isTrue,
    );
    expect(parser.looksLikeLoginPage('<div class="pm-conversation-list">'), isFalse);
    // Bare "guest" chrome must not force an auth wall.
    expect(
      parser.looksLikeLoginPage('<div class="guest-tip">welcome guest</div>'),
      isFalse,
    );
  });
}
