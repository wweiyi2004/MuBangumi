enum RakuenMode {
  subjectTrending('热门', '条目讨论', false),
  subjectLatest('最新', '条目讨论', false),
  groupAll('全部', '小组话题', false),
  groupJoined('参加的', '小组话题', true),
  groupCreated('发表的', '小组话题', true),
  groupReplied('回复的', '小组话题', true);

  const RakuenMode(this.label, this.categoryLabel, this.requiresLogin);

  final String label;
  final String categoryLabel;
  final bool requiresLogin;

  bool get isSubject => switch (this) {
    subjectTrending || subjectLatest => true,
    _ => false,
  };

  String get apiMode => switch (this) {
    groupJoined => 'joined',
    groupCreated => 'created',
    groupReplied => 'replied',
    _ => 'all',
  };
}

enum CommunityGroupMode {
  all('全部小组', false),
  joined('我的小组', true),
  managed('管理的小组', true);

  const CommunityGroupMode(this.label, this.requiresLogin);

  final String label;
  final bool requiresLogin;
}

enum CommunityGroupSort {
  members('成员数'),
  updated('最新讨论'),
  topics('主题数'),
  posts('帖子数'),
  created('创建时间');

  const CommunityGroupSort(this.label);

  final String label;
}

enum CommunityTimelineMode {
  friends('好友'),
  all('全站'),
  me('我的');

  const CommunityTimelineMode(this.label);

  final String label;
}

class NoticeTimelineDestination {
  const NoticeTimelineDestination({
    required this.timelineId,
    required this.mode,
    this.username,
  });

  final int timelineId;
  final CommunityTimelineMode mode;
  final String? username;

  /// P1 `until` is an exclusive max id, so this keeps [timelineId] on the
  /// first page.
  int get fetchUntil => timelineId + 1;
}

class CommunityPageResult<T> {
  const CommunityPageResult({required this.data, required this.total});

  final List<T> data;
  final int total;
}

enum CommunityTopicKind {
  group,
  subject,
  episode,
  character,
  person,
  blog,
  unknown;

  String get label => switch (this) {
    group => '小组',
    subject => '条目',
    episode => '章节',
    character => '角色',
    person => '人物',
    blog => '日志',
    unknown => '话题',
  };
}

class CommunityTopic {
  const CommunityTopic({
    this.id = 0,
    required this.kind,
    required this.title,
    required this.url,
    required this.webUrl,
    this.sourceTitle = '',
    this.sourceUrl = '',
    this.author = '',
    this.avatarUrl = '',
    this.replyCount = 0,
    this.updatedText = '',
    this.updatedAt,
  });

  final int id;
  final CommunityTopicKind kind;
  final String title;
  final String url;
  final String webUrl;
  final String sourceTitle;
  final String sourceUrl;
  final String author;
  final String avatarUrl;
  final int replyCount;
  final String updatedText;
  final DateTime? updatedAt;
}

class CommunityGroup {
  const CommunityGroup({
    this.id = 0,
    this.slug = '',
    required this.name,
    required this.url,
    this.imageUrl = '',
    this.memberText = '',
    this.memberCount = 0,
    this.topicCount = 0,
    this.createdAt,
    this.nsfw = false,
  });

  final int id;
  final String slug;
  final String name;
  final String url;
  final String imageUrl;
  final String memberText;
  final int memberCount;
  final int topicCount;
  final DateTime? createdAt;
  final bool nsfw;
}

class CommunityLanding {
  const CommunityLanding({this.topics = const [], this.groups = const []});

  final List<CommunityTopic> topics;
  final List<CommunityGroup> groups;
}

class CommunityPost {
  const CommunityPost({
    required this.id,
    required this.author,
    required this.body,
    this.userUrl = '',
    this.avatarUrl = '',
    this.meta = '',
    this.images = const [],
    this.rawBody = '',
    this.isOriginal = false,
    this.isNested = false,
    this.reactions = const [],
  });

  final String id;
  final String author;
  final String body;
  final String userUrl;
  final String avatarUrl;
  final String meta;
  final List<String> images;
  final String rawBody;
  final bool isOriginal;
  final bool isNested;
  final List<CommunityReaction> reactions;
}

class CommunityReaction {
  const CommunityReaction({required this.value, this.users = const []});

  final int value;
  final List<CommunityUser> users;

  int get count => users.length;

  bool isSelectedBy(String? username) {
    final normalized = username?.trim().toLowerCase() ?? '';
    return normalized.isNotEmpty &&
        users.any((user) => user.username.toLowerCase() == normalized);
  }
}

class CommunityTopicDetail {
  const CommunityTopicDetail({
    required this.title,
    required this.posts,
    this.sourceTitle = '',
    this.sourceUrl = '',
  });

