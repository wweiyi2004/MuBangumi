// Local RSS (torrent-site) update sources bound to schedule subjects.
// App-only reminders; no download engine.

class RssSource {
  const RssSource({
    required this.id,
    required this.name,
    required this.url,
    this.enabled = true,
    this.etag = '',
    this.lastModified = '',
    this.lastFetchAt,
    this.lastError = '',
    this.createdAt,
  });

  final int id;
  final String name;
  final String url;
  final bool enabled;
  final String etag;
  final String lastModified;
  final DateTime? lastFetchAt;
  final String lastError;
  final DateTime? createdAt;

  RssSource copyWith({
    int? id,
    String? name,
    String? url,
    bool? enabled,
    String? etag,
    String? lastModified,
    DateTime? lastFetchAt,
    String? lastError,
    DateTime? createdAt,
    bool clearError = false,
  }) => RssSource(
    id: id ?? this.id,
    name: name ?? this.name,
    url: url ?? this.url,
    enabled: enabled ?? this.enabled,
    etag: etag ?? this.etag,
    lastModified: lastModified ?? this.lastModified,
    lastFetchAt: lastFetchAt ?? this.lastFetchAt,
    lastError: clearError ? '' : lastError ?? this.lastError,
    createdAt: createdAt ?? this.createdAt,
  );

  Map<String, Object?> toRow() => {
    'id': id == 0 ? null : id,
    'name': name,
    'url': url,
    'enabled': enabled ? 1 : 0,
    'etag': etag,
    'last_modified': lastModified,
    'last_fetch_at': lastFetchAt?.millisecondsSinceEpoch,
    'last_error': lastError,
    'created_at':
        (createdAt ?? DateTime.now()).millisecondsSinceEpoch,
  };

  factory RssSource.fromRow(Map<String, Object?> row) => RssSource(
    id: (row['id'] as num?)?.toInt() ?? 0,
    name: row['name']?.toString() ?? '',
    url: row['url']?.toString() ?? '',
    enabled: (row['enabled'] as num?)?.toInt() != 0,
    etag: row['etag']?.toString() ?? '',
    lastModified: row['last_modified']?.toString() ?? '',
    lastFetchAt: _ms(row['last_fetch_at']),
    lastError: row['last_error']?.toString() ?? '',
    createdAt: _ms(row['created_at']),
  );
}

/// Binds one RSS source to one Bangumi subject (usually a schedule entry).
class RssBinding {
  const RssBinding({
    required this.id,
    required this.sourceId,
    required this.subjectId,
    required this.subjectName,
    this.seasonKey = '',
    this.matchKeywords = '',
    this.excludeKeywords = '合集,NC-OP,NC-ED,NCOP,NCED,SP,特典',
    this.enabled = true,
    this.createdAt,
  });

  final int id;
  final int sourceId;
  final int subjectId;
  final String subjectName;
  final String seasonKey;

  /// Comma/space separated; all non-empty tokens must appear (case-insensitive).
  /// Empty → fall back to [subjectName] tokens.
  final String matchKeywords;

  /// Comma/space separated; if any token hits, item is rejected.
  final String excludeKeywords;
  final bool enabled;
  final DateTime? createdAt;

  List<String> get matchTokens => _tokens(
    matchKeywords.trim().isEmpty ? subjectName : matchKeywords,
  );

  List<String> get excludeTokens => _tokens(excludeKeywords);

  bool matchesTitle(String title) {
    final lower = title.toLowerCase();
    final excludes = excludeTokens;
    for (final token in excludes) {
      if (lower.contains(token.toLowerCase())) return false;
    }
    final includes = matchTokens;
    if (includes.isEmpty) return false;
    for (final token in includes) {
      if (!lower.contains(token.toLowerCase())) return false;
    }
    return true;
  }

