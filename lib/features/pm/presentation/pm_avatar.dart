import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/network/bangumi_endpoints.dart';
import '../../../widgets/social_chat_style.dart';

class PmAvatar extends StatelessWidget {
  const PmAvatar({
    super.key,
    required this.url,
    required this.name,
    this.radius = 22,
  });
  final String url;
  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final resolved = BangumiEndpoints.imageUrl(url);
    final letter = name.trim().isEmpty
        ? '?'
        : name.trim().characters.first.toUpperCase();
    final fallback = ColoredBox(
      color: SocialChatStyle.accent(context).withValues(alpha: .12),
      child: Center(
        child: Text(
          letter,
          style: TextStyle(
            color: SocialChatStyle.accent(context),
            fontSize: radius * .78,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
    return Semantics(
      image: true,
      label: '${name.isEmpty ? '用户' : name}的头像',
      child: ExcludeSemantics(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: SizedBox.square(
            dimension: radius * 2,
            child: resolved.isEmpty
                ? fallback
                : CachedNetworkImage(
                    imageUrl: resolved,
                    fit: BoxFit.cover,
                    placeholder: (_, _) => fallback,
                    errorWidget: (_, _, _) => fallback,
                  ),
          ),
        ),
      ),
    );
  }
}
