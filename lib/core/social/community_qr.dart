import 'friend_qr.dart';

enum CommunityQrKind { friend, group }

class CommunityQrTarget {
  const CommunityQrTarget(this.kind, this.identifier);
  final CommunityQrKind kind;
  final String identifier;
}

class CommunityQr {
  static final _groupSlug = RegExp(r'^[A-Za-z0-9_][A-Za-z0-9_-]{0,63}$');
  static String groupUrl(String slug) {
    if (!_groupSlug.hasMatch(slug)) throw const FormatException('小组地址无效');
    return 'https://bgm.tv/group/$slug';
  }

  static CommunityQrTarget? decode(String raw) {
    if (raw.length > 2048) return null;
    final friend = FriendQr.decode(raw);
    if (friend != null &&
        friend.length <= 128 &&
        !RegExp(r'[\x00-\x1f/\\]').hasMatch(friend)) {
      return CommunityQrTarget(CommunityQrKind.friend, friend);
    }
    final uri = Uri.tryParse(raw.trim());
    if (uri == null ||
        !const {'http', 'https'}.contains(uri.scheme) ||
        !const {
          'bgm.tv',
          'bangumi.tv',
          'chii.in',
          'www.bgm.tv',
          'www.bangumi.tv',
          'www.chii.in',
        }.contains(uri.host.toLowerCase()) ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort && uri.port != (uri.scheme == 'https' ? 443 : 80)) {
      return null;
    }
    final segments = uri.pathSegments.where((part) => part.isNotEmpty).toList();
    if (segments.length != 2) return null;
    if (segments.first == 'group' && _groupSlug.hasMatch(segments.last)) {
      return CommunityQrTarget(CommunityQrKind.group, segments.last);
    }
    if (segments.first == 'user' && _groupSlug.hasMatch(segments.last)) {
      return CommunityQrTarget(CommunityQrKind.friend, segments.last);
    }
    return null;
  }
}
