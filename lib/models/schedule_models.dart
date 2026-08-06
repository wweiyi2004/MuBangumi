import 'bangumi_models.dart';

/// Local-only weekly arrangement for a broadcast season.
/// Bangumi API supplies subject info; placement is user-owned.
class SeasonKey {
  const SeasonKey({required this.year, required this.quarter});

  /// quarter: 0 winter(1), 1 spring(4), 2 summer(7), 3 autumn(10)
  final int year;
  final int quarter;

  String get id => '$year-Q$quarter';

  String get label {
    final season = switch (quarter) {
      0 => '冬季',
      1 => '春季',
      2 => '夏季',
      _ => '秋季',
    };
    return '$year $season新番';
  }

  int get startMonth => quarter * 3 + 1;

  factory SeasonKey.current([DateTime? now]) {
    final date = now ?? DateTime.now();
    return SeasonKey(year: date.year, quarter: (date.month - 1) ~/ 3);
  }

  factory SeasonKey.fromId(String raw) {
    final match = RegExp(r'^(\d+)-Q([0-3])$').firstMatch(raw.trim());
    if (match == null) return SeasonKey.current();
    return SeasonKey(
      year: int.parse(match.group(1)!),
      quarter: int.parse(match.group(2)!),
    );
  }

  SeasonKey copyWith({int? year, int? quarter}) =>
      SeasonKey(year: year ?? this.year, quarter: quarter ?? this.quarter);

  Map<String, dynamic> toJson() => {'year': year, 'quarter': quarter};

  factory SeasonKey.fromJson(Map<String, dynamic> json) => SeasonKey(
    year: (json['year'] as num?)?.toInt() ?? DateTime.now().year,
    quarter: (json['quarter'] as num?)?.toInt() ?? 0,
  );

  @override
  bool operator ==(Object other) =>
      other is SeasonKey && other.year == year && other.quarter == quarter;

  @override
  int get hashCode => Object.hash(year, quarter);
}

/// weekday: 1=Mon ... 7=Sun (DateTime.weekday). null = 待安排 pool.
class ScheduleItem {
  const ScheduleItem({
    required this.subjectId,
    required this.name,
    required this.nameCn,
    required this.imageUrl,
    this.type = SubjectType.anime,
    this.weekday,
    this.sortOrder = 0,
    this.note = '',
    this.episodeCount = 0,
  });

  final int subjectId;
  final SubjectType type;
  final String name;
  final String nameCn;
  final String imageUrl;
  final int? weekday;
  final int sortOrder;
  final String note;
  final int episodeCount;

  String get displayName => nameCn.trim().isNotEmpty ? nameCn : name;

  bool get isScheduled => weekday != null && weekday! >= 1 && weekday! <= 7;

  ScheduleItem copyWith({
    int? subjectId,
    SubjectType? type,
    String? name,
    String? nameCn,
    String? imageUrl,
    int? weekday,
    bool clearWeekday = false,
    int? sortOrder,
    String? note,
    int? episodeCount,
  }) => ScheduleItem(
    subjectId: subjectId ?? this.subjectId,
    type: type ?? this.type,
    name: name ?? this.name,
    nameCn: nameCn ?? this.nameCn,
    imageUrl: imageUrl ?? this.imageUrl,
    weekday: clearWeekday ? null : weekday ?? this.weekday,
    sortOrder: sortOrder ?? this.sortOrder,
    note: note ?? this.note,
    episodeCount: episodeCount ?? this.episodeCount,
  );

  factory ScheduleItem.fromSubject(
    Subject subject, {
    int? weekday,
    int sortOrder = 0,
  }) => ScheduleItem(
    subjectId: subject.id,
    type: subject.type,
    name: subject.name,
    nameCn: subject.nameCn,
    imageUrl: subject.imageUrl,
    weekday: weekday,
    sortOrder: sortOrder,
    episodeCount: subject.episodeCount,
  );

  factory ScheduleItem.fromCollection(
    UserCollection collection, {
    int? weekday,
    int sortOrder = 0,
  }) => ScheduleItem.fromSubject(
    collection.subject,
    weekday: weekday,
    sortOrder: sortOrder,
  );

  Map<String, dynamic> toJson() => {
    'subjectId': subjectId,
    'type': type.value,
    'name': name,
    'nameCn': nameCn,
    'imageUrl': imageUrl,
    'weekday': weekday,
    'sortOrder': sortOrder,
    'note': note,
    'episodeCount': episodeCount,
  };

  factory ScheduleItem.fromJson(Map<String, dynamic> json) => ScheduleItem(
    subjectId: (json['subjectId'] as num?)?.toInt() ?? 0,
    type: SubjectType.fromValue(
      (json['type'] as num?)?.toInt() ?? SubjectType.anime.value,
    ),
    name: json['name']?.toString() ?? '',
    nameCn: json['nameCn']?.toString() ?? '',
    imageUrl: json['imageUrl']?.toString() ?? '',
    weekday: (json['weekday'] as num?)?.toInt(),
    sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
    note: json['note']?.toString() ?? '',
    episodeCount: (json['episodeCount'] as num?)?.toInt() ?? 0,
  );
}

class SeasonSchedule {
  const SeasonSchedule({required this.season, this.items = const []});

  final SeasonKey season;
  final List<ScheduleItem> items;

  List<ScheduleItem> get unscheduled =>
      items.where((item) => !item.isScheduled).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  List<ScheduleItem> itemsOn(int weekday) =>
      items.where((item) => item.weekday == weekday).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  bool containsSubject(int subjectId) =>
      items.any((item) => item.subjectId == subjectId);

  SeasonSchedule copyWith({SeasonKey? season, List<ScheduleItem>? items}) =>
      SeasonSchedule(season: season ?? this.season, items: items ?? this.items);

  Map<String, dynamic> toJson() => {
    'season': season.toJson(),
    'items': [for (final item in items) item.toJson()],
  };

  factory SeasonSchedule.fromJson(Map<String, dynamic> json) {
    final seasonJson = json['season'];
    final season = seasonJson is Map
        ? SeasonKey.fromJson(Map<String, dynamic>.from(seasonJson))
        : SeasonKey.current();
    final rawItems = json['items'];
    final items = rawItems is List
        ? rawItems
              .whereType<Map>()
              .map((item) => ScheduleItem.fromJson(Map<String, dynamic>.from(item)))
              .where((item) => item.subjectId > 0)
              .toList()
        : const <ScheduleItem>[];
    return SeasonSchedule(season: season, items: items);
  }

  factory SeasonSchedule.empty(SeasonKey season) =>
      SeasonSchedule(season: season);
}

String weekdayLabel(int weekday) => switch (weekday) {
  DateTime.monday => '周一',
  DateTime.tuesday => '周二',
  DateTime.wednesday => '周三',
  DateTime.thursday => '周四',
  DateTime.friday => '周五',
  DateTime.saturday => '周六',
  DateTime.sunday => '周日',
  _ => '待安排',
};

/// Single-character header for dense week grids (phone).
String weekdayShortLabel(int weekday) => switch (weekday) {
  DateTime.monday => '一',
  DateTime.tuesday => '二',
  DateTime.wednesday => '三',
  DateTime.thursday => '四',
  DateTime.friday => '五',
  DateTime.saturday => '六',
  DateTime.sunday => '日',
  _ => '·',
};