  final String title;
  final String sourceTitle;
  final String sourceUrl;
  final List<CommunityPost> posts;
}

class CommunityUser {
  const CommunityUser({
    required this.id,
    required this.username,
    required this.nickname,
    this.avatarUrl = '',
    this.joinedAt,
  });

  final int id;
  final String username;
  final String nickname;
  final String avatarUrl;
  final DateTime? joinedAt;

  String get displayName => nickname.isEmpty ? username : nickname;
  String get webUrl => 'https://bgm.tv/user/$username';
}

class CommunityGroupDetail {
  const CommunityGroupDetail({
    required this.group,
    this.description = '',
    this.postCount = 0,
    this.accessible = true,
    this.joinedAt,
    this.members = const [],
    this.moderators = const [],
    this.recentTopics = const [],
  });

  final CommunityGroup group;
  final String description;
  final int postCount;
  final bool accessible;
  final DateTime? joinedAt;
  final List<CommunityUser> members;
  final List<CommunityUser> moderators;
  final List<CommunityTopic> recentTopics;

  bool get isJoined => joinedAt != null;
  bool get canCreateTopic => accessible || isJoined;
}

/// P1 `/p1/notify` notice item (电波提醒).
class BangumiNotice {
  const BangumiNotice({
    required this.id,
    required this.title,
    required this.type,
    required this.mainId,
    required this.relatedId,
    required this.unread,
    required this.createdAt,
    this.sender,
  });

  final int id;
  final String title;
  final int type;
  final int mainId;
  final int relatedId;
  final bool unread;
  final DateTime createdAt;
  final CommunityUser? sender;

  bool get isFriendRequest =>
      type == 14 && sender?.username.trim().isNotEmpty == true;

  bool get showsContextTitle => title.isNotEmpty && type != 14 && type != 15;

  String get actionText {
    final actor = sender?.displayName ?? 'Bangumi';
    final action = switch (type) {
      1 => '在你的小组话题中发表了新回复',
      2 => '在小组话题中回复了你',
      3 => '在你的条目讨论中发表了新回复',
      4 => '在条目讨论中回复了你',
      5 => '在角色讨论中发表了新回复',
      6 => '在角色讨论中回复了你',
      // The current P1 subject reply route emits 7/8. Older notices used
      // these values for blog replies, so keep the wording intentionally
      // broad and let [title] provide the exact context.
      7 => '在你参与的讨论中发表了新回复',
      8 => '在讨论中回复了你',
      9 => '在章节讨论中发表了新回复',
      10 => '在章节讨论中回复了你',
      11 => '在目录中给你留言了',
      12 => '在目录中回复了你',
      13 => '在人物讨论中回复了你',
      14 => '请求与你成为好友',
      15 => '通过了你的好友请求',
      22 => '回复了你的吐槽',
      23 => '在小组话题中提到了你',
      24 => '在条目讨论中提到了你',
      25 => '在角色讨论中提到了你',
      26 => '在人物讨论中提到了你',
      27 => '在目录中提到了你',
      28 => '在吐槽中提到了你',
      29 => '在日志中提到了你',
      30 => '在章节讨论中提到了你',
      35 || 36 || 41 || 42 => '接受了你的 Wiki Patch',
      37 || 38 || 43 || 44 => '拒绝了你的 Wiki Patch',
      39 || 40 || 45 || 46 => '将你的 Wiki Patch 标记为过期',
      47 || 48 || 49 || 50 => '回复了你参与的 Wiki Patch',
      _ => '发来一条提醒',
    };
    return '$actor$action';
  }

  /// Whether the app can resolve the referenced reply through a native P1
  /// topic endpoint. The title and action remain available when it cannot.
  bool get canLoadReplyContent =>
      mainId > 0 &&
      relatedId > 0 &&
      const {1, 2, 3, 4, 7, 8, 23, 24}.contains(type);

  CommunityTopicKind? get nativeTopicKind => switch (type) {
    1 || 2 || 23 => CommunityTopicKind.group,
    3 || 4 || 7 || 8 || 24 => CommunityTopicKind.subject,
    5 || 6 || 25 => CommunityTopicKind.character,
    9 || 10 || 30 => CommunityTopicKind.episode,
    13 || 26 => CommunityTopicKind.person,
    29 => CommunityTopicKind.blog,
    _ => null,
  };

