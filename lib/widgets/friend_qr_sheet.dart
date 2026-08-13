import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../core/network/bangumi_endpoints.dart';
import '../core/social/friend_qr.dart';
import '../core/social/friend_qr_export.dart';
import '../models/bangumi_models.dart';

Future<void> showMyFriendQrSheet(BuildContext context, BangumiUser user) {
  return showFriendQrSheet(context, user, mine: true);
}

Future<void> showFriendQrSheet(
  BuildContext context,
  BangumiUser user, {
  bool mine = false,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => _FriendQrSheet(user: user, mine: mine),
  );
}

class _FriendQrSheet extends StatefulWidget {
  const _FriendQrSheet({required this.user, this.mine = false});

  final BangumiUser user;
  final bool mine;

  @override
  State<_FriendQrSheet> createState() => _FriendQrSheetState();
}

class _FriendQrSheetState extends State<_FriendQrSheet> {
  final _boundaryKey = GlobalKey();
  bool _busy = false;

  Future<void> _save() async {
    final file = await _exportPng();
    if (file == null || !mounted) return;
    final path = file.path;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('已保存：$path'),
          action: SnackBarAction(
            label: '打开位置',
            onPressed: () => FriendQrExporter.revealInFileManager(path),
          ),
        ),
      );
  }

  Future<void> _share() async {
    final file = await _exportPng();
    if (file == null || !mounted) return;
    await Share.shareXFiles([
      XFile(file.path, mimeType: 'image/png'),
    ], text: '用 MuBangumi 扫描添加 @${widget.user.username}');
  }

  Future<File?> _exportPng() async {
    if (_busy) return null;
    setState(() => _busy = true);
    try {
      await Future<void>.delayed(const Duration(milliseconds: 16));
      if (!mounted) return null;
      final bytes = await FriendQrExporter.captureBoundary(_boundaryKey);
      return FriendQrExporter.savePng(
        username: widget.user.username,
        bytes: bytes,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(error.toString().replaceFirst('Exception: ', '')),
            ),
          );
      }
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = widget.mine ? '我的二维码' : '${widget.user.displayName} 的二维码';
    final hint = widget.mine ? '仅限 MuBangumi 扫描添加好友' : '把这个码给别人扫描，即可推荐添加';
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              hint,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            RepaintBoundary(
              key: _boundaryKey,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      QrImageView(
                        data: FriendQr.encode(widget.user.username),
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
                      const SizedBox(height: 12),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFFFFD6E4),
                          backgroundImage: widget.user.avatarUrl.isEmpty
                              ? null
                              : CachedNetworkImageProvider(
                                  BangumiEndpoints.imageUrl(
                                    widget.user.avatarUrl,
                                  ),
                                ),
                          child: widget.user.avatarUrl.isEmpty
                              ? Text(
                                  widget.user.displayName.characters.first
                                      .toUpperCase(),
                                  style: const TextStyle(color: Colors.black87),
                                )
                              : null,
                        ),
                        title: Text(
                          widget.user.displayName,
                          style: const TextStyle(color: Colors.black87),
                        ),
                        subtitle: Text(
                          '@${widget.user.username}',
                          style: const TextStyle(color: Colors.black54),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _save,
                    icon: _busy
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download_rounded),
                    label: const Text('保存图片'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _share,
                    icon: const Icon(Icons.ios_share_rounded),
                    label: const Text('分享'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
