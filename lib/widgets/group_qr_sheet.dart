import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../core/social/community_qr.dart';
import '../core/social/friend_qr_export.dart';
import '../models/community_models.dart';

Future<void> showGroupQr(BuildContext context, CommunityGroup group) async {
  final slug = group.slug.isNotEmpty
      ? group.slug
      : Uri.tryParse(
              group.url,
            )?.pathSegments.where((part) => part.isNotEmpty).lastOrNull ??
            '';
  try {
    CommunityQr.groupUrl(slug);
  } on FormatException {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('小组地址无效，暂时无法生成二维码')));
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _GroupQrSheet(group: group, slug: slug),
  );
}

class _GroupQrSheet extends StatefulWidget {
  const _GroupQrSheet({required this.group, required this.slug});
  final CommunityGroup group;
  final String slug;
  @override
  State<_GroupQrSheet> createState() => _GroupQrSheetState();
}

class _GroupQrSheetState extends State<_GroupQrSheet> {
  final _boundary = GlobalKey();
  bool _busy = false;
  String get _slug => widget.slug;
  String get _url => CommunityQr.groupUrl(_slug);
  Future<File?> _export() async {
    if (_busy) return null;
    setState(() => _busy = true);
    try {
      final bytes = await FriendQrExporter.captureBoundary(_boundary);
      return await FriendQrExporter.savePng(
        username: _slug,
        bytes: bytes,
        group: true,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('二维码保存失败，请重试')));
      }
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('小组二维码', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('扫码查看小组，再选择是否加入'),
          const SizedBox(height: 18),
          RepaintBoundary(
            key: _boundary,
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  QrImageView(
                    data: _url,
                    size: 220,
                    backgroundColor: Colors.white,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.group.name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Bangumi · $_slug',
                    style: const TextStyle(color: Colors.black54),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: _url));
                  if (context.mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('小组链接已复制')));
                  }
                },
                icon: const Icon(Icons.link),
                label: const Text('复制链接'),
              ),
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () async {
                        final file = await _export();
                        if (file != null && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('已保存：${file.path}')),
                          );
                        }
                      },
                icon: const Icon(Icons.download_outlined),
                label: const Text('保存图片'),
              ),
              FilledButton.icon(
                onPressed: _busy
                    ? null
                    : () async {
                        final file = await _export();
                        if (file != null && context.mounted) {
                          await Share.shareXFiles([
                            XFile(file.path, mimeType: 'image/png'),
                          ], text: '${widget.group.name} · $_url');
                        }
                      },
                icon: const Icon(Icons.share_outlined),
                label: const Text('分享'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
