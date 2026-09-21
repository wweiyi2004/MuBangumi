import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import '../../models/pm_models.dart';

class PmHtmlParser {
  /// Only inspect the site's own account navigation, never a message author.
  String? parseSignedInUser(String source) =>
      _signedInUser(html_parser.parse(source));

  String? _signedInUser(Document document) {
    final links = document.querySelectorAll(
      '#headerNeue2 > div > .idBadgerNeue a.avatar[href], #badgeUserPanel a.avatar[href], #dock a[href]',
    );
    final ids = <String>{};
    for (final link in links) {
      final uri = Uri.tryParse(link.attributes['href'] ?? '');
      if (uri == null ||
          (uri.hasScheme && !const ['http', 'https'].contains(uri.scheme))) {
        continue;
      }
      if (uri.hasAuthority &&
          !const [
            'bgm.tv',
            'bangumi.tv',
            'chii.in',
          ].contains(uri.host.toLowerCase())) {
        continue;
      }
      if (uri.pathSegments.length >= 2 &&
          uri.pathSegments.first == 'user' &&
          uri.pathSegments[1].isNotEmpty) {
        ids.add(uri.pathSegments[1]);
      }
    }
    return ids.length == 1 ? ids.single : null;
  }

  static final _bgUrl = RegExp(
    r'''url\((?:['"])?([^)'";]+)''',
    caseSensitive: false,
  );
  static final _conversationId = RegExp(r'/conversation/(\d+)');
  static final _threadId = RegExp(r'thread=(\d+)');

  /// Notice markers that identify an error even when the text also contains
  /// the word "成功" (e.g. "发送未成功，请稍后重试").
  static final _failureNotice = RegExp(
    r'失败|未成功|不成功|错误|无效|过期|重试|无法|不能|请勿|禁止|拒绝|\berror\b|\bfailed\b|\bfail\b',
    caseSensitive: false,
  );

  bool looksLikeLoginPage(String source) {
    final document = html_parser.parse(source);
    if (_signedInUser(document) != null) return false;
    // A message may discuss login or quote HTML. Only actual site forms and
    // account notices establish a lost session, never arbitrary body text.
    for (final form in document.querySelectorAll('form')) {
      final action = Uri.tryParse(
        form.attributes['action'] ?? '',
      )?.path.toLowerCase();
      final loginForm =
          form.id.toLowerCase() == 'loginform' ||
          action == '/login' ||
          action == '/followtherabbit';
      if (loginForm &&
          form.querySelector(
                'input[type="password"], input[name="password"]',
              ) !=
              null) {
        return true;
      }
    }
    if (document.querySelector(
          '#headerNeue2 .idBadgerNeue > .guest, #badgeUserPanel .guest',
        ) !=
        null) {
      return true;
    }
    return document
        .querySelectorAll('#colunmNotice, #columnNotice, .errorMessage')
        .any((notice) => notice.text.contains('请先登录'));
  }

  /// Returns a user-facing website error from a PM form response, if present.
  String? parseSubmissionError(String source) {
    for (final text in _submissionNotices(source)) {
      // Failure markers take priority: texts like "发送未成功，请稍后重试"
      // contain "成功" but must still be reported as errors.
      if (_failureNotice.hasMatch(text)) return text;
    }
    return null;
  }

  Iterable<String> _submissionNotices(String source) => html_parser
      .parse(source)
      .querySelectorAll(
        '#colunmNotice .text, #columnNotice .text, .errorMessage, .alert-error, .alert-danger, .message.error',
      )
      .map((notice) => notice.text.replaceAll(RegExp(r'\s+'), ' ').trim())
      .where((text) => text.isNotEmpty);

  bool hasSubmissionSuccess(String source) {
    final notices = _submissionNotices(source).toList();
    if (notices.any(_failureNotice.hasMatch)) return false;
    final receipt = RegExp(
      r'(?:短信|私信|消息).{0,12}已(?:成功)?(?:发送|發送)|(?:发送|發送)成功|\bmessage (?:was |has been )?sent\b',
      caseSensitive: false,
    );
    return notices.any(receipt.hasMatch);
  }

  bool hasSubmissionForm(String source) {
    final document = html_parser.parse(source);
    return document.querySelector('input[name="formhash"]') != null &&
        document.querySelector('textarea[name="msg_body"]') != null;
  }

