import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../core/social/friend_qr.dart';
import '../screens/friend_qr_scan_page.dart';
import 'subject_widgets.dart';

bool friendQrSupportsCamera() {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;
}

Future<String?> readBangumiQrPayload(BuildContext context) async {
  if (friendQrSupportsCamera()) {
    final result = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const FriendQrScanPage()));
    if (result == null) return null;
    if (result != '__pick_image__') return result;
  }
  if (!context.mounted) return null;
  return _readQrFromPickedImage(context);
}

Future<String?> _readQrFromPickedImage(BuildContext context) async {
  final picked = await FilePicker.platform.pickFiles(
    type: FileType.image,
    allowMultiple: false,
    withData: true,
  );
  if (picked == null || picked.files.isEmpty) return null;
  final file = picked.files.single;
  var bytes = file.bytes;
  if (bytes == null && file.path != null) {
    bytes = await File(file.path!).readAsBytes();
  }
  if (bytes == null) {
    if (context.mounted) showAppMessage(context, '无法读取所选图片');
    return null;
  }
  final raw = await FriendQr.decodePayloadFromImageBytesAsync(bytes);
  if (raw == null) {
    if (context.mounted) showAppMessage(context, '没有识别到二维码');
    return null;
  }
  return raw;
}
