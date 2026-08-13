import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class FriendQrExporter {
  FriendQrExporter._();

  static Future<File> savePng({
    required String username,
    required Uint8List bytes,
    Directory? directory,
  }) async {
    final dir = directory ?? await exportDirectory();
    await dir.create(recursive: true);
    final now = DateTime.now();
    final stamp =
        '${now.year}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';
    final safe = username
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(' ', '');
    final file = File(p.join(dir.path, 'MuBangumi_friend_${safe}_$stamp.png'));
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  static Future<Directory> exportDirectory() async {
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

  static Future<Uint8List> captureBoundary(
    GlobalKey key, {
    double pixelRatio = 3,
  }) async {
    final context = key.currentContext;
    if (context == null || !context.mounted) {
      throw StateError('二维码尚未完成布局，请稍后重试');
    }
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) {
      throw StateError('找不到可保存的二维码区域');
    }
    if (!renderObject.hasSize || renderObject.size.isEmpty) {
      throw StateError('二维码尺寸无效');
    }
    final image = await renderObject.toImage(pixelRatio: pixelRatio);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('PNG 编码失败');
      return data.buffer.asUint8List();
    } finally {
      image.dispose();
    }
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
    } catch (_) {}
  }
}
