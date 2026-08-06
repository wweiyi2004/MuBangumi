import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/network/bangumi_endpoints.dart';
import '../models/schedule_models.dart';

/// Fixed-width share poster for a local season schedule.
class ScheduleExportPoster extends StatelessWidget {
  const ScheduleExportPoster({
    super.key,
    required this.schedule,
    this.width = 1080,
    this.dark = false,
  });

  final SeasonSchedule schedule;
  final double width;
  final bool dark;

  static const brandPink = Color(0xFFE95383);
  static const brandGold = Color(0xFFF3A646);

  @override
  Widget build(BuildContext context) {
    final bg = dark ? const Color(0xFF12141A) : const Color(0xFFF7F7FA);
    final card = dark ? const Color(0xFF1C1F28) : Colors.white;
    final ink = dark ? const Color(0xFFF2F3F7) : const Color(0xFF1D2433);
    final muted = dark ? const Color(0xFFA0A6B5) : const Color(0xFF6B7280);
    final line = dark ? const Color(0xFF2A2F3C) : const Color(0xFFE5E5EC);
    final headerBg = dark ? const Color(0xFF252A36) : const Color(0xFFF1F1F6);

    final scale = width / 1080.0;
    double s(double v) => v * scale;

    final scheduled = [
      for (var day = DateTime.monday; day <= DateTime.sunday; day++)
        schedule.itemsOn(day),
    ];
    final maxRows = scheduled
        .map((list) => list.length)
        .fold<int>(0, math.max)
        .clamp(1, 12);
    final unscheduled = schedule.unscheduled;
    final total = schedule.items.length;
    final placed = schedule.items.where((e) => e.isScheduled).length;

    final dayColW = (width - s(48) - s(6) * 6) / 7;
    final coverH = dayColW * 1.35;
    final titleH = s(40);
    // cover + title gap + title + vertical padding
    final cellH = coverH + s(6) + titleH + s(16);
    final dayHeaderH = s(48);

    return Container(
      width: width,
      color: bg,
      padding: EdgeInsets.fromLTRB(s(28), s(32), s(28), s(28)),
      child: DefaultTextStyle(
        style: TextStyle(
          color: ink,
          fontFamilyFallback: const [
            'Microsoft YaHei UI',
            'PingFang SC',
            'Noto Sans CJK SC',
            'sans-serif',
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: s(10),
                  height: s(56),
                  decoration: BoxDecoration(
                    color: brandPink,
                    borderRadius: BorderRadius.circular(s(8)),
                  ),
                ),
                SizedBox(width: s(16)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        schedule.season.label,
                        style: TextStyle(
                          fontSize: s(40),
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                          height: 1.1,
                          color: ink,
                        ),
                      ),
                      SizedBox(height: s(6)),
                      Text(
                        '我的追番表 · 共 $total 部 · 已排 $placed 部',
                        style: TextStyle(
                          fontSize: s(20),
                          color: muted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: s(14),
                    vertical: s(8),
                  ),
                  decoration: BoxDecoration(
                    color: brandPink.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(s(999)),
                  ),
                  child: Text(
                    'MuBangumi',
                    style: TextStyle(
                      color: brandPink,
                      fontWeight: FontWeight.w800,
                      fontSize: s(18),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: s(28)),
            Container(
              decoration: BoxDecoration(
                color: card,
                borderRadius: BorderRadius.circular(s(22)),
                border: Border.all(color: line),
                boxShadow: dark
                    ? null
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: s(18),
                          offset: Offset(0, s(6)),
                        ),
                      ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  Container(
                    color: headerBg,
                    height: dayHeaderH,
                    child: Row(
                      children: [
                        for (var day = DateTime.monday;
                            day <= DateTime.sunday;
                            day++)
                          Expanded(
                            child: Container(
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                border: Border(
                                  right: day == DateTime.sunday
                                      ? BorderSide.none
                                      : BorderSide(color: line),
                                ),
                              ),
                              child: Text(
                                weekdayLabel(day),
                                style: TextStyle(
                                  fontSize: s(20),
                                  fontWeight: FontWeight.w800,
                                  color: day == DateTime.now().weekday
                                      ? brandPink
                                      : ink,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  for (var row = 0; row < maxRows; row++)
                    Container(
                      decoration: BoxDecoration(
                        border: Border(top: BorderSide(color: line)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var day = 0; day < 7; day++)
                            Expanded(
                              child: Container(
                                height: cellH,
                                padding: EdgeInsets.fromLTRB(
                                  s(6),
                                  s(8),
                                  s(6),
                                  s(6),
                                ),
                                decoration: BoxDecoration(
                                  border: Border(
                                    right: day == 6
                                        ? BorderSide.none
                                        : BorderSide(color: line),
                                  ),
                                ),
                                child: row < scheduled[day].length
                                    ? _PosterCell(
                                        item: scheduled[day][row],
                                        coverHeight: coverH,
                                        titleHeight: titleH,
                                        scale: scale,
                                        ink: ink,
                                        muted: muted,
                                        placeholder: headerBg,
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            if (unscheduled.isNotEmpty) ...[
              SizedBox(height: s(24)),
              Text(
                '待安排 · ${unscheduled.length}',
                style: TextStyle(
                  fontSize: s(22),
                  fontWeight: FontWeight.w800,
                  color: ink,
                ),
              ),
              SizedBox(height: s(12)),
              Wrap(
                spacing: s(12),
                runSpacing: s(12),
                children: [
                  for (final item in unscheduled.take(18))
                    SizedBox(
                      width: s(150),
                      child: _PosterCell(
                        item: item,
                        coverHeight: s(150) * 1.35,
                        titleHeight: s(40),
                        scale: scale,
                        ink: ink,
                        muted: muted,
                        placeholder: headerBg,
                      ),
                    ),
                  if (unscheduled.length > 18)
                    Container(
                      width: s(150),
                      height: s(150) * 1.35 + s(40),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: card,
                        borderRadius: BorderRadius.circular(s(14)),
                        border: Border.all(color: line),
                      ),
                      child: Text(
                        '+${unscheduled.length - 18}',
                        style: TextStyle(
                          fontSize: s(28),
                          fontWeight: FontWeight.w800,
                          color: muted,
                        ),
                      ),
                    ),
                ],
              ),
            ],
            SizedBox(height: s(28)),
            Row(
              children: [
                Icon(Icons.auto_awesome_rounded, size: s(18), color: brandGold),
                SizedBox(width: s(8)),
                Expanded(
                  child: Text(
                    '由 MuBangumi 导出 · ${_formatDate(DateTime.now())}',
                    style: TextStyle(fontSize: s(16), color: muted),
                  ),
                ),
                Text(
                  'bgm.tv',
                  style: TextStyle(
                    fontSize: s(16),
                    color: muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _formatDate(DateTime date) {
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '${date.year}-$m-$d';
  }
}

class _PosterCell extends StatelessWidget {
  const _PosterCell({
    required this.item,
    required this.coverHeight,
    required this.titleHeight,
    required this.scale,
    required this.ink,
    required this.muted,
    required this.placeholder,
  });

  final ScheduleItem item;
  final double coverHeight;
  final double titleHeight;
  final double scale;
  final Color ink;
  final Color muted;
  final Color placeholder;

  @override
  Widget build(BuildContext context) {
    final url = BangumiEndpoints.imageUrl(item.imageUrl);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10 * scale),
          child: SizedBox(
            height: coverHeight,
            width: double.infinity,
            child: url.isEmpty
                ? ColoredBox(
                    color: placeholder,
                    child: Icon(
                      Icons.movie_filter_outlined,
                      color: muted,
                      size: 28 * scale,
                    ),
                  )
                : CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.cover,
                    fadeInDuration: Duration.zero,
                    fadeOutDuration: Duration.zero,
                    placeholder: (_, _) => ColoredBox(color: placeholder),
                    errorWidget: (_, _, _) => ColoredBox(
                      color: placeholder,
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: muted,
                        size: 24 * scale,
                      ),
                    ),
                  ),
          ),
        ),
        SizedBox(height: 6 * scale),
        SizedBox(
          height: titleHeight,
          child: Text(
            item.displayName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14 * scale,
              height: 1.15,
              fontWeight: FontWeight.w700,
              color: ink,
            ),
          ),
        ),
      ],
    );
  }
}

class ScheduleImageExportResult {
  const ScheduleImageExportResult({
    required this.filePath,
    required this.bytes,
  });

  final String filePath;
  final Uint8List bytes;
}

/// Capture [ScheduleExportPoster] to a PNG file.
class ScheduleImageExporter {
  ScheduleImageExporter._();

  static Future<void> precacheCovers(
    BuildContext context,
    SeasonSchedule schedule,
  ) async {
    final urls = <String>{
      for (final item in schedule.items)
        if (item.imageUrl.trim().isNotEmpty)
          BangumiEndpoints.imageUrl(item.imageUrl),
    };
    if (urls.isEmpty) return;
    await Future.wait([
      for (final url in urls)
        precacheImage(CachedNetworkImageProvider(url), context).catchError(
          (_) {},
        ),
    ]);
  }

  /// Capture an already-mounted [RepaintBoundary] (preferred path).
  ///
  /// Callers that need cover images should precache / wait before invoking.
  static Future<Uint8List> captureBoundary(
    GlobalKey boundaryKey, {
    double pixelRatio = 2.0,
  }) async {
    final boundaryContext = boundaryKey.currentContext;
    if (boundaryContext == null || !boundaryContext.mounted) {
      throw StateError('海报尚未完成布局，请稍后重试');
    }
    final renderObject = boundaryContext.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) {
      throw StateError('找不到可截图的海报区域');
    }
    if (!renderObject.hasSize || renderObject.size.isEmpty) {
      throw StateError('海报尺寸无效（${renderObject.size}）');
    }

    // Avoid huge GPU textures when the week grid is very tall.
    final longest = math.max(renderObject.size.width, renderObject.size.height);
    var ratio = pixelRatio;
    if (longest * ratio > 4096) {
      ratio = 4096 / longest;
    }
    ratio = ratio.clamp(1.0, 3.0);

    final image = await renderObject.toImage(pixelRatio: ratio);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        throw StateError('PNG 编码失败');
      }
      return data.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  static Future<ScheduleImageExportResult> savePngBytes({
    required SeasonSchedule schedule,
    required Uint8List bytes,
  }) async {
    final dir = await _exportDirectory();
    await dir.create(recursive: true);
    final now = DateTime.now();
    final stamp =
        '${now.year}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';
    final safeSeason = schedule.season.label
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(' ', '');
    final file = File(p.join(dir.path, 'MuBangumi_${safeSeason}_$stamp.png'));
    await file.writeAsBytes(bytes, flush: true);
    return ScheduleImageExportResult(filePath: file.path, bytes: bytes);
  }

  static Future<Directory> _exportDirectory() async {
    if (Platform.isAndroid || Platform.isIOS) {
      final docs = await getApplicationDocumentsDirectory();
      return Directory(p.join(docs.path, 'exports'));
    }
    try {
      final downloads = await getDownloadsDirectory();
      if (downloads != null) {
        return Directory(p.join(downloads.path, 'MuBangumi'));
      }
    } catch (_) {}
    final docs = await getApplicationDocumentsDirectory();
    return Directory(p.join(docs.path, 'MuBangumi', 'exports'));
  }

  static Future<void> revealInFileManager(String filePath) async {
    try {
      if (Platform.isWindows) {
        await Process.run('explorer', ['/select,', filePath]);
      } else if (Platform.isMacOS) {
        await Process.run('open', ['-R', filePath]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [p.dirname(filePath)]);
      }
    } catch (_) {
      // Best-effort only.
    }
  }

  static String formatError(Object error) {
    final text = error.toString();
    return text
        .replaceFirst(RegExp(r'^Exception:\s*'), '')
        .replaceFirst(RegExp(r'^Bad state:\s*'), '')
        .replaceFirst(RegExp(r'^StateError:\s*'), '')
        .trim();
  }
}

/// Preview dialog + save action for schedule image export.
Future<void> showScheduleExportDialog(
  BuildContext context, {
  required SeasonSchedule schedule,
}) async {
  if (schedule.items.isEmpty) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('课表是空的，先加几部番再导出吧')));
    return;
  }

  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) => _ScheduleExportDialog(schedule: schedule),
  );
}

class _ScheduleExportDialog extends StatefulWidget {
  const _ScheduleExportDialog({required this.schedule});

  final SeasonSchedule schedule;

  @override
  State<_ScheduleExportDialog> createState() => _ScheduleExportDialogState();
}

class _ScheduleExportDialogState extends State<_ScheduleExportDialog> {
  final GlobalKey _boundaryKey = GlobalKey();
  var _dark = false;
  var _themeReady = false;
  var _exporting = false;
  var _precacheDone = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prepare());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_themeReady) {
      _dark = Theme.of(context).brightness == Brightness.dark;
      _themeReady = true;
    }
  }

  Future<void> _prepare() async {
    if (!mounted) return;
    try {
      await ScheduleImageExporter.precacheCovers(context, widget.schedule);
    } catch (_) {}
    if (!mounted) return;
    setState(() => _precacheDone = true);
    // Extra frame after images land in cache.
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (mounted) setState(() {});
  }

  Future<void> _export() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      // Ensure covers are ready before rasterizing.
      await ScheduleImageExporter.precacheCovers(context, widget.schedule);
      if (!mounted) return;
      // Give CachedNetworkImage one paint pass after cache hits.
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;
      setState(() {}); // force rebuild with cached images
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;

      final bytes = await ScheduleImageExporter.captureBoundary(
        _boundaryKey,
        pixelRatio: 2.0,
      );
      final result = await ScheduleImageExporter.savePngBytes(
        schedule: widget.schedule,
        bytes: bytes,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('已保存：${result.filePath}'),
            action: SnackBarAction(
              label: '打开位置',
              onPressed: () =>
                  ScheduleImageExporter.revealInFileManager(result.filePath),
            ),
            duration: const Duration(seconds: 6),
          ),
        );
    } catch (error, stack) {
      debugPrint('Schedule export failed: $error\n$stack');
      if (!mounted) return;
      setState(() => _exporting = false);
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              '导出失败：${ScheduleImageExporter.formatError(error)}',
            ),
            duration: const Duration(seconds: 6),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context);
    final maxW = math.min(440.0, size.width - 40);
    final maxH = size.height * 0.78;

    return AlertDialog(
      title: const Text('导出追番表图片'),
      content: SizedBox(
        width: maxW,
        height: maxH,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '预览与导出使用同一海报区域，保存为高清 PNG。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('浅色')),
                ButtonSegment(value: true, label: Text('深色')),
              ],
              selected: {_dark},
              onSelectionChanged: _exporting
                  ? null
                  : (value) => setState(() => _dark = value.first),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ColoredBox(
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Scrollable preview of the full-resolution poster.
                      InteractiveViewer(
                        minScale: 0.2,
                        maxScale: 2.5,
                        constrained: false,
                        child: RepaintBoundary(
                          key: _boundaryKey,
                          child: ScheduleExportPoster(
                            schedule: widget.schedule,
                            width: 1080,
                            dark: _dark,
                          ),
                        ),
                      ),
                      if (!_precacheDone || _exporting)
                        ColoredBox(
                          color: Colors.black.withValues(alpha: 0.18),
                          child: Center(
                            child: Card(
                              child: Padding(
                                padding: const EdgeInsets.all(18),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const SizedBox.square(
                                      dimension: 28,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      _exporting ? '正在导出 PNG…' : '加载封面中…',
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _exporting ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          onPressed: (_exporting || !_precacheDone) ? null : _export,
          icon: _exporting
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.download_rounded),
          label: Text(_exporting ? '导出中' : '保存 PNG'),
        ),
      ],
    );
  }
}