  CommunityTopic? get nativeTopic {
    final kind = nativeTopicKind;
    if (kind == null || mainId <= 0) return null;
    final (rakuenKind, webPath) = switch (kind) {
      CommunityTopicKind.group => ('group', '/group/topic/$mainId'),
      CommunityTopicKind.subject => ('subject', '/subject/topic/$mainId'),
      CommunityTopicKind.episode => ('ep', '/ep/$mainId'),
      CommunityTopicKind.character => ('crt', '/character/$mainId'),
      CommunityTopicKind.person => ('prsn', '/person/$mainId'),
      CommunityTopicKind.blog => ('blog', '/blog/$mainId'),
      CommunityTopicKind.unknown => ('', ''),
    };
    return CommunityTopic(
      id: mainId,
      kind: kind,
      title: title,
      url: 'https://bgm.tv/rakuen/topic/$rakuenKind/$mainId',
      webUrl: 'https://bgm.tv$webPath',
    );
  }

  /// Type 22 is a reply on the current user's status. Type 28 is a mention on
  /// the sender's status, so it must not open `CommunityTimelineMode.me`.
  NoticeTimelineDestination? get nativeTimelineDestination {
    if (mainId <= 0) return null;
    return switch (type) {
      22 => NoticeTimelineDestination(
        timelineId: mainId,
        mode: CommunityTimelineMode.me,
      ),
      28 => NoticeTimelineDestination(
        timelineId: mainId,
        mode: CommunityTimelineMode.all,
        username: _senderUsername,
      ),
      _ => null,
    };
  }

  String? get _senderUsername {
    final value = sender?.username.trim() ?? '';
    return value.isEmpty ? null : value;
  }

  bool get opensNativeTimeline => nativeTimelineDestination != null;

  /// Best-effort deep link on bgm.tv; empty when unknown.
  String get webUrl {
    final topic = nativeTopic;
    if (topic != null) {
      return topic.kind == CommunityTopicKind.group ||
              topic.kind == CommunityTopicKind.subject
          ? topic.url
          : topic.webUrl;
    }
    if (sender != null && sender!.username.isNotEmpty) {
      return sender!.webUrl;
    }
    return 'https://bgm.tv/notify';
  }
}

class CommunityTimelineItem {
  const CommunityTimelineItem({
    required this.id,
    required this.user,
    required this.description,
    required this.createdAt,
    this.content = '',
    this.rawContent = '',
    this.imageUrls = const [],
    this.replyCount = 0,
    this.sourceName = '',
    this.sourceUrl = '',
    this.isStatus = false,
    this.progress,
  });

  final int id;
  final CommunityUser user;
  final String description;
  final String content;
  final String rawContent;
  final List<String> imageUrls;
  final int replyCount;
  final DateTime createdAt;
  final String sourceName;
  final String sourceUrl;
  final bool isStatus;
  final CommunityTimelineProgress? progress;

  CommunityTimelineItem copyWith({int? replyCount}) => CommunityTimelineItem(
    id: id,
    user: user,
    description: description,
    createdAt: createdAt,
    content: content,
    rawContent: rawContent,
    imageUrls: imageUrls,
    replyCount: replyCount ?? this.replyCount,
    sourceName: sourceName,
    sourceUrl: sourceUrl,
    isStatus: isStatus,
    progress: progress,
  );
}

class CommunityTimelineProgress {
  const CommunityTimelineProgress({
    required this.subjectId,
    required this.subjectName,
    required this.subjectNameCn,
    this.subjectType = 0,
    this.imageUrl = '',
    this.score = 0,
    this.rank = 0,
    this.episode,
    this.episodeProgress,
    this.episodeTotal = '',
    this.volumeProgress,
    this.volumeTotal = '',
  });

  final int subjectId;
  final String subjectName;
  final String subjectNameCn;
  final int subjectType;
  final String imageUrl;
  final double score;
  final int rank;
  final CommunityTimelineEpisode? episode;
  final int? episodeProgress;
  final String episodeTotal;
  final int? volumeProgress;
  final String volumeTotal;

  String get title => subjectNameCn.isNotEmpty ? subjectNameCn : subjectName;
  bool get isSingleEpisode => episode != null;
}

class CommunityTimelineEpisode {
  const CommunityTimelineEpisode({
    required this.id,
    required this.subjectId,
    required this.type,
    required this.sort,
    this.name = '',
    this.nameCn = '',
    this.airDate = '',
  });

  final int id;
  final int subjectId;
  final int type;
  final double sort;
  final String name;
  final String nameCn;
  final String airDate;

  String get title => nameCn.isNotEmpty ? nameCn : name;
}

class CommunityTimelineReply {
  const CommunityTimelineReply({
    required this.id,
    required this.creatorId,
    required this.user,
    required this.content,
    required this.rawContent,
    required this.createdAt,
    this.relatedId = 0,
    this.imageUrls = const [],
    this.replies = const [],
    this.isDeleted = false,
  });

  final int id;
  final int creatorId;
  final CommunityUser user;
  final String content;
  final String rawContent;
  final DateTime createdAt;
  final int relatedId;
  final List<String> imageUrls;
  final List<CommunityTimelineReply> replies;
  final bool isDeleted;
}
