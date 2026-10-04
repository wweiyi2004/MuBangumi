import 'brand_qr.dart';
import '../core/theme/anime_icon.dart';
import 'package:flutter/material.dart';

import '../core/sharing/share_content.dart';

/// Fixed canvas keeps exports identical across phone and desktop previews.
class ContentShareCard extends StatelessWidget {
  const ContentShareCard({super.key, required this.content, this.image});
  final ShareContent content;
  final ImageProvider? image;
  static const width = 720.0;
  static const ink = Color(0xFF263249);
  static const accent = Color(0xFFF09199);
  static const muted = Color(0xFF758095);

  @override
  Widget build(BuildContext context) => MediaQuery.withNoTextScaling(
    child: DefaultTextStyle(
      style: Theme.of(
        context,
      ).textTheme.bodyMedium!.copyWith(color: ink, fontSize: 18, height: 1.5),
      child: Container(
        width: width,
        height: content.cardHeight,
        padding: const EdgeInsets.all(32),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFF7FA), Color(0xFFFFFFFF), Color(0xFFF0F4FC)],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'M',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'MuBangumi',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                Text(
                  content.isCollection
                      ? '把喜欢写进手账'
                      : content.isTimeline
                      ? '此刻的想法'
                      : '值得相遇的作品',
                  style: const TextStyle(fontSize: 14, color: muted),
                ),
              ],
            ),
            const SizedBox(height: 26),
            Expanded(
              child: content.isCollection
                  ? _collection()
                  : content.isTimeline
                  ? _timeline()
                  : _subject(),
            ),
            const SizedBox(height: 22),
            const Divider(height: 1, color: Color(0xFFE3E7EF)),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '让喜欢被看见',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'MuBangumi 内扫码直达\n系统扫一扫进入下载页',
                        style: TextStyle(color: muted, fontSize: 15),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        content.url,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: const Color(0xFFE3E7EF)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: BrandQr(
                    data: content.qrUrl,
                    size: 112,
                    padding: const EdgeInsets.all(10),
                    backgroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  Widget _cover(double width, double height) => ClipRRect(
    borderRadius: BorderRadius.circular(16),
    child: SizedBox(
      width: width,
      height: height,
      child: image == null
          ? _placeholder()
          : Image(
              image: image!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _placeholder(),
            ),
    ),
  );

  Widget _placeholder() => Container(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFBE8EB), Color(0xFFDCE5F6)],
      ),
    ),
    alignment: Alignment.center,
    child: const AnimeIcon(
      Icons.auto_stories_rounded,
      color: Colors.white,
      size: 64,
    ),
  );

  Widget _subject() => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _cover(216, 324),
      const SizedBox(width: 28),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              content.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                height: 1.25,
              ),
            ),
            if (content.subtitle.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                content.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, color: muted),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              content.detail,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, color: muted),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const AnimeIcon(
                  Icons.star_rounded,
                  size: 26,
                  color: Color(0xFFEBA345),
                ),
                const SizedBox(width: 6),
                Text(
                  content.score?.toStringAsFixed(1) ?? '—',
                  style: const TextStyle(
                    fontSize: 38,
                    height: 1.1,
                    color: accent,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  content.score == null ? '暂无评分' : 'Bangumi 评分',
                  style: const TextStyle(fontSize: 13, color: muted),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _metrics(),
            if (content.excerpt.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                content.excerpt,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, height: 1.6),
              ),
            ],
          ],
        ),
      ),
    ],
  );

  Widget _collection() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        content.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w800,
          height: 1.25,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        '${content.subtitle} · ${content.detail}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 16, color: muted),
      ),
      const SizedBox(height: 24),
      Row(
        children: [
          for (final metric in content.metrics)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    metric.value,
                    style: const TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w800,
                      color: accent,
                    ),
                  ),
                  Text(
                    metric.label,
                    style: const TextStyle(fontSize: 16, color: muted),
                  ),
                ],
              ),
            ),
        ],
      ),
      const SizedBox(height: 24),
      Expanded(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (content.imageUrl.isNotEmpty) ...[
              _cover(132, 186),
              const SizedBox(width: 24),
            ],
            Expanded(
              child: Text(
                content.excerpt,
                maxLines: 7,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 18, height: 1.7),
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _timeline() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        content.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 28,
          height: 1.25,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        content.subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: muted, fontSize: 15),
      ),
      const SizedBox(height: 20),
      Expanded(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (content.imageUrl.isNotEmpty) ...[
              _cover(160, 220),
              const SizedBox(width: 24),
            ],
            Expanded(
              child: Text(
                content.excerpt,
                maxLines: 8,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 22, height: 1.6),
              ),
            ),
          ],
        ),
      ),
      Text(
        content.detail,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: muted, fontSize: 14),
      ),
      const SizedBox(height: 14),
      _metrics(),
    ],
  );

  Widget _metrics() => Row(
    children: [
      for (final metric in content.metrics)
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                metric.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 20,
                  height: 1.3,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                metric.label,
                style: const TextStyle(fontSize: 12, color: muted),
              ),
            ],
          ),
        ),
    ],
  );
}
