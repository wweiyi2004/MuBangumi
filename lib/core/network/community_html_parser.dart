import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import '../../models/community_models.dart';

class CommunityHtmlParser {
  static final _baseUri = Uri.parse('https://bgm.tv');
  static final _backgroundImage = RegExp(
    r'''background-image\s*:\s*url\((?:['"])?([^)'";]+)''',
    caseSensitive: false,
  );
  static final _replyNumber = RegExp(r'\d+');
  static final _dateTime = RegExp(
    r'\d{4}[-/]\d{1,2}[-/]\d{1,2}\s+\d{1,2}:\d{2}',
  );
  static final _formhashLogout = RegExp(
    r'/logout/([0-9a-f]{8,})\b',
    caseSensitive: false,
  );

  /// The session-wide CSRF token embedded in every classic website page:
  /// a hidden `formhash` input in forms, or the `/logout/{formhash}` link.
  String? parseFormhash(String source) {
    final document = html_parser.parse(source);
    for (final input in document.querySelectorAll('input[name="formhash"]')) {
      final value = input.attributes['value']?.trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    final fromLogout = _formhashLogout.firstMatch(source)?.group(1)?.trim();
    if (fromLogout == null || fromLogout.isEmpty) return null;
    return fromLogout;
  }

  List<CommunityTopic> parseRakuen(String source) {
    final document = html_parser.parse(source);
    final topics = <CommunityTopic>[];
    for (final item in document.querySelectorAll('li.item_list')) {
      final titleLink = item.querySelector('a.title');
      final href = titleLink?.attributes['href'];
      final title = titleLink?.text.trim() ?? '';
      if (href == null || title.isEmpty) continue;

      final id = item.id;
      final kindName = id.startsWith('item_')
          ? id.substring(5).split('_').first
          : '';
      final kind = _kindFromName(kindName);
      final contextLink = item.querySelector('.row a');
      final authorLink = item.querySelector('a.avatar[title]');
      final replyText = item.querySelector('small.grey')?.text ?? '';
      final topicId =
          int.tryParse(
            Uri.parse(href).pathSegments.isEmpty
                ? ''
                : Uri.parse(href).pathSegments.last,
          ) ??
          0;
      topics.add(
        CommunityTopic(
          id: topicId,
          kind: kind,
          title: title,
          url: _absolute(href),
          webUrl: _canonicalTopicUrl(href, kind),
          sourceTitle: contextLink?.text.trim() ?? '',
          sourceUrl: _absolute(contextLink?.attributes['href']),
          author: authorLink?.attributes['title']?.trim() ?? '',
          avatarUrl: _backgroundUrl(item.querySelector('.avatarNeue')),
          replyCount:
              int.tryParse(
                _replyNumber.firstMatch(replyText)?.group(0) ?? '',
              ) ??
              0,
          updatedText: item.querySelector('.time')?.text.trim() ?? '',
        ),
      );
    }
    return topics;
  }

  CommunityLanding parseGroupLanding(String source) {
    final document = html_parser.parse(source);
    final topics = <CommunityTopic>[];
    for (final row in document.querySelectorAll('table.topic_list tr')) {
      final cells = row.querySelectorAll('td');
      if (cells.length < 4) continue;
      final titleLink = cells[0].querySelector('a.l');
      final href = titleLink?.attributes['href'];
      final title = titleLink?.text.trim() ?? '';
      if (href == null || title.isEmpty) continue;
      final groupLink = cells[1].querySelector('a');
      final authorLink = cells[2].querySelector('a');
      final replyText = cells[0].querySelector('small.grey')?.text ?? '';
      final topicId =
          int.tryParse(
            Uri.parse(href).pathSegments.isEmpty
                ? ''
                : Uri.parse(href).pathSegments.last,
          ) ??
          0;
      topics.add(
        CommunityTopic(
          id: topicId,
          kind: CommunityTopicKind.group,
          title: title,
          url: _rakuenUrlForGroupTopic(href),
          webUrl: _absolute(href),
          sourceTitle: groupLink?.text.trim() ?? '',
          sourceUrl: _absolute(groupLink?.attributes['href']),
          author: authorLink?.text.trim() ?? '',
          replyCount:
              int.tryParse(
                _replyNumber.firstMatch(replyText)?.group(0) ?? '',
              ) ??
              0,
          updatedText: cells[3].text.trim(),
        ),
      );
    }

    final groups = <CommunityGroup>[];
    final seen = <String>{};
    for (final item in document.querySelectorAll(
      'ul.groupsLarge li, ul.groupsSmall li, #memberGroupList li',
    )) {
      final links = item.querySelectorAll('a[href^="/group/"]');
      Element? link;
      for (final candidate in links) {
        final candidateName = (candidate.attributes['title'] ?? candidate.text)
            .trim();
        if (candidateName.isNotEmpty) {
          link = candidate;
          break;
        }
      }
      final href = link?.attributes['href'];
      if (href == null || !seen.add(href)) continue;
      final name = (link?.attributes['title'] ?? link?.text ?? '').trim();
      if (name.isEmpty) continue;
      groups.add(
        CommunityGroup(
          name: name,
          url: _absolute(href),
          imageUrl: _absolute(item.querySelector('img')?.attributes['src']),
          memberText: item.querySelector('small.feed')?.text.trim() ?? '',
        ),
      );
    }
    return CommunityLanding(topics: topics, groups: groups);
  }

  CommunityTopicDetail parseTopicDetail(String source, CommunityTopic topic) {
    final document = html_parser.parse(source);
    final heading = document.querySelector('h1');
    final contextLink = heading?.querySelector('span a');
    final posts = <CommunityPost>[];

    final original = document.querySelector('.postTopic');
    if (original != null) {
      final body = original.querySelector('.topic_content');
      final post = _parsePost(original, body, isOriginal: true);
      if (post.body.isNotEmpty || post.images.isNotEmpty) posts.add(post);
    } else if (topic.kind == CommunityTopicKind.blog) {
      final body = document.querySelector('#entry_content');
      if (body != null) {
        posts.add(
          CommunityPost(
            id: 'entry',
            author: topic.author,
            avatarUrl: topic.avatarUrl,
            body: _plainText(body),
            images: _images(body),
            isOriginal: true,
          ),
        );
      }
    }

    for (final reply in document.querySelectorAll('.row_reply')) {
      final message = reply.querySelector('.reply_content > .message');
      final body = message ?? reply.querySelector('.reply_content');
      final post = _parsePost(reply, body);
      if (post.body.isNotEmpty || post.images.isNotEmpty) posts.add(post);
      for (final nested in reply.querySelectorAll('.sub_reply_bg')) {
        final nestedBody = nested.querySelector('.cmt_sub_content');
        final nestedPost = _parsePost(nested, nestedBody, isNested: true);
        if (nestedPost.body.isNotEmpty || nestedPost.images.isNotEmpty) {
          posts.add(nestedPost);
        }
      }
    }

    return CommunityTopicDetail(
      title: topic.title,
      sourceTitle: contextLink?.text.trim().isNotEmpty == true
          ? contextLink!.text.trim()
          : topic.sourceTitle,
      sourceUrl: _absolute(contextLink?.attributes['href']).isNotEmpty
          ? _absolute(contextLink?.attributes['href'])
          : topic.sourceUrl,
      posts: posts,
    );
  }

  CommunityPost _parsePost(
    Element container,
    Element? body, {
    bool isOriginal = false,
    bool isNested = false,
  }) {
    final authorLink = isNested
        ? container.querySelector('strong.userName a')
        : container.querySelector('strong a.l');
    final actionText = container.querySelector('.post_actions.re_info')?.text;
    final date = _dateTime.firstMatch(actionText ?? '')?.group(0) ?? '';
    final floor =
        container.attributes['name']?.replaceFirst('floor-', '') ?? '';
    final meta = [
      if (floor.isNotEmpty) '#$floor',
      if (date.isNotEmpty) date,
    ].join(' · ');
    return CommunityPost(
      id: container.id,
      author:
          authorLink?.text.trim() ??
          container.attributes['data-item-user'] ??
          '',
      userUrl: _absolute(authorLink?.attributes['href']),
      avatarUrl: _backgroundUrl(container.querySelector('.avatarNeue')),
      body: body == null ? '' : _plainText(body),
      images: body == null ? const [] : _images(body),
      meta: meta,
      isOriginal: isOriginal,
      isNested: isNested,
    );
  }

  CommunityTopicKind _kindFromName(String value) => switch (value) {
    'group' => CommunityTopicKind.group,
    'subject' => CommunityTopicKind.subject,
    'ep' => CommunityTopicKind.episode,
    'crt' => CommunityTopicKind.character,
    'prsn' => CommunityTopicKind.person,
    'blog' => CommunityTopicKind.blog,
    _ => CommunityTopicKind.unknown,
  };

  String _canonicalTopicUrl(String href, CommunityTopicKind kind) {
    final uri = Uri.parse(_absolute(href));
    final parts = uri.pathSegments;
    if (parts.length < 4 || parts.first != 'rakuen') return uri.toString();
    final id = parts.last;
    final path = switch (kind) {
      CommunityTopicKind.group => '/group/topic/$id',
      CommunityTopicKind.subject => '/subject/topic/$id',
      CommunityTopicKind.episode => '/ep/$id',
      CommunityTopicKind.character => '/character/$id',
      CommunityTopicKind.person => '/person/$id',
      _ => uri.path,
    };
    return _baseUri.resolve(path).toString();
  }

  String _rakuenUrlForGroupTopic(String href) {
    final id = Uri.parse(href).pathSegments.last;
    return _baseUri.resolve('/rakuen/topic/group/$id').toString();
  }

  String _backgroundUrl(Element? element) {
    final style = element?.attributes['style'] ?? '';
    return _absolute(_backgroundImage.firstMatch(style)?.group(1));
  }

  List<String> _images(Element body) => body
      .querySelectorAll('img')
      .where((image) => !image.classes.contains('smile'))
      .map((image) => _absolute(image.attributes['src']))
      .where((url) => url.isNotEmpty)
      .toSet()
      .toList();

  String _plainText(Element element) {
    final buffer = StringBuffer();

    void appendBreak() {
      if (buffer.isNotEmpty && !buffer.toString().endsWith('\n')) {
        buffer.write('\n');
      }
    }

    void visit(Node node) {
      if (node is Text) {
        buffer.write(node.data);
        return;
      }
      if (node is! Element) return;
      final tag = node.localName;
      if (tag == 'br') {
        appendBreak();
        return;
      }
      if (tag == 'img') {
        final alt = node.attributes['alt']?.trim() ?? '';
        if (alt.isNotEmpty) buffer.write(alt);
        return;
      }
      final block = const {
        'p',
        'div',
        'li',
        'blockquote',
        'pre',
        'h1',
        'h2',
        'h3',
        'hr',
      }.contains(tag);
      if (block) appendBreak();
      for (final child in node.nodes) {
        visit(child);
      }
      if (block) appendBreak();
    }

    for (final node in element.nodes) {
      visit(node);
    }
    return buffer
        .toString()
        .replaceAll('\u00a0', ' ')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r' *\n *'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  String _absolute(String? value) {
    if (value == null || value.trim().isEmpty) return '';
    final url = value.trim();
    if (url.startsWith('//')) return 'https:$url';
    return _baseUri.resolve(url).toString();
  }
}
