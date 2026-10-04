import '../core/theme/anime_icon.dart';
import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../core/network/bangumi_endpoints.dart';
import '../core/sharing/share_content.dart';
import '../core/social/friend_qr_export.dart';
import 'content_share_card.dart';
import 'bounded_image.dart';

Future<void> showContentShareSheet(
  BuildContext context,
  ShareContent content,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  useSafeArea: true,
  constraints: const BoxConstraints(maxWidth: 640),
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
  ),
  builder: (_) => ContentShareSheet(content: content),
);

class ContentShareSheet extends StatefulWidget {
  const ContentShareSheet({super.key, required this.content});
  final ShareContent content;
  @override
  State<ContentShareSheet> createState() => _ContentShareSheetState();
}

class _ContentShareSheetState extends State<ContentShareSheet> {
  final _boundary = GlobalKey();
  ImageProvider? _image;
  bool _loadingCover = false, _coverFailed = false, _busy = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loadingCover &&
        _image == null &&
        !_coverFailed &&
        widget.content.imageUrl.isNotEmpty) {
      unawaited(_loadCover());
    }
  }

  Future<void> _loadCover() async {
    setState(() {
      _loadingCover = true;
      _coverFailed = false;
    });
    final provider = boundedImageProvider(
      CachedNetworkImageProvider(
        BangumiEndpoints.imageUrl(
          widget.content.imageUrl,
          size: BangumiImageSize.large,
        ),
      ),
      width: 512,
      height: 768,
    );
    final stream = provider.resolve(createLocalImageConfiguration(context));
    final ready = Completer<bool>();
    final listener = ImageStreamListener(
      (info, _) {
        if (!ready.isCompleted) ready.complete(true);
        info.dispose();
      },
      onError: (Object error, StackTrace? stack) {
        if (!ready.isCompleted) ready.complete(false);
      },
    );
    stream.addListener(listener);
    try {
      final loaded = await ready.future.timeout(
        const Duration(seconds: 12),
        onTimeout: () => false,
      );
      if (!mounted) return;
      setState(() {
        _image = loaded ? provider : null;
        _coverFailed = !loaded;
      });
    } finally {
      stream.removeListener(listener);
      if (mounted) setState(() => _loadingCover = false);
    }
  }

  Future<void> _perform(String action) async {
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
      if (action == 'copy') {
        await Clipboard.setData(ClipboardData(text: widget.content.linkText));
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('摘要与链接已复制')));
        }
      } else if (action == 'link') {
        await Share.share(
          widget.content.linkText,
          subject: widget.content.title,
          sharePositionOrigin: origin,
        );
      } else {
        final preview = _boundary.currentContext;
        if (preview != null) await Scrollable.ensureVisible(preview);
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
        final bytes = await FriendQrExporter.captureBoundary(
          _boundary,
          pixelRatio: 2,
        );
        if (!mounted) return;
        final filename = 'MuBangumi-${widget.content.fileKey}.png';
        if (action == 'save') {
          final destination = await FilePicker.platform.saveFile(
            dialogTitle: '保存分享卡片',
            fileName: filename,
            type: FileType.custom,
            allowedExtensions: ['png'],
            bytes: bytes,
            lockParentWindow: true,
          );
          if (mounted && destination != null) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('分享卡片已保存到所选位置')));
          }
        } else {
          await Share.shareXFiles(
            [XFile.fromData(bytes, mimeType: 'image/png')],
            fileNameOverrides: [filename],
            text: widget.content.linkText,
            subject: widget.content.title,
            sharePositionOrigin: origin,
          );
        }
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error =
              '分享失败，请重试：${error.toString().replaceFirst('Exception: ', '')}',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _chooseImageAction() async {
    final action = await showDialog<String>(
      context: context,
      builder: (_) =>
          ContentImageActions(content: widget.content, image: _image),
    );
    if (mounted && action != null) await _perform(action);
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      child: SizedBox(
        height: (MediaQuery.sizeOf(context).height * .88).clamp(520.0, 1000.0),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.content.shareTitle,
                      style: Theme.of(context).textTheme.titleLarge,
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
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) => Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: ContentShareCard.width,
                          ),
                          child: AspectRatio(
                            aspectRatio:
                                ContentShareCard.width /
                                widget.content.cardHeight,
                            child: FittedBox(
                              fit: BoxFit.contain,
                              child: RepaintBoundary(
                                key: _boundary,
                                child: ContentShareCard(
                                  content: widget.content,
                                  image: _image,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (_loadingCover)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('正在载入封面…'),
                      ),
                    if (_coverFailed)
                      TextButton(
                        onPressed: _busy ? null : _loadCover,
                        child: const Text('封面暂时无法载入，点击重试；也可保存当前卡片'),
                      ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _perform('copy'),
                    icon: const AnimeIcon(Icons.copy_rounded),
                    label: const Text('复制摘要链接'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _perform('link'),
                    icon: const AnimeIcon(Icons.link_rounded),
                    label: const Text('分享链接'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy || _loadingCover
                        ? null
                        : () => _perform('save'),
                    icon: const AnimeIcon(Icons.download_rounded),
                    label: const Text('保存图片'),
                  ),
                  FilledButton.icon(
                    onPressed: _busy || _loadingCover
                        ? null
                        : _chooseImageAction,
                    icon: const AnimeIcon(Icons.ios_share_rounded),
                    label: Text(_busy ? '处理中…' : '分享图片'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class ContentImageActions extends StatelessWidget {
  const ContentImageActions({super.key, required this.content, this.image});
  final ShareContent content;
  final ImageProvider? image;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  scheme.primaryContainer.withValues(alpha: .55),
                  scheme.surface,
                  scheme.secondaryContainer.withValues(alpha: .35),
                ],
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    AnimeIcon(
                      Icons.favorite_rounded,
                      color: scheme.primary,
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '把喜欢分享出去',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭图片分享',
                      onPressed: () => Navigator.pop(context),
                      icon: const AnimeIcon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 180,
                  child: FittedBox(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: ContentShareCard(content: content, image: image),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  content.title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(context, 'image'),
                  icon: const AnimeIcon(Icons.ios_share_rounded, size: 20),
                  label: const Text('发送到其他应用'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context, 'save'),
                  icon: const AnimeIcon(Icons.download_rounded, size: 20),
                  label: const Text('保存这张卡片'),
                ),
                const SizedBox(height: 8),
                Text(
                  '让今天的小小心动，被更多人看见',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
