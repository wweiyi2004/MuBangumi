import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/network/bangumi_endpoints.dart';
import '../core/social/friend_qr.dart';
import '../models/bangumi_models.dart';

Future<void> showMyFriendQrSheet(BuildContext context, BangumiUser user) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => _FriendQrSheet(user: user),
  );
}

class _FriendQrSheet extends StatelessWidget {
  const _FriendQrSheet({required this.user});

  final BangumiUser user;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('我的二维码', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              '仅限 MuBangumi 扫描添加好友',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: QrImageView(
                  data: FriendQr.encode(user.username),
                  size: 220,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Colors.black,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: scheme.primaryContainer,
                backgroundImage: user.avatarUrl.isEmpty
                    ? null
                    : CachedNetworkImageProvider(
                        BangumiEndpoints.imageUrl(user.avatarUrl),
                      ),
                child: user.avatarUrl.isEmpty
                    ? Text(user.displayName.characters.first.toUpperCase())
                    : null,
              ),
              title: Text(user.displayName),
              subtitle: Text('@${user.username}'),
            ),
          ],
        ),
      ),
    );
  }
}
