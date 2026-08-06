import '../../models/bangumi_models.dart';

/// Client-side “番会荐” preference + ranking helpers.
class FanTasteProfile {
  const FanTasteProfile({
    required this.topTags,
    required this.ownedIds,
    this.likedCount = 0,
    this.avgLikedScore = 0,
  });

  /// Tags ranked by preference weight (highest first).
  final List<String> topTags;
  final Set<int> ownedIds;
  final int likedCount;
  final double avgLikedScore;

  bool get hasTaste => topTags.isNotEmpty && likedCount > 0;
}

class FanRecommendRequest {
  const FanRecommendRequest({
    this.wishText = '',
    this.selectedTags = const [],
    this.minimumRating = 7,
    this.startYear = 0,
    this.useTaste = true,
    this.subjectType = SubjectType.anime,
  });

  final String wishText;
  final List<String> selectedTags;
  final int minimumRating;
  final int startYear;
  final bool useTaste;
  final SubjectType subjectType;

  List<String> get effectiveTags {
    final seen = <String>{};
    final out = <String>[];
    for (final tag in [
      ...selectedTags,
      ...FanRecommendEngine._tagsFromWish(wishText),
    ]) {
      final t = tag.trim();
      if (t.isEmpty || !seen.add(t)) continue;
      out.add(t);
    }
    return out;
  }

  String get keyword {
    // Keep free-text that isn't already covered by selected tags.
    final tags = selectedTags.map((t) => t.trim()).where((t) => t.isNotEmpty);
    var text = wishText.trim();
    for (final tag in tags) {
      text = text.replaceAll(tag, ' ');
    }
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}

class FanRecommendItem {
  const FanRecommendItem({
    required this.subject,
    required this.score,
    required this.reasons,
    required this.matchedTags,
  });

  final Subject subject;
  final double score;
  final List<String> reasons;
  final List<String> matchedTags;
}

class FanRecommendEngine {
  FanRecommendEngine._();

  /// Common anime taste chips for “说出需求”.
  static const presetTags = <String>[
    '治愈',
    '恋爱',
    '日常',
    '搞笑',
    '校园',
    '奇幻',
    '科幻',
    '战斗',
    '热血',
    '悬疑',
    '异世界',
    '百合',
    '音乐',
    '运动',
    '致郁',
    '萌',
    '剧情',
    '原创',
  ];

  /// Build taste from the user's Bangumi collections.
  static FanTasteProfile buildTaste(
    List<UserCollection> collections, {
    SubjectType type = SubjectType.anime,
  }) {
    // Exclude anything already in the library (any type) from recommendations.
    final owned = <int>{
      for (final c in collections)
        if (c.subjectId > 0) c.subjectId,
    };

    final weights = <String, double>{};
    var likedCount = 0;
    var scoredCount = 0;
    var scoreSum = 0.0;

    for (final c in collections) {
      if (c.subject.type != type) continue;
      // Prefer finished / watching with a score, or strong wish lists.
      final personal = c.rate;
      final public = c.subject.score;
      final liked =
          (personal >= 7) ||
          (personal == 0 &&
              public >= 7.2 &&
              (c.type == CollectionType.done ||
                  c.type == CollectionType.doing));
      if (!liked && c.type != CollectionType.wish) continue;

      likedCount++;
      if (personal > 0) {
        scoreSum += personal;
        scoredCount++;
      }
      final weight = personal > 0
          ? personal.toDouble()
          : (c.type == CollectionType.wish ? 6.5 : public.clamp(6.5, 10));

      final tags = <String>{
        ...c.tags,
        ...c.subject.tags,
        ...c.subject.metaTags,
      };
      for (final raw in tags) {
        final tag = raw.trim();
        if (!_isUsefulTag(tag)) continue;
        weights[tag] = (weights[tag] ?? 0) + weight;
      }
    }

    final ranked = weights.entries.toList()
      ..sort((a, b) {
        final byW = b.value.compareTo(a.value);
        if (byW != 0) return byW;
        return a.key.compareTo(b.key);
      });

    return FanTasteProfile(
      topTags: [for (final e in ranked.take(12)) e.key],
      ownedIds: owned,
      likedCount: likedCount,
      avgLikedScore: scoredCount == 0 ? 0 : scoreSum / scoredCount,
    );
  }

