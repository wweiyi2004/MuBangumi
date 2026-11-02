import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import '../format/date_format.dart';
import '../sharing/export_files.dart';

class FriendQrExporter {
  FriendQrExporter._();

  static Future<File> savePng({
    required String username,
    required Uint8List bytes,
    Directory? directory,
    bool group = false,
  }) async {
    final dir = directory ?? await ExportFiles.directory();
    await dir.create(recursive: true);
    final now = DateTime.now();
    final stamp = formatFileStamp(now);
    final safe = username
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(' ', '');
    final file = File(
      p.join(
        dir.path,
        'MuBangumi_${group ? 'group' : 'friend'}_${safe}_$stamp.png',
      ),
    );
    await file.writeAsBytes(bytes, flush: true);
    return file;
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
}
