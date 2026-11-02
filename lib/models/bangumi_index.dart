import 'bangumi_models.dart';
import 'community_models.dart';

enum BangumiIndexMode { hot, latest, created, collected }

class BangumiIndex {
  const BangumiIndex({
    required this.id,
    required this.ownerId,
    required this.title,
    this.description = '',
    this.isPrivate = false,
    this.total = 0,
    this.collects = 0,
    this.collected = false,
    this.owner,
  });
  final int id, ownerId, total, collects;
  final String title, description;
  final bool isPrivate, collected;
  final CommunityUser? owner;
  factory BangumiIndex.fromJson(Map<String, dynamic> json) {
    final user = json['user'] is Map
        ? Map<String, dynamic>.from(json['user'] as Map)
        : null;
    final avatar = user?['avatar'] is Map ? user!['avatar'] as Map : const {};
    return BangumiIndex(
      id: (json['id'] as num?)?.toInt() ?? 0,
      ownerId: (json['uid'] as num?)?.toInt() ?? 0,
      title: json['title']?.toString() ?? '',
      description: json['desc']?.toString() ?? '',
      isPrivate: json['private'] == true,
      total: (json['total'] as num?)?.toInt() ?? 0,
      collects: (json['collects'] as num?)?.toInt() ?? 0,
      collected: json['collectedAt'] != null,
      owner: user == null
          ? null
          : CommunityUser(
              id: (user['id'] as num?)?.toInt() ?? 0,
              username: user['username']?.toString() ?? '',
              nickname: user['nickname']?.toString() ?? '',
              avatarUrl: avatar['large']?.toString() ?? '',
            ),
    );
  }
}

class BangumiIndexEntry {
  const BangumiIndexEntry({
    required this.id,
    required this.subjectId,
    required this.order,
    this.comment = '',
    this.subject,
  });
  final int id, subjectId, order;
  final String comment;
  final Subject? subject;
  factory BangumiIndexEntry.fromJson(Map<String, dynamic> json) {
    final raw = json['subject'] is Map
        ? Map<String, dynamic>.from(json['subject'] as Map)
        : null;
    return BangumiIndexEntry(
      id: (json['id'] as num?)?.toInt() ?? 0,
      subjectId: (json['sid'] as num?)?.toInt() ?? 0,
      order: (json['order'] as num?)?.toInt() ?? 0,
      comment: json['comment']?.toString() ?? '',
      subject: raw == null
          ? null
          : Subject.fromJson({
              ...raw,
              'name_cn': raw['nameCN'] ?? raw['name_cn'],
            }),
    );
  }
}