  /// Rank candidates from Bangumi search pages.
  static List<FanRecommendItem> rank({
    required List<Subject> candidates,
    required FanTasteProfile taste,
    required FanRecommendRequest request,
    int limit = 24,
  }) {
    final wanted = {
      for (final t in [
        if (request.useTaste) ...taste.topTags.take(8),
        ...request.effectiveTags,
      ])
        t.trim(),
    }..removeWhere((t) => t.isEmpty);

    final keyword = request.keyword.toLowerCase();
    final scored = <FanRecommendItem>[];

    for (final subject in candidates) {
      if (subject.id <= 0) continue;
      if (taste.ownedIds.contains(subject.id)) continue;
      if (request.minimumRating > 0 && subject.score > 0) {
        if (subject.score + 1e-6 < request.minimumRating) continue;
      }
      if (request.startYear > 0 && subject.date.length >= 4) {
        final year = int.tryParse(subject.date.substring(0, 4)) ?? 0;
        if (year > 0 && year < request.startYear) continue;
      }

      final subjectTags = {
        ...subject.tags,
        ...subject.metaTags,
      }.map((t) => t.trim()).where((t) => t.isNotEmpty).toSet();

      final matched = subjectTags.intersection(wanted).toList()
        ..sort((a, b) => a.compareTo(b));

      var score = 0.0;
      // Public quality.
      if (subject.score > 0) score += subject.score * 8;
      if (subject.rank > 0 && subject.rank < 3000) {
        score += (3000 - subject.rank) / 300;
      }
      if (subject.ratingTotal > 0) {
        score += (subject.ratingTotal.clamp(0, 5000)) / 400;
      }

      // Taste / request match.
      score += matched.length * 14;
      for (var i = 0; i < taste.topTags.length && i < 8; i++) {
        final tag = taste.topTags[i];
        if (subjectTags.contains(tag)) {
          score += 10 - i; // earlier tags matter more
        }
      }

      // Keyword soft match on names.
      if (keyword.isNotEmpty) {
        final blob =
            '${subject.name} ${subject.nameCn} ${subject.summary}'.toLowerCase();
        if (blob.contains(keyword)) score += 18;
        for (final part in keyword.split(RegExp(r'[\s,，、]+'))) {
          if (part.length >= 2 && blob.contains(part)) score += 6;
        }
      }

      final reasons = <String>[];
      if (matched.isNotEmpty) {
        reasons.add('标签：${matched.take(3).join(' · ')}');
      }
      if (subject.score > 0) {
        reasons.add('评分 ${subject.score.toStringAsFixed(1)}');
      }
      if (subject.rank > 0 && subject.rank <= 500) {
        reasons.add('排名 #${subject.rank}');
      }
      if (request.useTaste && matched.isNotEmpty) {
        reasons.add('贴近你的喜好');
      }
      if (keyword.isNotEmpty &&
          ('${subject.nameCn}${subject.name}'.toLowerCase().contains(
            keyword,
          ))) {
        reasons.add('符合你的描述');
      }
      if (reasons.isEmpty) reasons.add('综合热度推荐');

      scored.add(
        FanRecommendItem(
          subject: subject,
          score: score,
          reasons: reasons.take(3).toList(),
          matchedTags: matched,
        ),
      );
    }

    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return b.subject.score.compareTo(a.subject.score);
    });

    // Diversity: avoid too many near-identical titles in a row.
    final out = <FanRecommendItem>[];
    final seenNames = <String>{};
    for (final item in scored) {
      final key = item.subject.displayName
          .replaceAll(RegExp(r'[\s:：\-_]'), '')
          .toLowerCase();
      if (key.isNotEmpty && !seenNames.add(key)) continue;
      out.add(item);
      if (out.length >= limit) break;
    }
    return out;
  }

  /// Suggest search keywords / tag queries to hit Bangumi API with.
  static List<({String keyword, List<String> tags})> buildSearchJobs(
    FanRecommendRequest request,
    FanTasteProfile taste,
  ) {
    final jobs = <({String keyword, List<String> tags})>[];
    final keyword = request.keyword;
    final tags = request.effectiveTags;

    if (keyword.isNotEmpty) {
      jobs.add((keyword: keyword, tags: tags.take(2).toList()));
      if (tags.isNotEmpty) {
        jobs.add((keyword: keyword, tags: const []));
      }
    }

    // Tag-only searches (Bangumi supports filter.tag).
    final tagPool = <String>[
      ...tags,
      if (request.useTaste) ...taste.topTags,
    ];
    final seen = <String>{};
    for (final tag in tagPool) {
      final t = tag.trim();
      if (t.isEmpty || !seen.add(t)) continue;
      jobs.add((keyword: '', tags: [t]));
      if (seen.length >= 5) break;
    }

    // Pair first two tags for finer taste.
    if (request.useTaste && taste.topTags.length >= 2) {
      jobs.add((
        keyword: '',
        tags: taste.topTags.take(2).toList(),
      ));
    }

    // Fallback: empty keyword ranked-ish search via generic words.
    if (jobs.isEmpty) {
      jobs.add((keyword: '动画', tags: const []));
      jobs.add((keyword: '推荐', tags: const []));
    }

    // Deduplicate jobs.
    final unique = <String, ({String keyword, List<String> tags})>{};
    for (final job in jobs) {
      final key = '${job.keyword}|${job.tags.join(',')}';
      unique.putIfAbsent(key, () => job);
    }
    return unique.values.take(8).toList();
  }

  static List<String> _tagsFromWish(String wish) {
    final text = wish.trim();
    if (text.isEmpty) return const [];
    final found = <String>[];
    for (final tag in presetTags) {
      if (text.contains(tag)) found.add(tag);
    }
    // Split free fragments.
    for (final part in text.split(RegExp(r'[\s,，、/|]+'))) {
      final t = part.trim();
      if (t.length >= 2 && t.length <= 12 && !found.contains(t)) {
        // Skip pure year / pure numbers.
        if (RegExp(r'^\d{4}$').hasMatch(t)) continue;
        found.add(t);
      }
    }
    return found.take(6).toList();
  }

  static bool _isUsefulTag(String tag) {
    if (tag.isEmpty || tag.length > 16) return false;
    // Drop ultra-generic or format tags.
    const noise = {
      'TV',
      'WEB',
      'OVA',
      'OAD',
      '剧场版',
      '日本',
      '动画',
      'Anime',
      'TVA',
      '续作',
      '原创',
      '漫改',
      '小说改',
      '游戏改',
    };
    if (noise.contains(tag)) return false;
    if (RegExp(r'^\d+$').hasMatch(tag)) return false;
    return true;
  }
}
