import 'bangumi_models.dart';
import 'pm_models.dart';

class PmContact {
  const PmContact({
    required this.key,
    required this.name,
    required this.username,
    required this.avatarUrl,
    required this.conversations,
    this.friend,
  });
  final String key, name, username, avatarUrl;
  final BangumiUser? friend;
  final List<PmConversation> conversations;
  bool get isFriend => friend != null;
  bool get isUnread => conversations.any((row) => row.isUnread);
  PmConversation? get latest => conversations.firstOrNull;
  bool matches(String query) {
    final term = query.trim().toLowerCase();
    return term.isEmpty ||
        '$name $username ${friend?.id ?? ''}'.toLowerCase().contains(term);
  }
}

/// Names are presentation only; identity comes from UID/username or a known
/// conversation ID. Never join two people just because their nicknames match.
List<PmContact> mergePmContacts(
  List<BangumiUser> friends,
  Iterable<PmConversation> messages, {
  DateTime? now,
}) {
  final clock = now ?? DateTime.now();
  final times = <String, int>{};
  int timestamp(String value) =>
      times.putIfAbsent(value, () => _messageTime(value, clock));
  final aliases = <String, String>{};
  final people = <String, BangumiUser>{};
  for (final friend in friends) {
    final username = friend.username.trim().toLowerCase();
    final key = friend.id > 0 ? 'friend:${friend.id}' : 'friend:$username';
    if (friend.id <= 0 && username.isEmpty) continue;
    people[key] = friend;
    if (friend.id > 0) aliases['${friend.id}'] = key;
    if (username.isNotEmpty) aliases[username] = key;
  }
  final unique = <String, PmConversation>{};
  for (final message in messages) {
    final previous = unique[message.id];
    final latest =
        previous == null ||
            timestamp(message.timeText) > timestamp(previous.timeText)
        ? message
        : previous;
    unique[message.id] = PmConversation(
      id: latest.id,
      title: latest.title,
      preview: latest.preview,
      peerName: latest.peerName,
      peerUserId: latest.peerUserId.isNotEmpty
          ? latest.peerUserId
          : (previous?.peerUserId.isNotEmpty == true
                ? previous!.peerUserId
                : message.peerUserId),
      avatarUrl: latest.avatarUrl.isNotEmpty
          ? latest.avatarUrl
          : (previous?.avatarUrl ?? message.avatarUrl),
      timeText: latest.timeText,
      isUnread: message.isUnread || (previous?.isUnread ?? false),
    );
  }
  final groups = <String, List<PmConversation>>{
    for (final key in people.keys) key: [],
  };
  for (final message in unique.values) {
    final peer = message.peerUserId.trim().toLowerCase();
    final key =
        aliases[peer] ??
        (peer.isEmpty ? 'conversation:${message.id}' : 'peer:$peer');
    groups.putIfAbsent(key, () => []).add(message);
  }
  final result = <PmContact>[];
  for (final entry in groups.entries) {
    final rows = entry.value
      ..sort((a, b) => timestamp(b.timeText).compareTo(timestamp(a.timeText)));
    final friend = people[entry.key];
    result.add(
      PmContact(
        key: entry.key,
        friend: friend,
        name:
            friend?.displayName ??
            (rows.first.peerName.isNotEmpty ? rows.first.peerName : '历史会话'),
        username: friend?.username ?? rows.first.peerUserId,
        avatarUrl: friend?.avatarUrl.isNotEmpty == true
            ? friend!.avatarUrl
            : (rows.firstOrNull?.avatarUrl ?? ''),
        conversations: List.unmodifiable(rows),
      ),
    );
  }
  result.sort((a, b) {
    if (a.isFriend != b.isFriend) return a.isFriend ? -1 : 1;
    if ((a.latest != null) != (b.latest != null)) {
      return a.latest != null ? -1 : 1;
    }
    final time = timestamp(
      b.latest?.timeText ?? '',
    ).compareTo(timestamp(a.latest?.timeText ?? ''));
    if (time != 0) return time;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return result;
}

int _messageTime(String text, DateTime? clock) {
  final now = clock ?? DateTime.now();
  final date = RegExp(r'(\d{4})[-/年](\d{1,2})[-/月](\d{1,2})').firstMatch(text);
  final time = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(text);
  if (date != null) {
    return DateTime(
      int.parse(date[1]!),
      int.parse(date[2]!),
      int.parse(date[3]!),
      time == null ? 0 : int.parse(time[1]!),
      time == null ? 0 : int.parse(time[2]!),
    ).millisecondsSinceEpoch;
  }
  if (time != null || text.contains('今天') || text.contains('昨天')) {
    return DateTime(
      now.year,
      now.month,
      now.day - (text.contains('昨天') ? 1 : 0),
      time == null ? 0 : int.parse(time[1]!),
      time == null ? 0 : int.parse(time[2]!),
    ).millisecondsSinceEpoch;
  }
  return 0;
}
