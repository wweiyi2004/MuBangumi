enum SubjectType {
  book(1, '书籍', '读'),
  anime(2, '动画', '看'),
  music(3, '音乐', '听'),
  game(4, '游戏', '玩'),
  real(6, '三次元', '看');

  const SubjectType(this.value, this.label, this.verb);

  final int value;
  final String label;
  final String verb;

  bool get hasEpisodes => this == anime || this == real;

  bool get hasVolumes => this == book;

  static SubjectType fromValue(int value) => values.firstWhere(
    (item) => item.value == value,
    orElse: () => SubjectType.anime,
  );
}

enum CollectionType {
  wish(1),
  done(2),
  doing(3),
  onHold(4),
  dropped(5);

  const CollectionType(this.value);

  final int value;

  /// Default labels keep the historical anime wording.
  String get label => labelFor(SubjectType.anime);

  String labelFor(SubjectType type) => switch (this) {
    CollectionType.wish => '想${type.verb}',
    CollectionType.done => '${type.verb}过',
    CollectionType.doing => '在${type.verb}',
    CollectionType.onHold => '搁置',
    CollectionType.dropped => '抛弃',
  };

  static CollectionType fromValue(int value) => values.firstWhere(
    (item) => item.value == value,
    orElse: () => CollectionType.wish,
  );
}

class BangumiUser {
  const BangumiUser({
    required this.id,
    required this.username,
    required this.nickname,
    required this.avatarUrl,
    this.sign = '',
  });

  final int id;
  final String username;
  final String nickname;
  final String avatarUrl;
  final String sign;

  String get displayName => nickname.trim().isNotEmpty ? nickname : username;

