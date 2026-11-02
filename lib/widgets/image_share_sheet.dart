import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:share_plus/share_plus.dart';
import '../core/sharing/image_export.dart';
import '../core/social/friend_qr_export.dart';
import '../core/theme/anime_icon.dart';

Future<void> showImageShareSheet(
  BuildContext context, {
  required String title,
  required String filename,
  required Widget child,
  String subtitle = '',
  double width = 960,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  constraints: const BoxConstraints(maxWidth: 640),
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
  ),
  builder: (_) => ImageShareSheet(
    title: title,
    filename: filename,
    subtitle: subtitle,
    width: width,
    child: child,
  ),
);

class ImageShareSheet extends StatefulWidget {
  const ImageShareSheet({
    super.key,
    required this.title,
    required this.filename,
    required this.child,
    this.subtitle = '',
    this.width = 960,
  });
  final String title, filename, subtitle;
  final double width;
  final Widget child;
  @override
  State<ImageShareSheet> createState() => _ImageShareSheetState();
}

class _ImageShareSheetState extends State<ImageShareSheet> {
  final _boundary = GlobalKey();
  bool _busy = false;
  String? _error;
  Future<void> _perform(bool save) async {
    if (_busy) return;
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final bytes = await FriendQrExporter.captureBoundary(
        _boundary,
        pixelRatio: math.min(
          2,
          4096 /
              math.max(
                (_boundary.currentContext!.findRenderObject() as RenderBox)
                    .size
                    .width,
                (_boundary.currentContext!.findRenderObject() as RenderBox)
                    .size
                    .height,
              ),
        ),
      );
      if (!mounted) return;
      if (save) {
        final message = await ImageExport.save(bytes, widget.filename);
        if (mounted && message != null) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(message)));
        }
      } else {
        await Share.shareXFiles(
          [XFile.fromData(bytes, mimeType: 'image/png')],
          fileNameOverrides: [widget.filename],
          subject: widget.title,
          sharePositionOrigin: origin,
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error =
              '图片处理失败，请重试：${error is PlatformException ? error.message : error}',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .84,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '分享图片',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          widget.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭分享',
                    onPressed: _busy ? null : () => Navigator.pop(context),
                    icon: const AnimeIcon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: scheme.shadow.withValues(alpha: .12),
                            blurRadius: 20,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: RepaintBoundary(
                          key: _boundary,
                          child: Container(
                            width: widget.width,
                            padding: const EdgeInsets.all(36),
                            decoration: BoxDecoration(
                              color: scheme.surface,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: scheme.outlineVariant),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'MuBangumi',
                                  style: TextStyle(
                                    color: scheme.primary,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 2,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  widget.title,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                if (widget.subtitle.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(
                                      widget.subtitle,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: scheme.onSurfaceVariant,
                                          ),
                                    ),
                                  ),
                                const SizedBox(height: 24),
                                widget.child,
                                const SizedBox(height: 20),
                                Divider(color: scheme.outlineVariant),
                                Text(
                                  'MuBangumi · ${DateTime.now().year}/${DateTime.now().month}/${DateTime.now().day}',
                                  style: Theme.of(context).textTheme.labelMedium
                                      ?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          _error!,
                          style: TextStyle(color: scheme.error),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _perform(false),
                    icon: const AnimeIcon(Icons.ios_share_rounded),
                    label: Text(_busy ? '正在生成图片…' : '发送到其他应用'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _perform(true),
                    icon: const AnimeIcon(Icons.save_alt_rounded),
                    label: const Text('保存图片'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _busy ? null : () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
