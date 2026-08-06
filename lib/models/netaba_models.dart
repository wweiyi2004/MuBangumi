// Models for netaba.re Bangumi score / rank history.
// https://netaba.re

class NetabaCollectSnapshot {
  const NetabaCollectSnapshot({
    this.wish = 0,
    this.collect = 0,
    this.doing = 0,
    this.onHold = 0,
    this.dropped = 0,
  });

  final int wish;
  final int collect;
  final int doing;
  final int onHold;
  final int dropped;

  int get total => wish + collect + doing + onHold + dropped;

  factory NetabaCollectSnapshot.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const NetabaCollectSnapshot();
    return NetabaCollectSnapshot(
      wish: _int(json['wish']),
      collect: _int(json['collect']),
      doing: _int(json['doing']),
      onHold: _int(json['on_hold']),
      dropped: _int(json['dropped']),
    );
  }
}

class NetabaHistoryPoint {
  const NetabaHistoryPoint({
    required this.recordedAt,
    this.bgmId = 0,
    this.score = 0,
    this.rank = 0,
    this.ratingTotal = 0,
    this.ratingCount = const {},
    this.collect = const NetabaCollectSnapshot(),
  });

  final DateTime recordedAt;
  final int bgmId;
  final double score;
  final int rank;
  final int ratingTotal;
  final Map<int, int> ratingCount;
  final NetabaCollectSnapshot collect;

  bool get hasScore => score > 0;
  bool get hasRank => rank > 0;
  int get oneCount => ratingCount[1] ?? 0;
  int get tenCount => ratingCount[10] ?? 0;

  factory NetabaHistoryPoint.fromJson(Map<String, dynamic> json) {
    final rating = _map(json['rating']);
    final countMap = _map(rating['count']);
    final ratingCount = <int, int>{
      for (var score = 1; score <= 10; score++)
        score: _int(countMap['$score']),
    };
    return NetabaHistoryPoint(
      recordedAt: _date(json['recordedAt']),
      bgmId: _int(json['bgmId']),
      score: _double(json['score'], fallback: _double(rating['score'])),
      rank: _int(json['rank']),
      ratingTotal: _int(rating['total']),
      ratingCount: ratingCount,
      collect: NetabaCollectSnapshot.fromJson(_mapOrNull(json['collect'])),
    );
  }
}

class NetabaSubjectInfo {
  const NetabaSubjectInfo({
    required this.name,
    required this.nameCn,
    this.airDate = '',
    this.score = 0,
    this.rank = 0,
    this.imageUrl = '',
  });

  final String name;
  final String nameCn;
  final String airDate;
  final double score;
  final int rank;
  final String imageUrl;

  String get displayName => nameCn.trim().isNotEmpty ? nameCn : name;

  factory NetabaSubjectInfo.fromJson(Map<String, dynamic> json) {
    final images = _map(json['images']);
    final rating = _map(json['rating']);
    return NetabaSubjectInfo(
      name: _string(json['name']),
      nameCn: _string(json['name_cn']),
      airDate: _string(json['air_date']),
      score: _double(json['score'], fallback: _double(rating['score'])),
      rank: _int(json['rank'], fallback: _int(rating['rank'])),
      imageUrl: _string(
        images['large'],
        fallback: _string(
          images['common'],
          fallback: _string(images['medium']),
        ),
      ),
    );
  }
}

class NetabaSubjectHistory {
  const NetabaSubjectHistory({
    required this.subject,
    required this.history,
  });

  final NetabaSubjectInfo subject;
  final List<NetabaHistoryPoint> history;

  /// Score / rank / watching deltas over roughly the last [days] samples.
  NetabaDelta? delta({int days = 30}) {
    if (history.length < 2) return null;
    final latest = history.last;
    final target = latest.recordedAt.subtract(Duration(days: days));
    NetabaHistoryPoint? baseline;
    for (var i = history.length - 1; i >= 0; i--) {
      final point = history[i];
      if (!point.recordedAt.isAfter(target)) {
        baseline = point;
        break;
      }
    }
    baseline ??= history.first;
    if (identical(baseline, latest)) return null;
    return NetabaDelta(
      score: latest.score - baseline.score,
      rank: latest.hasRank && baseline.hasRank
          ? latest.rank - baseline.rank
          : 0,
      watching: latest.collect.doing - baseline.collect.doing,
      rated: latest.ratingTotal - baseline.ratingTotal,
      days: latest.recordedAt.difference(baseline.recordedAt).inDays,
    );
  }

  List<NetabaChartPoint> scoreSeries({int maxPoints = 360}) {
    return _downsample(
      [
        for (final point in history)
          if (point.hasScore)
            NetabaChartPoint(point.recordedAt, point.score),
      ],
      maxPoints: maxPoints,
    );
  }

  List<NetabaChartPoint> rankSeries({int maxPoints = 360}) {
    return _downsample(
      [
        for (final point in history)
          if (point.hasRank)
            NetabaChartPoint(point.recordedAt, point.rank.toDouble()),
      ],
      maxPoints: maxPoints,
    );
  }