  factory BangumiUser.fromJson(Map<String, dynamic> json) {
    final nested = json['user'];
    if (nested is Map && json['username'] == null) {
      return BangumiUser.fromJson(Map<String, dynamic>.from(nested));
    }
    final avatar = _map(json['avatar']);
    return BangumiUser(
      id: _int(json['id']),
      username: _string(json['username']),
      nickname: _string(json['nickname'], fallback: _string(json['username'])),
      avatarUrl: _string(avatar['large'], fallback: _string(avatar['medium'])),
      sign: _string(json['sign']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'nickname': nickname,
    'avatar': {'large': avatarUrl},
    'sign': sign,
  };
}

class Subject {
  const Subject({
    required this.id,
    required this.name,
    required this.nameCn,
    required this.imageUrl,
    required this.summary,
    required this.episodeCount,
    required this.score,
    required this.rank,
    required this.date,
    this.type = SubjectType.anime,
    this.volumeCount = 0,
    this.collectionTotal = 0,
    this.ratingTotal = 0,
    this.ratingCount = const {},
    this.wishCount = 0,
    this.collectCount = 0,
    this.doingCount = 0,
    this.onHoldCount = 0,
    this.droppedCount = 0,
    this.tags = const [],
    this.platform = '',
    this.officialSite = '',
    this.nsfw = false,
    this.metaTags = const [],
  });

  final int id;
  final SubjectType type;
  final String name;
  final String nameCn;
  final String imageUrl;
  final String summary;
  final int episodeCount;
  final int volumeCount;
  final double score;
  final int rank;
  final String date;
  final int collectionTotal;

  /// Number of users who rated this subject.
  final int ratingTotal;

  /// Score bucket (1-10) -> vote count. Inspired by garage "评分显示优化".
  final Map<int, int> ratingCount;
  final int wishCount;
  final int collectCount;
  final int doingCount;
  final int onHoldCount;
  final int droppedCount;
  final List<String> tags;

  /// Broadcast / release platform (e.g. TV, 剧场版, Web).
  final String platform;

  /// Official website when present in wiki infobox.
  final String officialSite;
  final bool nsfw;
  final List<String> metaTags;

  String get displayName => nameCn.trim().isNotEmpty ? nameCn : name;

  /// Population standard deviation of rating votes.
  double get ratingStdDev {
    if (ratingTotal <= 0 || ratingCount.isEmpty) return 0;
    var mean = 0.0;
    ratingCount.forEach((score, count) {
      mean += score * count;
    });
    mean /= ratingTotal;
    var variance = 0.0;
    ratingCount.forEach((score, count) {
      final delta = score - mean;
      variance += delta * delta * count;
    });
    variance /= ratingTotal;
    return variance <= 0 ? 0 : _sqrt(variance);
  }

  /// Human-readable controversy from stddev (garage #31 style).
  String get controversyLabel {
    final sigma = ratingStdDev;
    if (ratingTotal <= 0) return '暂无';
    if (sigma < 1.0) return '一致好评';
    if (sigma < 1.3) return '较为一致';
    if (sigma < 1.6) return '略有分歧';
    if (sigma < 2.0) return '争议较大';
    return '两极分化';
  }

  factory Subject.fromJson(Map<String, dynamic> json) {
    final images = _map(json['images']);
    final rating = _map(json['rating']);
    final collection = _map(json['collection']);
    final tagsJson = json['tags'];
    final countMap = _map(rating['count']);
    final ratingCount = <int, int>{
      for (var score = 1; score <= 10; score++) score: _int(countMap['$score']),
    };
    final typeValue = _int(
      json['type'],
      fallback: _int(json['subject_type'], fallback: SubjectType.anime.value),
    );
    final wish = _int(collection['wish']);
    final collect = _int(collection['collect']);
    final doing = _int(collection['doing']);
    final onHold = _int(collection['on_hold']);
    final dropped = _int(collection['dropped']);
    final totalFromBuckets = wish + collect + doing + onHold + dropped;
    final metaTagsJson = json['meta_tags'];
    return Subject(
      id: _int(json['id']),
      type: SubjectType.fromValue(typeValue),
      name: _string(json['name']),
      nameCn: _string(json['name_cn']),
      imageUrl: _string(
        images['large'],
        fallback: _string(
          images['common'],
          fallback: _string(
            images['medium'],
            fallback: _string(images['grid']),
          ),
        ),
      ),
      summary: _string(
        json['summary'],
        fallback: _string(json['short_summary']),
      ),
      episodeCount: _int(json['eps'], fallback: _int(json['total_episodes'])),
      volumeCount: _int(json['volumes']),
      score: _double(rating['score'], fallback: _double(json['score'])),
      rank: _int(rating['rank'], fallback: _int(json['rank'])),
      // Legacy calendar items use `air_date` instead of `date`.
      date: _string(json['date'], fallback: _string(json['air_date'])),
      collectionTotal: _int(
        collection['total'],
        fallback: totalFromBuckets > 0
            ? totalFromBuckets
            : _int(json['collection_total']),
      ),
      ratingTotal: _int(rating['total']),
      ratingCount: ratingCount,
      wishCount: wish,
      collectCount: collect,
      doingCount: doing,
      onHoldCount: onHold,
      droppedCount: dropped,
      tags: tagsJson is List
          ? tagsJson
                .map(
                  (tag) => tag is Map ? _string(tag['name']) : tag.toString(),
                )
                .where((tag) => tag.isNotEmpty)
                .take(8)
                .toList()
          : const [],
      platform: _string(json['platform']),
      officialSite: _officialSiteFromInfobox(json['infobox']),
      nsfw: json['nsfw'] == true,
      metaTags: metaTagsJson is List
          ? [
              for (final tag in metaTagsJson)
                if (tag != null && tag.toString().trim().isNotEmpty)
                  tag.toString().trim(),
            ].take(8).toList()
          : const [],
    );
  }

  Subject merge(Subject detailed) => Subject(
    id: id,
    type: detailed.type,
    name: detailed.name.isNotEmpty ? detailed.name : name,
    nameCn: detailed.nameCn.isNotEmpty ? detailed.nameCn : nameCn,
    imageUrl: detailed.imageUrl.isNotEmpty ? detailed.imageUrl : imageUrl,
    summary: detailed.summary.isNotEmpty ? detailed.summary : summary,
    episodeCount: detailed.episodeCount > 0
        ? detailed.episodeCount
        : episodeCount,
    volumeCount: detailed.volumeCount > 0 ? detailed.volumeCount : volumeCount,
    score: detailed.score > 0 ? detailed.score : score,
    rank: detailed.rank > 0 ? detailed.rank : rank,
    date: detailed.date.isNotEmpty ? detailed.date : date,
    collectionTotal: detailed.collectionTotal > 0
        ? detailed.collectionTotal
        : collectionTotal,
    ratingTotal: detailed.ratingTotal > 0 ? detailed.ratingTotal : ratingTotal,
    ratingCount: detailed.ratingCount.values.any((v) => v > 0)
        ? detailed.ratingCount
        : ratingCount,
    wishCount: detailed.wishCount > 0 ? detailed.wishCount : wishCount,
    collectCount: detailed.collectCount > 0
        ? detailed.collectCount
        : collectCount,
    doingCount: detailed.doingCount > 0 ? detailed.doingCount : doingCount,
    onHoldCount: detailed.onHoldCount > 0 ? detailed.onHoldCount : onHoldCount,
    droppedCount: detailed.droppedCount > 0
        ? detailed.droppedCount
        : droppedCount,
    tags: detailed.tags.isNotEmpty ? detailed.tags : tags,
    platform: detailed.platform.isNotEmpty ? detailed.platform : platform,
    officialSite: detailed.officialSite.isNotEmpty
        ? detailed.officialSite
        : officialSite,
    nsfw: detailed.nsfw || nsfw,
    metaTags: detailed.metaTags.isNotEmpty ? detailed.metaTags : metaTags,
  );

  /// Compact JSON for local list snapshots (Shaft-style first-screen cache).
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.value,
    'name': name,
    'name_cn': nameCn,
    'images': {'large': imageUrl},
    'summary': summary,
    'eps': episodeCount,
    'volumes': volumeCount,
    'rating': {
      'score': score,
      'rank': rank,
      'total': ratingTotal,
      'count': {
        for (final entry in ratingCount.entries) '${entry.key}': entry.value,
      },
    },
    'date': date,
    'collection': {
      'total': collectionTotal,
      'wish': wishCount,
      'collect': collectCount,
      'doing': doingCount,
      'on_hold': onHoldCount,
      'dropped': droppedCount,
    },
    'tags': [
      for (final tag in tags) {'name': tag},
    ],
    'platform': platform,
    'nsfw': nsfw,
    'meta_tags': metaTags,
  };
}

/// Lightweight friend collection status for a subject (garage "好友看？").
class FriendSubjectStatus {
  const FriendSubjectStatus({
    required this.user,
    required this.type,
    this.rate = 0,
    this.episodeStatus = 0,
  });

