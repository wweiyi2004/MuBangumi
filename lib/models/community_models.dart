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

  /// Best-effort deep link on bgm.tv; empty when unknown.
  String get webUrl {
    // Type numbers follow bangumi/next notify settings (topic/post/user/…).
    // Prefer stable public paths when ids are present.
    if (type >= 1 && type <= 8 && mainId > 0) {
      // Group / subject topic style notices commonly carry topic id in mainID.
      return 'https://bgm.tv/rakuen/topic/group/$mainId';
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