  List<NetabaChartPoint> seriesFor(
    NetabaHistoryMetric metric, {
    int maxPoints = 360,
  }) {
    switch (metric) {
      case NetabaHistoryMetric.score:
        return scoreSeries(maxPoints: maxPoints);
      case NetabaHistoryMetric.rank:
        return rankSeries(maxPoints: maxPoints);
      case NetabaHistoryMetric.watching:
        return _downsample(
          [
            for (final point in history)
              if (point.collect.doing > 0 || point.collect.total > 0)
                NetabaChartPoint(
                  point.recordedAt,
                  point.collect.doing.toDouble(),
                ),
          ],
          maxPoints: maxPoints,
        );
      case NetabaHistoryMetric.collect:
        return _downsample(
          [
            for (final point in history)
              if (point.collect.collect > 0 || point.collect.total > 0)
                NetabaChartPoint(
                  point.recordedAt,
                  point.collect.collect.toDouble(),
                ),
          ],
          maxPoints: maxPoints,
        );
      case NetabaHistoryMetric.rated:
        return _downsample(
          [
            for (final point in history)
              if (point.ratingTotal > 0)
                NetabaChartPoint(
                  point.recordedAt,
                  point.ratingTotal.toDouble(),
                ),
          ],
          maxPoints: maxPoints,
        );
    }
  }

  factory NetabaSubjectHistory.fromJson(Map<String, dynamic> json) {
    final historyJson = json['history'];
    return NetabaSubjectHistory(
      subject: NetabaSubjectInfo.fromJson(_map(json['subject'])),
      history: historyJson is List
          ? [
              for (final item in historyJson)
                if (item is Map)
                  NetabaHistoryPoint.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
            ]
          : const [],
    );
  }
}

enum NetabaHistoryMetric { score, rank, watching, collect, rated }

class NetabaChartPoint {
  const NetabaChartPoint(this.at, this.value);

  final DateTime at;
  final double value;
}

class NetabaDelta {
  const NetabaDelta({
    required this.score,
    required this.rank,
    required this.watching,
    required this.rated,
    required this.days,
  });

  final double score;
  /// Positive means rank number increased (worse). Negative = climbed.
  final int rank;
  final int watching;
  final int rated;
  final int days;
}

class NetabaTrendingItem {
  const NetabaTrendingItem({
    required this.bgmId,
    required this.scoreDelta,
    required this.name,
    required this.nameCn,
    required this.history,
  });

  final int bgmId;
  /// Score change over the trending window (positive = improved).
  final double scoreDelta;
  final String name;
  final String nameCn;
  final List<NetabaHistoryPoint> history;

  String get displayName => nameCn.trim().isNotEmpty ? nameCn : name;

  double get latestScore {
    for (var i = history.length - 1; i >= 0; i--) {
      if (history[i].hasScore) return history[i].score;
    }
    return 0;
  }

  int get latestRank {
    for (var i = history.length - 1; i >= 0; i--) {
      if (history[i].hasRank) return history[i].rank;
    }
    return 0;
  }

  List<NetabaChartPoint> sparkline({int maxPoints = 60}) {
    return _downsample(
      [
        for (final point in history)
          if (point.hasScore)
            NetabaChartPoint(point.recordedAt, point.score),
      ],
      maxPoints: maxPoints,
    );
  }

  factory NetabaTrendingItem.fromJson(Map<String, dynamic> json) {
    final subject = _map(json['subject']);
    final historyJson = json['history'];
    return NetabaTrendingItem(
      bgmId: _int(json['bgmId']),
      scoreDelta: _double(json['score']),
      name: _string(subject['name']),
      nameCn: _string(subject['name_cn']),
      history: historyJson is List
          ? [
              for (final item in historyJson)
                if (item is Map)
                  NetabaHistoryPoint.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
            ]
          : const [],
    );
  }
}

class NetabaTrending {
  const NetabaTrending({
    this.up = const [],
    this.down = const [],
    this.done = const [],
  });

  /// Rising scores (口碑提升).
  final List<NetabaTrendingItem> up;
  /// Falling scores.
  final List<NetabaTrendingItem> down;
  /// Finished / stable-ish recent titles.
  final List<NetabaTrendingItem> done;

  factory NetabaTrending.fromJson(Map<String, dynamic> json) {
    List<NetabaTrendingItem> parseList(Object? raw) {
      if (raw is! List) return const [];
      return [
        for (final item in raw)
          if (item is Map)
            NetabaTrendingItem.fromJson(Map<String, dynamic>.from(item)),
      ];
    }

    return NetabaTrending(
      up: parseList(json['up']),
      down: parseList(json['down']),
      done: parseList(json['done']),
    );
  }
}

List<NetabaChartPoint> _downsample(
  List<NetabaChartPoint> points, {
  required int maxPoints,
}) {
  if (points.length <= maxPoints || maxPoints < 3) return points;
  final result = <NetabaChartPoint>[points.first];
  final step = (points.length - 2) / (maxPoints - 2);
  for (var i = 1; i < maxPoints - 1; i++) {
    result.add(points[(i * step).round().clamp(1, points.length - 2)]);
  }
  result.add(points.last);
  return result;
}

Map<String, dynamic> _map(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return const {};
}

Map<String, dynamic>? _mapOrNull(Object? value) {
  if (value == null) return null;
  final map = _map(value);
  return map.isEmpty ? null : map;
}

String _string(Object? value, {String fallback = ''}) {
  if (value == null) return fallback;
  final text = value.toString().trim();
  return text.isEmpty ? fallback : text;
}

int _int(Object? value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

double _double(Object? value, {double fallback = 0}) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}

DateTime _date(Object? value) {
  if (value is DateTime) return value;
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value)?.toLocal() ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }
  if (value is int) {
    // seconds vs millis
    final ms = value > 20000000000 ? value : value * 1000;
    return DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
  }
  return DateTime.fromMillisecondsSinceEpoch(0);
}