  /// An empty result needs mailbox chrome; a gateway/error document is not
  /// evidence that the user's conversations have disappeared.
  bool hasMailboxLayout(String source) {
    final document = html_parser.parse(source);
    return document.querySelector('.pm-conversation-list') != null ||
        document.querySelector('table.topic_list') != null ||
        (_signedInUser(document) != null &&
            document.querySelector('a[href="/pm/inbox.chii"]') != null &&
            document.querySelector('a[href="/pm/outbox.chii"]') != null);
  }

  List<PmConversation> parseConversationList(String source) {
    final document = html_parser.parse(source);
    final items = <PmConversation>[];
    for (final row in document.querySelectorAll('a.pm-conversation-item')) {
      final href = row.attributes['href'] ?? '';
      final id = _conversationId.firstMatch(href)?.group(1) ?? '';
      if (id.isEmpty) continue;
      final avatarStyle =
          row.querySelector('.avatarNeue')?.attributes['style'] ?? '';
      final avatar = _bgUrl.firstMatch(avatarStyle)?.group(1) ?? '';
      final name =
          row.querySelector('.pm-conversation-name')?.text.trim() ?? '';
      final time =
          row.querySelector('.pm-conversation-date')?.text.trim() ?? '';
      var rawDesc =
          row.querySelector('.pm-conversation-desc')?.text.trim() ?? '';
      rawDesc = rawDesc.replaceAll(RegExp(r'\s+'), ' ').trim();
      final hasRe = rawDesc.startsWith('Re:');
      final clean = hasRe ? rawDesc.substring(3).trim() : rawDesc;
      var title = clean;
      var preview = clean;
      if (clean.contains(' / ')) {
        final parts = clean.split(' / ');
        title = parts.first.trim();
        preview = parts.skip(1).join(' / ').trim();
      }
      if (hasRe && preview.isNotEmpty) preview = 'Re: $preview';
      final isUnread =
          row.classes.contains('pm_new') ||
          row.querySelector('.pm_new') != null ||
          row.querySelector('.pm-conversation-unread') != null;
      final userId = _avatarUserId(avatar);
      items.add(
        PmConversation(
          id: id,
          title: title.isEmpty ? (name.isEmpty ? '会话 $id' : name) : title,
          preview: preview,
          peerName: name,
          peerUserId: userId,
          avatarUrl: _absolute(avatar),
          timeText: time,
          isUnread: isUnread,
        ),
      );
    }

    // Legacy table layout fallback.
    if (items.isEmpty) {
      for (final row in document.querySelectorAll(
        'table.topic_list > tbody > tr',
      )) {
        final avatar = row.querySelector('a.avatar');
        final href = avatar?.attributes['href'] ?? '';
        final id =
            _conversationId.firstMatch(href)?.group(1) ??
            RegExp(r'/view/(\d+)').firstMatch(href)?.group(1) ??
            '';
        if (id.isEmpty) continue;
        final user = row.querySelector('small.sub_title > a');
        final title =
            row.querySelector('a.l')?.text.trim() ??
            row.querySelector('td a')?.text.trim() ??
            '';
        items.add(
          PmConversation(
            id: id,
            title: title.isEmpty ? '会话 $id' : title,
            preview: '',
            peerName: user?.text.trim() ?? '',
            peerUserId: (user?.attributes['href'] ?? '').replaceAll(
              '/user/',
              '',
            ),
            avatarUrl: _backgroundUrl(row.querySelector('.avatarNeue')),
            timeText: row.querySelector('small.time')?.text.trim() ?? '',
            isUnread: row.querySelector('td.pm_new') != null,
          ),
        );
      }
    }
    return items;
  }

