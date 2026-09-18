import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/network/community_service.dart';
import '../core/social/friend_qr.dart';
import '../core/social/community_qr.dart';
import '../models/bangumi_models.dart';
import '../screens/friend_qr_scan_page.dart';
import '../screens/community_group_screen.dart';
import 'friend_qr_sheet.dart';
import 'subject_widgets.dart';
import 'package:banjian_server/banjian_server.dart';
import '../features/anime_appreciation/room_pages.dart';

bool friendQrSupportsCamera() {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;
}

Future<void> showMyFriendQr(BuildContext context, BangumiUser user) {
  return showFriendQrSheet(context, user, mine: true);
}

Future<void> showFriendQr(BuildContext context, BangumiUser user) {
  return showFriendQrSheet(context, user);
}

Future<bool> scanAndAddFriend(
  BuildContext context, {
  required String myUsername,
  CommunityService? service,
  Future<String?> Function(BuildContext context)? reader,
}) async {
  final backend = service ?? CommunityService.shared;
  final revision = backend.identityRevision;
  final raw = await (reader ?? _readQrPayload)(context);
  if (!context.mounted || raw == null || raw.isEmpty) return false;
  if (revision != backend.identityRevision) return false;

  final room = RoomInvite.parse(raw);
  if (room != null) {
    await openRoomInvite(context, room);
    return false;
  }
  final target = CommunityQr.decode(raw);
  if (target == null) {
    showAppMessage(context, '未识别到好友、小组或番键会二维码');
    return false;
  }
  if (target.kind == CommunityQrKind.group) {
    try {
      final detail = await backend.loadGroupPreview(target.identifier);
      if (!context.mounted || revision != backend.identityRevision) {
        return false;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CommunityGroupScreen(
            group: detail.group,
            initialDetail: detail,
            service: backend,
          ),
        ),
      );
    } catch (error) {
      if (context.mounted) {
        showAppMessage(
          context,
          '无法打开小组：${error.toString().replaceFirst('Exception: ', '')}',
        );
      }
    }
    return false;
  }
  final username = target.identifier;
  if (username.toLowerCase() == myUsername.trim().toLowerCase()) {
    showAppMessage(context, '不能添加自己为好友');
    return false;
  }

  try {
    if (await backend.isFriend(username)) {
      if (context.mounted) showAppMessage(context, '@$username 已经是好友');
      return false;
    }
  } catch (_) {
    // Fall through to the confirm + add path.
  }
  if (!context.mounted || revision != backend.identityRevision) return false;

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
  if (confirmed != true ||
      !context.mounted ||
      revision != backend.identityRevision) {
    return false;
  }

  try {
    await backend.addFriend(username);
    if (context.mounted) showAppMessage(context, '已发送 / 添加好友');
    return true;
  } catch (error) {
    if (context.mounted) {
      showAppMessage(context, error.toString().replaceFirst('Exception: ', ''));
    }
    return false;
  }
}

Future<String?> _readQrPayload(BuildContext context) async {
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
