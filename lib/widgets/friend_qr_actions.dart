import 'qr_payload_reader.dart';
export 'qr_payload_reader.dart';
import '../state/service_providers.dart';
import '../navigation/app_destination.dart';

import 'package:flutter/material.dart';

import '../core/network/community_service.dart';
import '../core/social/community_qr.dart';
import '../core/shortcuts/shared_bangumi_link.dart';
import '../models/bangumi_models.dart';
import '../screens/config_transfer_page.dart';
import '../core/sharing/config_transfer.dart';
import 'friend_qr_sheet.dart';
import 'subject_widgets.dart';
import 'package:banjian_server/banjian_server.dart';
import '../features/anime_appreciation/room_pages.dart';

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
  final backend = service ?? communityServiceFor(context);
  final revision = backend.identityRevision;
  final raw = await (reader ?? readBangumiQrPayload)(context);
  if (!context.mounted || raw == null || raw.isEmpty) return false;
  if (revision != backend.identityRevision) return false;

  if (raw.trim().startsWith(configQrPrefix)) {
    try {
      ConfigInvitation.parse(raw.trim());
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ConfigTransferPage(invitation: raw.trim()),
        ),
      );
    } catch (error) {
      if (context.mounted) {
        showAppMessage(context, '$error'.replaceFirst('FormatException: ', ''));
      }
    }
    return false;
  }

  final shared = SharedBangumiLink.parse(raw.trim());
  if (shared != null) {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => SharedLinkRoute(link: shared)),
    );
    return false;
  }

  final room = RoomInvite.parse(raw);
  if (room != null) {
    await openRoomInvite(context, room);
    return false;
  }
  final target = CommunityQr.decode(raw);
  if (target == null) {
    showAppMessage(context, '未识别到条目、动态、好友、小组或番键会二维码');
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
          builder: (_) => GroupRoute(
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
