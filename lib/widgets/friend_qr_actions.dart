import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/network/community_service.dart';
import '../core/social/friend_qr.dart';
import '../models/bangumi_models.dart';
import '../screens/friend_qr_scan_page.dart';
import 'friend_qr_sheet.dart';
import 'subject_widgets.dart';

bool friendQrSupportsCamera() {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;
}

Future<void> showMyFriendQr(BuildContext context, BangumiUser user) {
  return showMyFriendQrSheet(context, user);
}

Future<bool> scanAndAddFriend(
  BuildContext context, {
  required String myUsername,
}) async {
  final raw = await _readQrPayload(context);
  if (!context.mounted || raw == null || raw.isEmpty) return false;

  final username = FriendQr.decode(raw);
  if (username == null) {
    showAppMessage(context, '这不是 MuBangumi 的好友二维码');
    return false;
  }
  if (username.toLowerCase() == myUsername.trim().toLowerCase()) {
    showAppMessage(context, '不能添加自己为好友');
    return false;
  }

  try {
    if (await CommunityService.shared.isFriend(username)) {
      if (context.mounted) showAppMessage(context, '@$username 已经是好友');
      return false;
    }
  } catch (_) {
    // Fall through to the confirm + add path.
  }
  if (!context.mounted) return false;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('加为好友'),
      content: Text('确定添加 @$username 为好友？'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('添加'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return false;

  try {
    await CommunityService.shared.addFriend(username);
    if (context.mounted) showAppMessage(context, '已发送 / 添加好友');
    return true;
  } catch (error) {
    if (context.mounted) {
      showAppMessage(
        context,
        error.toString().replaceFirst('Exception: ', ''),
      );
    }
    return false;
  }
}

Future<String?> _readQrPayload(BuildContext context) async {
  if (friendQrSupportsCamera()) {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const FriendQrScanPage()),
    );
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
  final username = FriendQr.decodeFromImageBytes(bytes);
  if (username == null) {
    if (context.mounted) showAppMessage(context, '没有识别到 MuBangumi 好友二维码');
    return null;
  }
  return FriendQr.encode(username);
}
