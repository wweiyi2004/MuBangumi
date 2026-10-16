import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

class ImageExport {
  static const channel = MethodChannel('mubangumi/gallery');
  static Future<String?> save(Uint8List bytes, String filename) async {
    if (Platform.isAndroid || Platform.isIOS) {
      return saveToGalleryOrFile(bytes, filename);
    }
    return _saveFile(bytes, filename);
  }

  /// The 4033 native baseline has no gallery method channel. Keep the patch
  /// usable there without changing platform binaries or ignoring permissions.
  static Future<String?> saveToGalleryOrFile(
    Uint8List bytes,
    String filename,
  ) async {
    try {
      return await saveToGallery(bytes, filename);
    } on MissingPluginException {
      return _saveFile(bytes, filename);
    }
  }

  static Future<String?> _saveFile(Uint8List bytes, String filename) async {
    final destination = await FilePicker.platform.saveFile(
      dialogTitle: '保存图片',
      fileName: filename,
      type: FileType.custom,
      allowedExtensions: ['png'],
      bytes: bytes,
      lockParentWindow: true,
    );
    if (destination == null) return null;
    // Desktop file_picker returns a path; it does not write the bytes.
    if (Platform.isAndroid || Platform.isIOS) return '图片已保存到所选位置';
    await File(destination).writeAsBytes(bytes, flush: true);
    return '已保存：$destination';
  }

  static Future<String> saveToGallery(Uint8List bytes, String filename) async {
    final location = await channel.invokeMethod<String>('savePng', {
      'bytes': bytes,
      'name': filename,
    });
    if (location == null || location.isEmpty) throw StateError('相册未返回保存结果');
    return '已保存到系统相册';
  }
}
