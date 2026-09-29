import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/network/bangumi_endpoints.dart';
import '../core/theme/app_tokens.dart';

class MonoProfileHeader extends StatelessWidget {
  const MonoProfileHeader({
    super.key,
    required this.name,
    required this.subtitle,
    required this.imageUrl,
    required this.meta,
    required this.fallbackIcon,
    required this.imageHeight,
    required this.imageRadius,
  });

  final String name;
  final String subtitle;
  final String imageUrl;
  final List<String> meta;
  final IconData fallbackIcon;
  final double imageHeight;
  final BorderRadius imageRadius;

  static const double _imageWidth = 96;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: imageRadius,
              child: SizedBox(
                width: _imageWidth,
                height: imageHeight,
                child: imageUrl.isEmpty
                    ? ColoredBox(
                        color: scheme.surfaceContainerHighest,
                        child: Icon(fallbackIcon, size: 40),
                      )
                    : CachedNetworkImage(
                        imageUrl: BangumiEndpoints.imageUrl(imageUrl),
                        fit: BoxFit.cover,
                        memCacheWidth: (_imageWidth * 2).round(),
                        memCacheHeight: (imageHeight * 2).round(),
                        errorWidget: (_, _, _) => ColoredBox(
                          color: scheme.surfaceContainerHighest,
                          child: const Icon(Icons.broken_image_outlined),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: Theme.of(context).textTheme.headlineSmall),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ],
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final item in meta)
                          Chip(
                            label: Text(item),
                            visualDensity: VisualDensity.compact,
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MonoThumb extends StatelessWidget {
  const MonoThumb({
    super.key,
    required this.url,
    this.round = false,
    this.roundFallbackIcon = Icons.person_rounded,
  });

  final String url;
  final bool round;
  final IconData roundFallbackIcon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final child = url.isEmpty
        ? ColoredBox(
            color: scheme.surfaceContainerHighest,
            child: Icon(
              round ? roundFallbackIcon : Icons.movie_filter_outlined,
              size: 20,
            ),
          )
        : CachedNetworkImage(
            imageUrl: BangumiEndpoints.imageUrl(url),
            fit: BoxFit.cover,
            memCacheWidth: 96,
            memCacheHeight: 96,
            errorWidget: (_, _, _) => ColoredBox(
              color: scheme.surfaceContainerHighest,
              child: const Icon(Icons.broken_image_outlined, size: 18),
            ),
          );
    if (round) {
      return CircleAvatar(
        radius: 22,
        backgroundColor: scheme.surfaceContainerHighest,
        child: ClipOval(child: SizedBox(width: 44, height: 44, child: child)),
      );
    }
    return ClipRRect(
      borderRadius: AppRadius.small,
      child: SizedBox(width: 44, height: 60, child: child),
    );
  }
}
