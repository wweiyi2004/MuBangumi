import '../../models/bangumi_models.dart';

/// Pure helpers for Bangumi OpenAPI payloads/parsers (unit-testable).
class BangumiSupport {
  BangumiSupport._();

  /// Query for paginated search/browse continuation.
  static Map<String, int> pageQuery({
    required int limit,
    required int offset,
  }) => {'limit': limit, 'offset': offset};

  /// Body `filter` for POST /v0/search/subjects.
  static Map<String, dynamic> subjectSearchFilter({
    required SubjectType subjectType,
    int minimumRating = 0,
    int startYear = 0,
    List<String> tags = const [],
    List<String> metaTags = const [],
  }) => {
    'type': [subjectType.value],
    'nsfw': false,
    if (minimumRating > 0) 'rating': ['>=$minimumRating'],
    if (startYear > 0) 'air_date': ['>=$startYear-01-01'],
    if (tags.isNotEmpty) 'tag': tags,
    if (metaTags.isNotEmpty) 'meta_tags': metaTags,
  };

  /// Payload for POST /v0/users/-/collections/{id}.
  ///
  /// [episodeStatus] / [volumeStatus] are only meaningful for books
  /// (`ep_status` / `vol_status` in OpenAPI). Omit them for other types.
  static Map<String, dynamic> collectionUpdatePayload({
    required CollectionType type,
    int rate = 0,
    String comment = '',
    List<String> tags = const [],
    bool private = false,
    int? episodeStatus,
    int? volumeStatus,
  }) {
    final clamped = rate.clamp(0, 10);
    return {
      'type': type.value,
      'rate': clamped,
      'comment': comment,
      'tags': [
        for (final tag in tags)
          if (tag.trim().isNotEmpty) tag.trim(),
      ],
      'private': private,
      if (episodeStatus != null)
        'ep_status': episodeStatus < 0 ? 0 : episodeStatus,
      if (volumeStatus != null)
        'vol_status': volumeStatus < 0 ? 0 : volumeStatus,
    };
  }

  static String episodeTypeLabel(int type) => switch (type) {
    0 => '本篇',
    1 => '特别篇',
    2 => 'OP',
    3 => 'ED',
    4 => '预告/宣传/广告',
    5 => 'MAD',
    6 => '其他',
    _ => '类型$type',
  };

  /// Keep episodes matching [filterType]; null keeps all.
  static List<Episode> filterEpisodesByType(
    List<Episode> episodes,
    int? filterType,
  ) {
    if (filterType == null) return List<Episode>.from(episodes);
    return [
      for (final ep in episodes)
        if (ep.type == filterType) ep,
    ];
  }

  /// Progress tooling only counts 本篇 (`episode.type == 0`).
  static List<UserEpisodeCollection> mainEpisodeCollections(
    List<UserEpisodeCollection> episodes,
  ) => [
    for (final item in episodes)
      if (item.episode.type == 0) item,
  ];

  /// Next unwatched 本篇; ignores SP/OP/ED even if mixed into [episodes].
  static UserEpisodeCollection? nextUnwatchedMain(
    List<UserEpisodeCollection> episodes,
  ) {
    for (final item in mainEpisodeCollections(episodes)) {
      if (!item.isWatched) return item;
    }
    return null;
  }

  /// Unwatched 本篇 ids for “看过” auto-complete.
  static List<int> unfinishedMainEpisodeIds(
    List<UserEpisodeCollection> episodes,
  ) => [
    for (final item in mainEpisodeCollections(episodes))
      if (!item.isWatched) item.episode.id,
  ];

  /// Watched 本篇 count after marking [markedEpisodeId] as watched.
  static int watchedMainCountAfterMark(
    List<UserEpisodeCollection> episodes,
    int markedEpisodeId,
  ) {
    var count = 0;
    for (final item in mainEpisodeCollections(episodes)) {
      if (item.isWatched || item.episode.id == markedEpisodeId) count++;
    }
    return count;
  }

