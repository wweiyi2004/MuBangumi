import 'package:html/parser.dart' as html;

import '../../models/bangumi_models.dart';
import '../../models/community_models.dart';
import '../shortcuts/shared_bangumi_link.dart';

class ShareMetric {
  const ShareMetric(this.label, this.value);
  final String label, value;
}

/// Public content only. No session, account tokens or private collection data.
class ShareContent {
  const ShareContent({
    required this.title,
    required this.url,
    required this.fileKey,
    this.subtitle = '',
    this.excerpt = '',
    this.imageUrl = '',
    this.detail = '',
    this.score,
    this.metrics = const [],
    this.isTimeline = false,
  });

  final String title, subtitle, excerpt, imageUrl, detail, url, fileKey;
  final double? score;
  final List<ShareMetric> metrics;
  final bool isTimeline;

  factory ShareContent.subject(Subject subject) => ShareContent(
    title: subject.displayName,
    subtitle: subject.name != subject.displayName ? subject.name : '',
    excerpt: plainShareText(subject.summary),
    imageUrl: subject.imageUrl,
    detail: [
      subject.type.label,
      if (subject.platform.isNotEmpty) subject.platform,
      if (subject.date.isNotEmpty) subject.date,
      if (subject.episodeCount > 0) '${subject.episodeCount} 话',
      if (subject.volumeCount > 0) '${subject.volumeCount} 卷',
    ].join(' · '),
    score: subject.score.isFinite && subject.score > 0 ? subject.score : null,
    metrics: [
      ShareMetric('排名', subject.rank > 0 ? '#${subject.rank}' : '暂无'),
      ShareMetric('评分人数', '${subject.ratingTotal}'),
      ShareMetric('收藏人数', '${subject.collectionTotal}'),
    ],
    url: SharedBangumiLink(SharedBangumiKind.subject, subject.id).url,
    fileKey: 'subject-${subject.id}',
  );

  factory ShareContent.timeline(CommunityTimelineItem item) {
    final username =
        item.user.username.isNotEmpty && item.user.username != 'unknown'
        ? item.user.username
        : '${item.user.id}';
    final targets = item.targets;
    final text = plainShareText(
      item.content.isNotEmpty ? item.content : item.rawContent,
    );
    final date = item.createdAt.toLocal();
    return ShareContent(
      title: '${item.user.displayName}的动态',
      subtitle: '@$username',
      excerpt: text.isNotEmpty ? text : plainShareText(item.description),
      imageUrl: targets.isNotEmpty && targets.first.imageUrl.isNotEmpty
          ? targets.first.imageUrl
          : item.imageUrls.isNotEmpty
          ? item.imageUrls.first
          : '',
      detail: [
        '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}',
        if (item.description.isNotEmpty && text.isNotEmpty)
          plainShareText(item.description),
        if (targets.isNotEmpty)
          targets.take(4).map((target) => target.title).join(' / '),
      ].join(' · '),
      metrics: [
        ShareMetric('回复', '${item.replyCount}'),
        ShareMetric(
          '回应',
          '${item.reactions.fold<int>(0, (sum, reaction) => sum + reaction.users.length)}',
        ),
      ],
      url: SharedBangumiLink(
        SharedBangumiKind.timeline,
        item.id,
        username: username,
        isStatus: item.isStatus,
      ).url,
      fileKey: 'timeline-${item.id}',
      isTimeline: true,
    );
  }

  String get linkText => [
    title,
    if (detail.isNotEmpty) detail,
    if (!isTimeline)
      '${score == null ? '暂无评分' : '${score!.toStringAsFixed(1)} 分'} · ${metrics.map((metric) => '${metric.label} ${metric.value}').join(' · ')}',
    if (excerpt.isNotEmpty) shortenShareText(excerpt, 180),
    url,
  ].join('\n');
  String get qrUrl => SharedBangumiLink.parse(url)?.qrUrl ?? url;

  double get cardHeight => isTimeline ? 660 : 720;
}

String plainShareText(String source) {
  final withoutImages = source.replaceAll(
    RegExp(r'\[img[^\]]*\].*?\[/img\]', caseSensitive: false, dotAll: true),
    '',
  );
  return (html
              .parseFragment(
                withoutImages.replaceAll(RegExp(r'\[/?[a-zA-Z][^\]]*\]'), ''),
              )
              .text ??
          '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String shortenShareText(String text, int limit) {
  final runes = text.runes.toList();
  return runes.length <= limit
      ? text
      : '${String.fromCharCodes(runes.take(limit))}…';
}