  final BangumiUser user;
  final CollectionType type;
  final int rate;
  final int episodeStatus;
}

double _sqrt(double value) {
  if (value <= 0) return 0;
  var x = value;
  for (var i = 0; i < 12; i++) {
    x = 0.5 * (x + value / x);
  }
  return x;
}

class UserCollection {
  const UserCollection({
    required this.subjectId,
    required this.type,
    required this.rate,
    required this.episodeStatus,
    required this.updatedAt,
    required this.subject,
    this.volumeStatus = 0,
    this.comment = '',
    this.tags = const [],
    this.private = false,
  });

  final int subjectId;
  final CollectionType type;
  final int rate;
  final int episodeStatus;
  final int volumeStatus;
  final DateTime? updatedAt;
  final Subject subject;
  final String comment;
  final List<String> tags;
  final bool private;

  SubjectType get subjectType => subject.type;

  factory UserCollection.fromJson(Map<String, dynamic> json) {
    final subjectId = _int(json['subject_id']);
    final subjectJson = _map(json['subject']);
    if (!subjectJson.containsKey('id')) subjectJson['id'] = subjectId;
    final subjectType = _int(
      json['subject_type'],
      fallback: _int(subjectJson['type'], fallback: SubjectType.anime.value),
    );
    if (!subjectJson.containsKey('type')) {
      subjectJson['type'] = subjectType;
    }
    final tagsJson = json['tags'];
    final tags = tagsJson is List
        ? [
            for (final item in tagsJson)
              if (item != null && item.toString().trim().isNotEmpty)
                item.toString().trim(),
          ]
        : const <String>[];
    return UserCollection(
      subjectId: subjectId,
      type: CollectionType.fromValue(_int(json['type'], fallback: 1)),
      rate: _int(json['rate']),
      episodeStatus: _int(json['ep_status']),
      volumeStatus: _int(json['vol_status']),
      updatedAt: DateTime.tryParse(_string(json['updated_at'])),
      subject: Subject.fromJson(subjectJson),
      comment: _string(json['comment']),
      tags: tags,
      private: json['private'] == true || json['private'] == 1,
    );
  }

