import '../../models/bangumi_models.dart';

/// Pure helpers for Bangumi OpenAPI payloads/parsers (unit-testable).
class BangumiSupport {
  BangumiSupport._();

  /// Query for paginated search/browse continuation.
  static Map<String, int> pageQuery({required int limit, required int offset}) =>
      {'limit': limit, 'offset': offset};

  /// Payload for POST /v0/users/-/collections/{id}.
  static Map<String, dynamic> collectionUpdatePayload({
    required CollectionType type,
    int rate = 0,
    String comment = '',
    List<String> tags = const [],
    bool private = false,
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
          relation: map['relation']?.toString() ??
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

  static List<SubjectCharacter> parseCharacters(List<dynamic>? raw) {
    if (raw == null) return const [];
    final result = <SubjectCharacter>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final actors = <String>[];
      final actorsRaw = map['actors'];
      if (actorsRaw is List) {
        for (final actor in actorsRaw) {
          if (actor is Map) {
            final name = actor['name']?.toString() ?? '';
            if (name.isNotEmpty) actors.add(name);
          }
        }
      }
      final images = map['images'];
      var imageUrl = '';
      if (images is Map) {
        imageUrl =
            images['large']?.toString() ??
            images['medium']?.toString() ??
            images['grid']?.toString() ??
            '';
      }
      final id = (map['id'] as num?)?.toInt() ?? 0;
      if (id <= 0) continue;
      result.add(
        SubjectCharacter(
          id: id,
          name: map['name']?.toString() ?? '',
          nameCn: map['name_cn']?.toString() ?? '',
          imageUrl: imageUrl,
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
      final images = map['images'];
      var imageUrl = '';
      if (images is Map) {
        imageUrl =
            images['large']?.toString() ??
            images['medium']?.toString() ??
            '';
      }
      final id = (map['id'] as num?)?.toInt() ?? 0;
      if (id <= 0) continue;
      result.add(
        SubjectPerson(
          id: id,
          name: map['name']?.toString() ?? '',
          nameCn: map['name_cn']?.toString() ?? '',
          imageUrl: imageUrl,
          relation: map['relation']?.toString() ?? '',
          career: [
            if (map['career'] is List)
              for (final c in map['career'] as List)
                if (c != null && c.toString().isNotEmpty) c.toString(),
          ],
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
        weekdayCn = weekdayMap['cn']?.toString() ??
            weekdayMap['en']?.toString() ??
            '';
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
      r'class="l"[^>]*>([^<]+)</a>[\s\S]*?'
      r'(?:class="starlight stars(\d+)"[\s\S]*?)?'
      r'class="comment"[^>]*>([\s\S]*?)</div>',
      caseSensitive: false,
    );
    for (final match in blockRe.allMatches(html)) {
      final content = match
          .group(5)!
          .replaceAll(RegExp(r'<[^>]+>'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (content.isEmpty) continue;
      result.add(
        SubjectComment(
          id: int.tryParse(match.group(1) ?? '') ?? 0,
          userName: match.group(3)?.trim() ?? '',
          avatarUrl: (match.group(2) ?? '').replaceAll("'", '').trim(),
          rate: int.tryParse(match.group(4) ?? '') ?? 0,
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
  final List<String> actors;

  String get displayName => nameCn.trim().isNotEmpty ? nameCn : name;
}

class SubjectPerson {
  const SubjectPerson({
    required this.id,
    required this.name,
    required this.nameCn,
    required this.imageUrl,
    required this.relation,
    required this.career,
  });

  final int id;
  final String name;
  final String nameCn;
  final String imageUrl;
  final String relation;
  final List<String> career;

  String get displayName => nameCn.trim().isNotEmpty ? nameCn : name;
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
    required this.avatarUrl,
    required this.rate,
    required this.comment,
  });

  final int id;
  final String userName;
  final String avatarUrl;
  final int rate;
  final String comment;
}