  PmConversationDetail parseConversationDetail(String source) {
    final document = html_parser.parse(source);
    final titleStrong = document.querySelector('.pm-chat-title strong a.l');
    final peerName = titleStrong?.text.trim() ?? '';
    final peerUserId = (titleStrong?.attributes['href'] ?? '').replaceAll(
      '/user/',
      '',
    );

    final threads = <PmThreadFilter>[];
    for (final a in document.querySelectorAll('.pm-thread-filter a')) {
      final href = a.attributes['href'] ?? '';
      final id = _threadId.firstMatch(href)?.group(1) ?? '';
      final title = a.text.trim();
      if (id.isEmpty && title.isEmpty) continue;
      threads.add(
        PmThreadFilter(
          id: id,
          title: title,
          current: a.classes.contains('focus'),
        ),
      );
    }
    final titleToId = {
      for (final t in threads)
        if (t.title.isNotEmpty) t.title: t.id,
    };

    var currentThreadId = '';
    final messages = <PmMessage>[];
    final listRoot = document.querySelector('div.pm-message-list');
    final children = listRoot?.children ?? const <Element>[];
    for (final el in children) {
      if (el.classes.contains('pm-thread-label')) {
        final label = el.text.trim();
        currentThreadId = titleToId[label] ?? '';
        continue;
      }
      if (!el.classes.contains('pm-message')) continue;
      final avatarStyle =
          el.querySelector('span.avatarNeue')?.attributes['style'] ?? '';
      final avatar = _bgUrl.firstMatch(avatarStyle)?.group(1) ?? '';
      final userHref = el.querySelector('a.avatar')?.attributes['href'] ?? '';
      final userId = userHref.replaceAll('/user/', '');
      final isSelf = el.classes.contains('pm-message-self');
      final body = el.querySelector('div.pm-message-body');
      final time =
          el
              .querySelector('div.pm-message-info small')
              ?.text
              .replaceAll(RegExp(r'\s*/\s*del\s*$'), '')
              .trim() ??
          '';
      messages.add(
        PmMessage(
          name: isSelf ? '我' : (peerName.isEmpty ? userId : peerName),
          userId: userId,
          contentHtml: body?.innerHtml ?? body?.text ?? '',
          timeText: time,
          avatarUrl: _absolute(avatar),
          isSelf: isSelf,
          threadId: currentThreadId.isEmpty ? null : currentThreadId,
        ),
      );
    }

    // Legacy detail fallback.
    if (messages.isEmpty) {
      for (final item in document.querySelectorAll(
        'div#comment_box > div.item',
      )) {
        final name =
            item.querySelector('div.rr + a.l')?.text.trim() ??
            item.querySelector('a.l')?.text.trim() ??
            '';
        final userId =
            (item.querySelector('a.avatar')?.attributes['href'] ?? '')
                .replaceAll('/user/', '');
        final html = item.querySelector('div.text_pm')?.innerHtml ?? '';
        final parts = html.split('</a>:');
        final content = parts.length > 1
            ? parts.sublist(1).join('</a>:')
            : html;
        messages.add(
          PmMessage(
            name: name,
            userId: userId,
            contentHtml: content,
            timeText: (item.querySelector('small.grey')?.text ?? '')
                .replaceAll(' / del', '')
                .trim(),
            avatarUrl: _backgroundUrl(item.querySelector('span.avatarSize32')),
          ),
        );
      }
    }

    String input(String name) =>
        document.querySelector('input[name=$name]')?.attributes['value'] ?? '';

    return PmConversationDetail(
      messages: messages,
      peerName: peerName,
      peerUserId: peerUserId,
      threads: threads,
      form: PmReplyForm(
        formhash: input('formhash'),
        msgReceivers: input('msg_receivers'),
        related: input('related'),
        msgTitle: input('msg_title'),
        newTopic: () {
          final v = input('new_topic');
          return v.isEmpty ? null : v;
        }(),
      ),
    );
  }

  PmComposeParams parseComposeParams(String source) {
    final document = html_parser.parse(source);
    String input(String name) =>
        document.querySelector('input[name=$name]')?.attributes['value'] ?? '';
    return PmComposeParams(
      formhash: input('formhash'),
      msgReceivers: input('msg_receivers'),
    );
  }

  String _backgroundUrl(Element? el) {
    final style = el?.attributes['style'] ?? '';
    return _absolute(_bgUrl.firstMatch(style)?.group(1) ?? '');
  }

  String _avatarUserId(String avatar) {
    final uri = Uri.tryParse(_absolute(avatar));
    if (uri == null ||
        uri.host.toLowerCase() != 'lain.bgm.tv' ||
        !uri.path.startsWith('/pic/user/')) {
      return '';
    }
    return RegExp(
          r'^(\d+)(?:_[^.]*)?\.(?:jpg|jpeg|png|gif|webp)$',
          caseSensitive: false,
        ).firstMatch(uri.pathSegments.lastOrNull ?? '')?.group(1) ??
        '';
  }

  String _absolute(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return '';
    if (value.startsWith('//')) return 'https:$value';
    if (value.startsWith('http')) return value;
    if (value.startsWith('/')) return 'https://bgm.tv$value';
    return value;
  }
}