  UserCollection copyWith({
    CollectionType? type,
    int? rate,
    int? episodeStatus,
    int? volumeStatus,
    String? comment,
    List<String>? tags,
    bool? private,
  }) => UserCollection(
    subjectId: subjectId,
    type: type ?? this.type,
    rate: rate ?? this.rate,
    episodeStatus: episodeStatus ?? this.episodeStatus,
    volumeStatus: volumeStatus ?? this.volumeStatus,
    updatedAt: DateTime.now(),
    subject: subject,
    comment: comment ?? this.comment,
    tags: tags ?? this.tags,
    private: private ?? this.private,
  );

  Map<String, dynamic> toJson() => {
    'subject_id': subjectId,
    'subject_type': subject.type.value,
    'type': type.value,
    'rate': rate,
    'ep_status': episodeStatus,
    'vol_status': volumeStatus,
    'updated_at': updatedAt?.toIso8601String(),
    'comment': comment,
    'tags': tags,
    'private': private,
    'subject': subject.toJson(),
  };
}

class Episode {
  const Episode({
    required this.id,
    required this.type,
    required this.number,
    required this.sort,
    required this.name,
    required this.nameCn,
    required this.airDate,
    required this.description,
  });

  final int id;
  final int type;
  final double number;
  final double sort;
  final String name;
  final String nameCn;
  final String airDate;
  final String description;

  String get displayName {
    if (nameCn.isNotEmpty) return nameCn;
    if (name.isNotEmpty) return name;
    return '第 ${number.toStringAsFixed(number % 1 == 0 ? 0 : 1)} 话';
  }

  factory Episode.fromJson(Map<String, dynamic> json) => Episode(
    id: _int(json['id']),
    type: _int(json['type']),
    number: _double(json['ep']),
    sort: _double(json['sort'], fallback: _double(json['ep'])),
    name: _string(json['name']),
    nameCn: _string(json['name_cn']),
    airDate: _string(json['airdate']),
    description: _string(json['desc']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'ep': number,
    'sort': sort,
    'name': name,
    'name_cn': nameCn,
    'airdate': airDate,
    'desc': description,
  };
}

class UserEpisodeCollection {
  const UserEpisodeCollection({
    required this.episode,
    required this.type,
    required this.updatedAt,
  });

  final Episode episode;
  final int type;
  final int updatedAt;

  bool get isWatched => type == 2;

  factory UserEpisodeCollection.fromJson(Map<String, dynamic> json) =>
      UserEpisodeCollection(
        episode: Episode.fromJson(_map(json['episode'])),
        type: _int(json['type']),
        updatedAt: _int(json['updated_at']),
      );

  Map<String, dynamic> toJson() => {
    'episode': episode.toJson(),
    'type': type,
    'updated_at': updatedAt,
  };

  UserEpisodeCollection copyWith({int? type}) => UserEpisodeCollection(
    episode: episode,
    type: type ?? this.type,
    updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
  );
}

Map<String, dynamic> _map(dynamic value) {
  if (value is Map<String, dynamic>) return Map<String, dynamic>.from(value);
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return <String, dynamic>{};
}

String _officialSiteFromInfobox(dynamic infobox) {
  if (infobox is! List) return '';
  for (final item in infobox) {
    if (item is! Map) continue;
    final key = item['key']?.toString() ?? '';
    if (key != '官方网站' && key != '官网' && key != 'Website' && key != '官方網站') {
      continue;
    }
    final value = item['value'];
    if (value is String && value.trim().isNotEmpty) return value.trim();
    if (value is List) {
      for (final entry in value) {
        if (entry is Map) {
          final v = entry['v']?.toString() ?? entry['value']?.toString() ?? '';
          if (v.trim().isNotEmpty) return v.trim();
        } else if (entry != null && entry.toString().trim().isNotEmpty) {
          return entry.toString().trim();
        }
      }
    }
  }
  return '';
}

String _string(dynamic value, {String fallback = ''}) =>
    value == null || value.toString().isEmpty ? fallback : value.toString();

int _int(dynamic value, {int fallback = 0}) => value is num
    ? value.toInt()
    : int.tryParse(value?.toString() ?? '') ?? fallback;

double _double(dynamic value, {double fallback = 0}) => value is num
    ? value.toDouble()
    : double.tryParse(value?.toString() ?? '') ?? fallback;