  RssBinding copyWith({
    int? id,
    int? sourceId,
    int? subjectId,
    String? subjectName,
    String? seasonKey,
    String? matchKeywords,
    String? excludeKeywords,
    bool? enabled,
    DateTime? createdAt,
  }) => RssBinding(
    id: id ?? this.id,
    sourceId: sourceId ?? this.sourceId,
    subjectId: subjectId ?? this.subjectId,
    subjectName: subjectName ?? this.subjectName,
    seasonKey: seasonKey ?? this.seasonKey,
    matchKeywords: matchKeywords ?? this.matchKeywords,
    excludeKeywords: excludeKeywords ?? this.excludeKeywords,
    enabled: enabled ?? this.enabled,
    createdAt: createdAt ?? this.createdAt,
  );

  Map<String, Object?> toRow() => {
    'id': id == 0 ? null : id,
    'source_id': sourceId,
    'subject_id': subjectId,
    'subject_name': subjectName,
    'season_key': seasonKey,
    'match_keywords': matchKeywords,
    'exclude_keywords': excludeKeywords,
    'enabled': enabled ? 1 : 0,
    'created_at':
        (createdAt ?? DateTime.now()).millisecondsSinceEpoch,
  };

  factory RssBinding.fromRow(Map<String, Object?> row) => RssBinding(
    id: (row['id'] as num?)?.toInt() ?? 0,
    sourceId: (row['source_id'] as num?)?.toInt() ?? 0,
    subjectId: (row['subject_id'] as num?)?.toInt() ?? 0,
    subjectName: row['subject_name']?.toString() ?? '',
    seasonKey: row['season_key']?.toString() ?? '',
    matchKeywords: row['match_keywords']?.toString() ?? '',
    excludeKeywords: row['exclude_keywords']?.toString() ?? '',
    enabled: (row['enabled'] as num?)?.toInt() != 0,
    createdAt: _ms(row['created_at']),
  );
}

/// A matched RSS entry kept only when bound to a schedule subject.
class RssItem {
  const RssItem({
    required this.id,
    required this.sourceId,
    required this.subjectId,
    required this.guid,
    required this.title,
    required this.link,
    this.publishedAt,
    this.read = false,
    this.firstSeenAt,
  });

  final int id;
  final int sourceId;
  final int subjectId;
  final String guid;
  final String title;
  final String link;
  final DateTime? publishedAt;
  final bool read;
  final DateTime? firstSeenAt;

  RssItem copyWith({bool? read}) => RssItem(
    id: id,
    sourceId: sourceId,
    subjectId: subjectId,
    guid: guid,
    title: title,
    link: link,
    publishedAt: publishedAt,
    read: read ?? this.read,
    firstSeenAt: firstSeenAt,
  );

  Map<String, Object?> toRow() => {
    'id': id == 0 ? null : id,
    'source_id': sourceId,
    'subject_id': subjectId,
    'guid': guid,
    'title': title,
    'link': link,
    'published_at': publishedAt?.millisecondsSinceEpoch,
    'read': read ? 1 : 0,
    'first_seen_at':
        (firstSeenAt ?? DateTime.now()).millisecondsSinceEpoch,
  };

  factory RssItem.fromRow(Map<String, Object?> row) => RssItem(
    id: (row['id'] as num?)?.toInt() ?? 0,
    sourceId: (row['source_id'] as num?)?.toInt() ?? 0,
    subjectId: (row['subject_id'] as num?)?.toInt() ?? 0,
    guid: row['guid']?.toString() ?? '',
    title: row['title']?.toString() ?? '',
    link: row['link']?.toString() ?? '',
    publishedAt: _ms(row['published_at']),
    read: (row['read'] as num?)?.toInt() != 0,
    firstSeenAt: _ms(row['first_seen_at']),
  );
}

/// Parsed feed entry before matching (not persisted unless bound).
class RssFeedEntry {
  const RssFeedEntry({
    required this.guid,
    required this.title,
    required this.link,
    this.publishedAt,
  });

  final String guid;
  final String title;
  final String link;
  final DateTime? publishedAt;
}

DateTime? _ms(Object? raw) {
  if (raw is num) {
    final value = raw.toInt();
    if (value <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(value);
  }
  return null;
}

List<String> _tokens(String raw) {
  return raw
      .split(RegExp(r'[,，;；\s]+'))
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList();
}
