import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import '../../models/community_models.dart';

/// Classic timeline HTML is independent of P1's asynchronously updated inbox.
class CommunityTimelineHtmlParser {
  /// The `#timeline` element alone; [parse] accepts it for cached snapshots.
  String extractTimeline(String source) {
    final timeline = html.parse(source).querySelector('#timeline');
    if (timeline == null) {
      throw const FormatException('未能识别网站动态，请稍后重试');
    }
    return timeline.outerHtml;
  }

  CommunityTimelinePageResult parse(
    String source, {
    required int page,
    CommunityUser? owner,
  }) {
    final document = html.parse(source);
    final timeline = document.querySelector('#timeline');
    if (timeline == null) {
      throw const FormatException('未能识别网站动态，请稍后重试');
    }
    final items = <CommunityTimelineItem>[];
    final seen = <int>{};
    // Consecutive events by one user omit the avatar after the first.
    final avatars = <String, String>{};
    for (final row in timeline.querySelectorAll('li[id^="tml_"]')) {
      final id = int.tryParse(row.id.substring(4));
      final info = row.querySelector('.info, .info_full');
      final date =
          row.querySelector('.date .titleTip[title]')?.attributes['title'] ??
          row.querySelector('.date [title]')?.attributes['title'];
      final time = _date(date);
      if (id == null || id <= 0 || info == null || time == null) {
        throw const FormatException('网站动态格式变化，请稍后重试');
      }
      if (!seen.add(id)) continue;
      final author = owner != null
          ? null
          : info.children
                .where(
                  (node) =>
                      node.localName == 'a' && _path(node).startsWith('/user/'),
                )
                .firstOrNull;
      final username = author == null
          ? owner?.username
          : _path(author).split('/').last;
      if (username == null || username.isEmpty) {
        throw const FormatException('无法确认动态所属用户');
      }
      final avatarStyle =
          row.querySelector('.avatarNeue')?.attributes['style'] ?? '';
      final styled = RegExp(
        r'''url\(['"]?([^)'";]+)''',
      ).firstMatch(avatarStyle)?.group(1);
      final avatar = styled == null
          ? avatars[username.toLowerCase()]
          : avatars[username.toLowerCase()] = _url(styled);
      final status = info.querySelector('p.status');
      final comment = info.querySelector('.collectInfo .comment');
      final reply = info.querySelector('.tml_comment');
      final targets = <CommunityTimelineTarget>[];
      final targetKeys = <String>{};
      for (final link in info.querySelectorAll('a[href]')) {
        final match = RegExp(
          r'^/(subject|character|person|blog)/(\d+)$',
        ).firstMatch(_path(link));
        if (match == null || !targetKeys.add(match.group(0)!)) continue;
        final kind = switch (match.group(1)) {
          'character' => CommunityTimelineTargetKind.character,
          'person' => CommunityTimelineTargetKind.person,
          'blog' => CommunityTimelineTargetKind.blog,
          _ => CommunityTimelineTargetKind.subject,
        };
        final card = info
            .querySelectorAll('.card')
            .where(
              (card) => card
                  .querySelectorAll('a[href]')
                  .any((candidate) => _path(candidate) == _path(link)),
            )
            .firstOrNull;
        final titleLink =
            card?.querySelector('.title a') ??
            info
                .querySelectorAll('a[href]')
                .where(
                  (candidate) =>
                      _path(candidate) == _path(link) &&
                      candidate.text.trim().isNotEmpty,
                )
                .firstOrNull ??
            link;
        targets.add(
          CommunityTimelineTarget(
            kind: kind,
            id: int.parse(match.group(2)!),
            title: titleLink.text.trim().isEmpty
                ? '#${match.group(2)}'
                : titleLink.text.trim(),
            imageUrl: _url(
              (card ?? link).querySelector('img')?.attributes['src'],
            ),
          ),
        );
      }
      final description = info.clone(true);
      for (final node in description.querySelectorAll(
        '.card, .collectInfo, .status, .post_actions, .likes_grid',
      )) {
        node.remove();
      }
      if (author != null) {
        description.children
            .firstWhere(
              (node) =>
                  node.localName == 'a' && _path(node).startsWith('/user/'),
            )
            .remove();
      }
      final body = status ?? comment;
      items.add(
        CommunityTimelineItem(
          id: id,
          user: CommunityUser(
            id: int.tryParse(username) ?? owner?.id ?? 0,
            username: username,
            nickname: author?.text.trim() ?? owner?.nickname ?? username,
            avatarUrl: avatar ?? owner?.avatarUrl ?? '',
          ),
          createdAt: time,
          description: _text(description),
          content: body == null ? '' : _text(body),
          imageUrls:
              body
                  ?.querySelectorAll('img:not(.smile)')
                  .map((node) => _url(node.attributes['src']))
                  .where((url) => url.isNotEmpty)
                  .toList() ??
              const [],
          // Renames/signature changes also use p.status but cannot be replied to.
          isStatus: status != null && reply != null,
          replyCount:
              int.tryParse(
                RegExp(r'\d+').firstMatch(reply?.text ?? '')?.group(0) ?? '',
              ) ??
              0,
          targets: targets,
        ),
      );
    }
    final next = timeline
        .querySelectorAll('#tmlPager a[href]')
        .any(
          (link) =>
              int.tryParse(
                Uri.tryParse(
                      link.attributes['href'] ?? '',
                    )?.queryParameters['page'] ??
                    '',
              ) ==
              page + 1,
        );
    return CommunityTimelinePageResult(
      items: items,
      nextPage: next ? page + 1 : null,
    );
  }

  String _path(Element node) =>
      Uri.tryParse(node.attributes['href'] ?? '')?.path ?? '';

  DateTime? _date(String? value) {
    final match = RegExp(
      r'^(\d{4})-(\d{1,2})-(\d{1,2}) (\d{1,2}):(\d{2})$',
    ).firstMatch(value ?? '');
    if (match == null) return null;
    final parts = [
      for (var i = 1; i <= 5; i++) match.group(i)!.padLeft(2, '0'),
    ];
    return DateTime.tryParse(
      '${parts[0]}-${parts[1]}-${parts[2]}T${parts[3]}:${parts[4]}:00+08:00',
    );
  }

  String _url(String? value) {
    if (value == null || value.isEmpty) return '';
    final uri = Uri.parse('https://bgm.tv').resolve(value);
    return const ['http', 'https'].contains(uri.scheme) ? uri.toString() : '';
  }

  String _text(Element node) {
    final copy = node.clone(true);
    for (final br in copy.querySelectorAll('br')) {
      br.replaceWith(Text('\n'));
    }
    for (final image in copy.querySelectorAll('img')) {
      image.replaceWith(Text(image.attributes['alt'] ?? ''));
    }
    return copy.text.replaceAll(RegExp(r'[ \t]+'), ' ').trim();
  }
}
