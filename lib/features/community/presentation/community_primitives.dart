import '../../../widgets/bounded_image.dart';
import '../../../core/theme/anime_icon.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/format/date_format.dart';
import '../../../core/network/bangumi_endpoints.dart';
import '../../../core/network/bangumi_smiles.dart';

class CommunityAvatar extends StatelessWidget {
  const CommunityAvatar({
    super.key,
    required this.imageUrl,
    this.radius = 22,
    this.fallbackIcon = Icons.person_rounded,
    this.onTap,
  });

  final String imageUrl;
  final double radius;
  final IconData fallbackIcon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final avatar = CircleAvatar(
      radius: radius,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      foregroundImage: imageUrl.isEmpty
          ? null
          : boundedAvatarProvider(context, imageUrl, diameter: radius * 2),
      child: imageUrl.isEmpty ? AnimeIcon(fallbackIcon, size: radius) : null,
    );
    if (onTap == null) return avatar;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: avatar,
      ),
    );
  }
}

class CommunityErrorView extends StatelessWidget {
  const CommunityErrorView({
    super.key,
    required this.message,
    required this.onRetry,
    this.onWebsiteRecovery,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback? onWebsiteRecovery;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimeIcon(
            Icons.cloud_off_rounded,
            size: 44,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 14),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 14),
          FilledButton.tonalIcon(
            onPressed: onRetry,
            icon: const AnimeIcon(Icons.refresh_rounded),
            label: const Text('重试'),
          ),
          if (onWebsiteRecovery != null)
            TextButton.icon(
              onPressed: onWebsiteRecovery,
              icon: const AnimeIcon(Icons.login),
              label: const Text('补充账号验证'),
            ),
        ],
      ),
    ),
  );
}

class CollapsibleCommunityText extends StatefulWidget {
  const CollapsibleCommunityText(
    this.text, {
    super.key,
    this.collapseAfter = 700,
  });

  final String text;
  final int collapseAfter;

  @override
  State<CollapsibleCommunityText> createState() =>
      _CollapsibleCommunityTextState();
}

class _CollapsibleCommunityTextState extends State<CollapsibleCommunityText> {
  bool _expanded = false;

  bool get _isLong =>
      widget.text.length > widget.collapseAfter ||
      '\n'.allMatches(widget.text).length >= 14;

  List<InlineSpan> _spansFor(BuildContext context, String text) {
    final style = DefaultTextStyle.of(context).style;
    final parts = BangumiSmiles.split(text);
    if (parts.every((part) => !part.isImage)) {
      return [TextSpan(text: text, style: style)];
    }
    return [
      for (final part in parts)
        if (part.isImage)
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: Image(
                image: boundedImageProvider(
                  CachedNetworkImageProvider(
                    BangumiEndpoints.imageUrl(part.imageUrl!),
                  ),
                  width: 44,
                  height: 22,
                  pixelRatio: MediaQuery.devicePixelRatioOf(context),
                ),
                height: 22,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => Text(part.text),
              ),
            ),
          )
        else
          TextSpan(text: part.text, style: style),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final collapsed = _isLong && !_expanded;
    final visible = collapsed && widget.text.length > widget.collapseAfter
        ? '${widget.text.substring(0, widget.collapseAfter).trimRight()}…'
        : widget.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectableText.rich(
          TextSpan(children: _spansFor(context, visible)),
          maxLines: collapsed ? 14 : null,
          scrollPhysics: const NeverScrollableScrollPhysics(),
        ),
        if (_isLong)
          TextButton.icon(
            onPressed: () => setState(() => _expanded = !_expanded),
            icon: AnimeIcon(
              _expanded ? Icons.unfold_less_rounded : Icons.unfold_more_rounded,
              size: 17,
            ),
            label: Text(_expanded ? '收起长内容' : '展开全文'),
          ),
      ],
    );
  }
}

class BlockedCommunityContent extends StatefulWidget {
  const BlockedCommunityContent({
    super.key,
    required this.username,
    required this.blocked,
    required this.child,
  });

  final String username;
  final bool blocked;
  final Widget child;

  @override
  State<BlockedCommunityContent> createState() =>
      _BlockedCommunityContentState();
}

class _BlockedCommunityContentState extends State<BlockedCommunityContent> {
  bool _revealed = false;

  @override
  void didUpdateWidget(covariant BlockedCommunityContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.blocked && widget.blocked) _revealed = false;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.blocked || _revealed) return widget.child;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: const AnimeIcon(Icons.visibility_off_outlined),
        title: Text('已折叠 @${widget.username} 的内容'),
        subtitle: const Text('这是本机屏蔽规则，不影响 Bangumi 账号设置'),
        trailing: TextButton(
          onPressed: () => setState(() => _revealed = true),
          child: const Text('临时查看'),
        ),
      ),
    );
  }
}

class CommunityImageStrip extends StatelessWidget {
  const CommunityImageStrip({super.key, required this.urls});

  final List<String> urls;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 112,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: urls.length,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (context, index) => ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: BoundedNetworkImage(
          imageUrl: BangumiEndpoints.imageUrl(urls[index]),
          width: 112,
          height: 112,
          fit: BoxFit.cover,
          errorWidget: (_, _, _) => const SizedBox.square(
            dimension: 112,
            child: AnimeIcon(Icons.broken_image_outlined),
          ),
        ),
      ),
    ),
  );
}

class CommunityMeta extends StatelessWidget {
  const CommunityMeta({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimeIcon(icon, size: 14, color: Theme.of(context).colorScheme.outline),
        const SizedBox(width: 4),
        Text(text, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

class CommunityBadge extends StatelessWidget {
  const CommunityBadge({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(5),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      child: Text(
        label,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onErrorContainer,
          fontSize: 9,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

String communityRelativeTime(DateTime time) {
  final difference = DateTime.now().difference(time);
  if (difference.isNegative || difference.inMinutes < 1) return '刚刚';
  if (difference.inHours < 1) return '${difference.inMinutes} 分钟前';
  if (difference.inDays < 1) return '${difference.inHours} 小时前';
  if (difference.inDays < 30) return '${difference.inDays} 天前';
  return formatDate(time);
}