  static List<RelatedSubject> parseRelatedSubjects(List<dynamic>? raw) {
    if (raw == null) return const [];
    final result = <RelatedSubject>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final subject = map['subject'] is Map
          ? Map<String, dynamic>.from(map['subject'] as Map)
          : map;
      final id = (subject['id'] as num?)?.toInt() ?? 0;
      if (id <= 0) continue;
      final images = subject['images'];
      var imageUrl = '';
      if (images is Map) {
        imageUrl =
            images['large']?.toString() ??
            images['common']?.toString() ??
            images['medium']?.toString() ??
            '';
      }
      result.add(
        RelatedSubject(
          id: id,
          name: subject['name']?.toString() ?? '',
          nameCn: subject['name_cn']?.toString() ?? '',
          imageUrl: imageUrl,
          relation:
              map['relation']?.toString() ??
              map['relation_cn']?.toString() ??
              '',
          type: SubjectType.fromValue(
            (subject['type'] as num?)?.toInt() ?? SubjectType.anime.value,
          ),
        ),
      );
    }
    return result;
  }

  static String imageUrlFrom(dynamic images, {String fallback = ''}) {
    if (images is Map) {
      return images['large']?.toString() ??
          images['medium']?.toString() ??
          images['common']?.toString() ??
          images['small']?.toString() ??
          images['grid']?.toString() ??
          fallback;
    }
    if (images is String && images.isNotEmpty) return images;
    return fallback;
  }

  /// Pull 简体中文名 from OpenAPI infobox array when present.
  static String nameCnFromInfobox(List<dynamic>? infobox) {
    if (infobox == null) return '';
    for (final item in infobox) {
      if (item is! Map) continue;
      final key = item['key']?.toString() ?? '';
      if (key != '简体中文名' && key != '中文名') continue;
      final value = item['value'];
      if (value is String && value.trim().isNotEmpty) return value.trim();
      if (value is List) {
        for (final entry in value) {
          if (entry is Map) {
            final v = entry['v']?.toString() ?? '';
            if (v.trim().isNotEmpty) return v.trim();
          } else if (entry != null && entry.toString().trim().isNotEmpty) {
            return entry.toString().trim();
          }
        }
      }
    }
    return '';
  }

  static List<String> careerFrom(dynamic raw) {
    if (raw is! List) return const [];
    return [
      for (final c in raw)
        if (c != null && c.toString().isNotEmpty) c.toString(),
    ];
  }

  static List<SubjectCharacter> parseCharacters(List<dynamic>? raw) {
    if (raw == null) return const [];
    final result = <SubjectCharacter>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final actors = <SubjectActor>[];
      final actorsRaw = map['actors'];
      if (actorsRaw is List) {
        for (final actor in actorsRaw) {
          if (actor is! Map) continue;
          final actorMap = Map<String, dynamic>.from(actor);
          final name = actorMap['name']?.toString() ?? '';
          if (name.isEmpty) continue;
          actors.add(
            SubjectActor(
              id: (actorMap['id'] as num?)?.toInt() ?? 0,
              name: name,
              imageUrl: imageUrlFrom(actorMap['images']),
            ),
          );
        }
      }
      final id = (map['id'] as num?)?.toInt() ?? 0;
      if (id <= 0) continue;
      result.add(
        SubjectCharacter(
          id: id,
          name: map['name']?.toString() ?? '',
          nameCn: map['name_cn']?.toString() ?? '',
          imageUrl: imageUrlFrom(map['images']),
          relation: map['relation']?.toString() ?? '',
          actors: actors,
        ),
      );
    }
    return result;
  }

  static List<SubjectPerson> parsePersons(List<dynamic>? raw) {
    if (raw == null) return const [];
    final result = <SubjectPerson>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final id = (map['id'] as num?)?.toInt() ?? 0;
      if (id <= 0) continue;
      result.add(
        SubjectPerson(
          id: id,
          name: map['name']?.toString() ?? '',
          nameCn: map['name_cn']?.toString() ?? '',
          imageUrl: imageUrlFrom(map['images']),
          relation: map['relation']?.toString() ?? '',
          career: careerFrom(map['career']),
          type: (map['type'] as num?)?.toInt() ?? 0,
          eps: map['eps']?.toString() ?? '',
        ),
      );
    }
    return result;
  }

  static CharacterDetail parseCharacterDetail(Map<String, dynamic> json) {
    final infobox = json['infobox'] is List
        ? List<dynamic>.from(json['infobox'] as List)
        : null;
    final nameCn = nameCnFromInfobox(infobox);
    final stat = json['stat'] is Map
        ? Map<String, dynamic>.from(json['stat'] as Map)
        : const <String, dynamic>{};
    return CharacterDetail(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name']?.toString() ?? '',
      nameCn: nameCn,
      imageUrl: imageUrlFrom(json['images']),
      summary: json['summary']?.toString() ?? '',
      gender: json['gender']?.toString() ?? '',
      type: (json['type'] as num?)?.toInt() ?? 0,
      commentCount: (stat['comments'] as num?)?.toInt() ?? 0,
      collectCount: (stat['collects'] as num?)?.toInt() ?? 0,
    );
  }

  static PersonDetail parsePersonDetail(Map<String, dynamic> json) {
    final infobox = json['infobox'] is List
        ? List<dynamic>.from(json['infobox'] as List)
        : null;
    final nameCn = nameCnFromInfobox(infobox);
    final stat = json['stat'] is Map
        ? Map<String, dynamic>.from(json['stat'] as Map)
        : const <String, dynamic>{};
    return PersonDetail(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name']?.toString() ?? '',
      nameCn: nameCn,
      imageUrl: imageUrlFrom(
        json['images'],
        fallback: json['img']?.toString() ?? '',
      ),
      summary:
          json['summary']?.toString() ??
          json['short_summary']?.toString() ??
          '',
      gender: json['gender']?.toString() ?? '',
      type: (json['type'] as num?)?.toInt() ?? 0,
      career: careerFrom(json['career']),
      commentCount: (stat['comments'] as num?)?.toInt() ?? 0,
      collectCount: (stat['collects'] as num?)?.toInt() ?? 0,
    );
  }

  /// Character/person → subjects links (`staff`, flat subject fields).
  static List<MonoLinkedSubject> parseMonoSubjects(List<dynamic>? raw) {
    if (raw == null) return const [];
    final result = <MonoLinkedSubject>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final id = (map['id'] as num?)?.toInt() ?? 0;
      if (id <= 0) continue;
      result.add(
        MonoLinkedSubject(
          id: id,
          name: map['name']?.toString() ?? '',
          nameCn: map['name_cn']?.toString() ?? '',
          imageUrl: map['image']?.toString() ?? imageUrlFrom(map['images']),
          staff: map['staff']?.toString() ?? '',
          eps: map['eps']?.toString() ?? '',
          type: SubjectType.fromValue(
            (map['type'] as num?)?.toInt() ?? SubjectType.anime.value,
          ),
        ),
      );
    }
    return result;
  }

  /// Character → cast persons (`/characters/{id}/persons`).
  static List<MonoLinkedPerson> parseCharacterPersons(List<dynamic>? raw) {
    if (raw == null) return const [];
    final result = <MonoLinkedPerson>[];
    final seen = <int>{};
    for (final item in raw) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final id = (map['id'] as num?)?.toInt() ?? 0;
      if (id <= 0 || !seen.add(id)) continue;
      result.add(
        MonoLinkedPerson(
          id: id,
          name: map['name']?.toString() ?? '',
          imageUrl: imageUrlFrom(map['images']),
          staff: map['staff']?.toString() ?? '',
          subjectName:
              (map['subject_name_cn']?.toString().trim().isNotEmpty ?? false)
              ? map['subject_name_cn'].toString()
              : (map['subject_name']?.toString() ?? ''),
        ),
      );
    }
    return result;
  }

  /// Person → characters (`/persons/{id}/characters`).
  static List<MonoLinkedCharacter> parsePersonCharacters(List<dynamic>? raw) {
    if (raw == null) return const [];
    final result = <MonoLinkedCharacter>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final id = (map['id'] as num?)?.toInt() ?? 0;
      if (id <= 0) continue;
      result.add(
        MonoLinkedCharacter(
          id: id,
          name: map['name']?.toString() ?? '',
          imageUrl: imageUrlFrom(map['images']),
          staff: map['staff']?.toString() ?? '',
          subjectName:
              (map['subject_name_cn']?.toString().trim().isNotEmpty ?? false)
              ? map['subject_name_cn'].toString()
              : (map['subject_name']?.toString() ?? ''),
        ),
      );
    }
    return result;
  }

  /// Parse GET /v0/calendar body: list of {weekday, items}.
  static List<CalendarDay> parseCalendar(List<dynamic>? raw) {
    if (raw == null) return const [];
    final result = <CalendarDay>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final weekdayMap = map['weekday'];
      var weekdayId = 0;
      var weekdayCn = '';
      if (weekdayMap is Map) {
        weekdayId = (weekdayMap['id'] as num?)?.toInt() ?? 0;
        weekdayCn =
            weekdayMap['cn']?.toString() ?? weekdayMap['en']?.toString() ?? '';
      }
      final subjects = <Subject>[];
      final items = map['items'];
      if (items is List) {
        for (final s in items) {
          if (s is! Map) continue;
          try {
            subjects.add(Subject.fromJson(Map<String, dynamic>.from(s)));
          } catch (_) {}
        }
      }
      result.add(
        CalendarDay(
          weekday: weekdayId,
          weekdayLabel: weekdayCn,
          subjects: subjects,
        ),
      );
    }
    result.sort((a, b) => a.weekday.compareTo(b.weekday));
    return result;
  }

  /// Parse HTML comments page fragments (bgm.tv subject comments).
  static List<SubjectComment> parseSubjectCommentsHtml(String html) {
    final result = <SubjectComment>[];
    // Each comment block typically has user + content.
    final blockRe = RegExp(
      r'id="item_(\d+)"[\s\S]*?'
      r'class="avatarNeue[^"]*"[^>]*style="background-image:url\(([^)]+)\)"[\s\S]*?'
      r'(?:href="[^"]*/user/([^"]+)"[^>]*class="l"|class="l"[^>]*href="[^"]*/user/([^"]+)"|class="l")[^>]*>([^<]+)</a>[\s\S]*?'
      r'(?:class="starlight stars(\d+)"[\s\S]*?)?'
      r'class="comment"[^>]*>([\s\S]*?)</div>',
      caseSensitive: false,
    );
    for (final match in blockRe.allMatches(html)) {
      final content = match
          .group(7)!
          .replaceAll(RegExp(r'<[^>]+>'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (content.isEmpty) continue;
      final username = (match.group(3) ?? match.group(4) ?? '').trim();
      final display = (match.group(5) ?? '').trim();
      result.add(
        SubjectComment(
          id: int.tryParse(match.group(1) ?? '') ?? 0,
          userName: display,
          username: username.isNotEmpty ? username : display,
          avatarUrl: (match.group(2) ?? '').replaceAll("'", '').trim(),
          rate: int.tryParse(match.group(6) ?? '') ?? 0,
          comment: content,
        ),
      );
    }
    if (result.isNotEmpty) return result;

    // Fallback simpler pattern for text-only blocks.
    final simple = RegExp(
      r'class="text"[^>]*>\s*<p>([\s\S]*?)</p>',
      caseSensitive: false,
    );
    var i = 0;
    for (final match in simple.allMatches(html)) {
      final content = match
          .group(1)!
          .replaceAll(RegExp(r'<[^>]+>'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (content.isEmpty) continue;
      result.add(
        SubjectComment(
          id: i++,
          userName: '',
          username: '',
          avatarUrl: '',
          rate: 0,
          comment: content,
        ),
      );
    }
    return result;
  }
}

class RelatedSubject {
  const RelatedSubject({
    required this.id,
    required this.name,
    required this.nameCn,
    required this.imageUrl,
    required this.relation,
    required this.type,
  });

  final int id;
  final String name;
  final String nameCn;
  final String imageUrl;
  final String relation;
  final SubjectType type;

  String get displayName => nameCn.trim().isNotEmpty ? nameCn : name;

  Subject toSubject() => Subject(
    id: id,
    name: name,
    nameCn: nameCn,
    imageUrl: imageUrl,
    summary: '',
    episodeCount: 0,
    score: 0,
    rank: 0,
    date: '',
    type: type,
  );
}

class SubjectActor {
  const SubjectActor({
    required this.id,
    required this.name,
    this.imageUrl = '',
  });

  final int id;
  final String name;
  final String imageUrl;
}

class SubjectCharacter {
  const SubjectCharacter({
    required this.id,
    required this.name,
    required this.nameCn,
    required this.imageUrl,
    required this.relation,
    required this.actors,
  });

  final int id;
  final String name;
  final String nameCn;
  final String imageUrl;
  final String relation;
  final List<SubjectActor> actors;

  String get displayName => nameCn.trim().isNotEmpty ? nameCn : name;

  List<String> get actorNames => [for (final a in actors) a.name];
}

class SubjectPerson {
  const SubjectPerson({
    required this.id,
    required this.name,
    required this.nameCn,
    required this.imageUrl,
    required this.relation,
    required this.career,
    this.type = 0,
    this.eps = '',
  });

  final int id;
  final String name;
  final String nameCn;
  final String imageUrl;
  final String relation;
  final List<String> career;

  /// Bangumi person type: 1 individual, 2 company, 3 group.
  final int type;
  final String eps;

  String get displayName => nameCn.trim().isNotEmpty ? nameCn : name;
}

class CharacterDetail {
  const CharacterDetail({
    required this.id,
    required this.name,
    required this.nameCn,
    required this.imageUrl,
    required this.summary,
    required this.gender,
    required this.type,
    required this.commentCount,
    required this.collectCount,
  });

  final int id;
  final String name;
  final String nameCn;
  final String imageUrl;
  final String summary;
  final String gender;
  final int type;
  final int commentCount;
  final int collectCount;

  String get displayName => nameCn.trim().isNotEmpty ? nameCn : name;
}

class PersonDetail {
  const PersonDetail({
    required this.id,
    required this.name,
    required this.nameCn,
    required this.imageUrl,
    required this.summary,
    required this.gender,
    required this.type,
    required this.career,
    required this.commentCount,
    required this.collectCount,
  });

  final int id;
  final String name;
  final String nameCn;
  final String imageUrl;
  final String summary;
  final String gender;
  final int type;
  final List<String> career;
  final int commentCount;
  final int collectCount;

  String get displayName => nameCn.trim().isNotEmpty ? nameCn : name;
}

class MonoLinkedSubject {
  const MonoLinkedSubject({
    required this.id,
    required this.name,
    required this.nameCn,
    required this.imageUrl,
    required this.staff,
    required this.type,
    this.eps = '',
  });

  final int id;
  final String name;
  final String nameCn;
  final String imageUrl;
  final String staff;
  final String eps;
  final SubjectType type;

  String get displayName => nameCn.trim().isNotEmpty ? nameCn : name;

  Subject toSubject() => Subject(
    id: id,
    name: name,
    nameCn: nameCn,
    imageUrl: imageUrl,
    summary: '',
    episodeCount: 0,
    score: 0,
    rank: 0,
    date: '',
    type: type,
  );
}

class MonoLinkedPerson {
  const MonoLinkedPerson({
    required this.id,
    required this.name,
    required this.imageUrl,
    required this.staff,
    required this.subjectName,
  });

  final int id;
  final String name;
  final String imageUrl;
  final String staff;
  final String subjectName;
}

class MonoLinkedCharacter {
  const MonoLinkedCharacter({
    required this.id,
    required this.name,
    required this.imageUrl,
    required this.staff,
    required this.subjectName,
  });

  final int id;
  final String name;
  final String imageUrl;
  final String staff;
  final String subjectName;
}

class CalendarDay {
  const CalendarDay({
    required this.weekday,
    required this.weekdayLabel,
    required this.subjects,
  });

  final int weekday;
  final String weekdayLabel;
  final List<Subject> subjects;
}

class SubjectComment {
  const SubjectComment({
    required this.id,
    required this.userName,
    this.username = '',
    required this.avatarUrl,
    required this.rate,
    required this.comment,
  });

  final int id;

  /// Display nickname when available.
  final String userName;

  /// Profile path username (`/user/{username}`); falls back to [userName].
  final String username;
  final String avatarUrl;
  final int rate;
  final String comment;

  String get profileUsername =>
      username.trim().isNotEmpty ? username.trim() : userName.trim();
}
