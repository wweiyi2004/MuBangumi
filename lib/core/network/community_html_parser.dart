import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import '../../models/community_models.dart';

class CommunityHtmlParser {
  static final _baseUri = Uri.parse('https://bgm.tv');
  static final _backgroundImage = RegExp(
    r'''background-image\s*:\s*url\((?:['"])?([^)'";]+)''',
    caseSensitive: false,
  );
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

  /// The logged-in new-blog form. Field names stay whatever the page emits.
  ({String action, Map<String, String> fields})? parseBlogCreateForm(
    String source,
  ) {
    final document = html_parser.parse(source);
    for (final form in document.querySelectorAll('form')) {
      if (form.querySelector('[name="title"]') == null ||
          form.querySelector('[name="content"]') == null) {
        continue;
      }
      final fields = <String, String>{};
      for (final input in form.querySelectorAll('input, textarea')) {
        final name = input.attributes['name']?.trim() ?? '';
        if (name.isEmpty) continue;
        final type = (input.attributes['type'] ?? '').toLowerCase();
        if (type == 'submit' || type == 'button' || type == 'image') {
          if (name == 'submit' && !fields.containsKey('submit')) {
            fields['submit'] = input.attributes['value'] ?? '提交';
          }
          continue;
        }
        if (type == 'checkbox' || type == 'radio') {
          if (input.attributes.containsKey('checked')) {
            fields[name] = input.attributes['value'] ?? '1';
          }
          continue;
        }
        fields[name] = input.attributes['value'] ?? '';
      }
      final action = form.attributes['action']?.trim() ?? '';
      return (action: action, fields: fields);
    }
    return null;
  }

  CommunityTopicDetail parseTopicDetail(String source, CommunityTopic topic) {
    final document = html_parser.parse(source);
    final heading =
        document.querySelector('h1.title') ?? document.querySelector('h1');
    final contextLink =
        document.querySelector('h1.nameSingle a') ??
        heading?.querySelector('span a');
    final titleHeading = heading?.clone(true);
    for (final context
        in titleHeading?.querySelectorAll('span') ?? <Element>[]) {
      context.remove();
    }
    final title = titleHeading?.text.trim() ?? '';
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
            htmlBody: body.innerHtml,
            images: _images(body),
            isOriginal: true,
          ),
        );
      }
    }

    // Document order includes replies under the original post as well as
    // ordinary floors. Selecting each nested row once avoids duplicates.
    for (final reply in document.querySelectorAll(
      '.row_reply, .sub_reply_bg',
    )) {
      final nested = reply.classes.contains('sub_reply_bg');
      final body = nested
          ? reply.querySelector('.cmt_sub_content')
          : reply.querySelector('.reply_content > .message') ??
                reply.querySelector('.reply_content');
      final content = body?.clone(true);
      for (final child
          in content?.querySelectorAll(
                '.sub_reply_bg, .topic_sub_reply, .likes_grid, .post_actions',
              ) ??
              <Element>[]) {
        child.remove();
      }
      final post = _parsePost(reply, content, isNested: nested);
      if (post.body.isNotEmpty || post.images.isNotEmpty) posts.add(post);
    }

    return CommunityTopicDetail(
      title: title.isEmpty ? topic.title : title,
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
        RegExp(r'#(\d+(?:-\d+)?)').firstMatch(actionText ?? '')?.group(1) ??
        container.attributes['name']?.replaceFirst('floor-', '') ??
        '';
    final parts = RegExp(
      r'\d+',
    ).allMatches(date).map((m) => int.parse(m[0]!)).toList();
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
      htmlBody: body?.innerHtml ?? '',
      images: body == null ? const [] : _images(body),
      meta: meta,
      createdAt: parts.length == 5
          ? DateTime.utc(
              parts[0],
              parts[1],
              parts[2],
              parts[3],
              parts[4],
            ).subtract(const Duration(hours: 8))
          : null,
      isOriginal: isOriginal,
      isNested: isNested,
    );
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
