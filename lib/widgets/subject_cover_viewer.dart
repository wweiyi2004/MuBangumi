import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../core/network/bangumi_endpoints.dart';
import '../core/sharing/cover_image_exporter.dart';
import '../core/theme/anime_icon.dart';
import '../models/bangumi_models.dart';

Future<void> showSubjectCover(
  BuildContext context,
  Subject subject, {
  bool saveOnOpen = false,
}) => showDialog<void>(
  context: context,
  builder: (_) => SubjectCoverViewer(subject: subject, saveOnOpen: saveOnOpen),
);

class SubjectCoverViewer extends StatefulWidget {
  const SubjectCoverViewer({
    super.key,
    required this.subject,
    this.saveOnOpen = false,
    this.exporter,
    this.image,
  });
  final Subject subject;
  final bool saveOnOpen;
  final CoverImageExporter? exporter;
  final ImageProvider? image;
  @override
  State<SubjectCoverViewer> createState() => _SubjectCoverViewerState();
}

class _SubjectCoverViewerState extends State<SubjectCoverViewer> {
  bool _saving = false;
  String? _message;
  final _cancel = CancelToken();
  @override
  void initState() {
    super.initState();
    if (widget.saveOnOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _save());
    }
  }

  @override
  void dispose() {
    _cancel.cancel();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !mounted) return;
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      final data = await (widget.exporter ?? CoverImageExporter()).download(
        widget.subject.imageUrl,
        cancelToken: _cancel,
      );
      if (!mounted) return;
      final destination = await FilePicker.platform.saveFile(
        dialogTitle: '收藏这张封面',
        fileName: 'MuBangumi-cover-${widget.subject.id}.${data.extension}',
        type: FileType.custom,
        allowedExtensions: [data.extension],
        bytes: data.bytes,
        lockParentWindow: true,
      );
      if (mounted && destination != null) {
        setState(() => _message = '封面已保存到所选位置');
      }
    } catch (_) {
      if (mounted) setState(() => _message = '封面暂时没能保存，再试一次吧');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: MediaQuery.sizeOf(context).height * .9,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                scheme.primaryContainer.withValues(alpha: .55),
                scheme.surface,
                scheme.secondaryContainer.withValues(alpha: .4),
              ],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    AnimeIcon(
                      Icons.auto_awesome_rounded,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '封面小画廊',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭封面',
                      onPressed: () => Navigator.pop(context),
                      icon: const AnimeIcon(Icons.close_rounded),
                    ),
                  ],
                ),
                Flexible(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: GestureDetector(
                      onLongPress: _save,
                      child: InteractiveViewer(
                        minScale: .8,
                        maxScale: 4,
                        child: widget.image != null
                            ? Image(image: widget.image!, fit: BoxFit.contain)
                            : CachedNetworkImage(
                                imageUrl: BangumiEndpoints.imageUrl(
                                  widget.subject.imageUrl,
                                  size: BangumiImageSize.large,
                                ),
                                memCacheWidth: 1600,
                                fit: BoxFit.contain,
                                placeholder: (_, _) => const SizedBox(
                                  height: 240,
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                ),
                                errorWidget: (_, _, _) => const SizedBox(
                                  height: 200,
                                  child: Center(child: Text('封面暂时走丢了，关闭后再试试')),
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  widget.subject.displayName,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 6),
                Text(
                  _message ?? '双指放大看看 · 长按把喜欢收藏起来',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: _saving ? null : _save,
                  icon: const AnimeIcon(Icons.favorite_border_rounded),
                  label: Text(_saving ? '正在保存…' : '保存封面'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
