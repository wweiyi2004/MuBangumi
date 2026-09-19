import 'bangumi_models.dart';
import 'snapshot_items.dart';

enum CollectionCompleteness { complete, partial, unknown }

/// Describes the exact effective list, including local pending edits. A cached
/// subset must never silently claim to be the complete remote collection.
class CollectionCoverage {
  CollectionCoverage({
    required this.loadedCount,
    this.sourceTotal,
    this.completeness = CollectionCompleteness.unknown,
    Set<SubjectType> loadedTypes = const {},
    this.savedAt,
  }) : loadedTypes = Set.unmodifiable(loadedTypes);
  final int loadedCount;
  final int? sourceTotal;
  final CollectionCompleteness completeness;
  final Set<SubjectType> loadedTypes;
  final DateTime? savedAt;
  bool get isComplete => completeness == CollectionCompleteness.complete;
  String get notice => sourceTotal != null && sourceTotal! > loadedCount
      ? '已加载 $loadedCount / $sourceTotal 条收藏，统计和导出仅包含这些记录'
      : '已加载 $loadedCount 条收藏，完整范围尚未确认；统计和导出仅包含这些记录';

  CollectionCoverage withCount(int count) => CollectionCoverage(
    loadedCount: count,
    sourceTotal: isComplete
        ? count
        : count == loadedCount
        ? sourceTotal
        : null,
    completeness: completeness,
    loadedTypes: loadedTypes,
    savedAt: savedAt,
  );
  CollectionCoverage retained(int count, DateTime saved) => CollectionCoverage(
    loadedCount: count,
    sourceTotal: sourceTotal ?? (isComplete ? loadedCount : null),
    completeness: count < loadedCount
        ? CollectionCompleteness.partial
        : completeness,
    loadedTypes: count < loadedCount ? const {} : loadedTypes,
    savedAt: saved,
  );
  Map<String, dynamic> toJson() => {
    'loaded_count': loadedCount,
    'source_total': sourceTotal,
    'completeness': completeness.name,
    'loaded_types': [for (final t in loadedTypes) t.value],
    'saved_at': savedAt?.toIso8601String(),
  };
  factory CollectionCoverage.fromJson(
    Object? raw, {
    required int loadedCount,
    DateTime? savedAt,
  }) {
    final data = raw is Map ? raw : const {};
    final total = data['source_total'];
    var kind =
        CollectionCompleteness.values
            .where((v) => v.name == data['completeness'])
            .firstOrNull ??
        CollectionCompleteness.unknown;
    if (kind == CollectionCompleteness.complete && total != loadedCount) {
      kind = CollectionCompleteness.unknown;
    }
    return CollectionCoverage(
      loadedCount: loadedCount,
      sourceTotal: total is int && total >= loadedCount ? total : null,
      completeness: kind,
      loadedTypes: {
        for (final t in SubjectType.values)
          if (data['loaded_types'] is List &&
              (data['loaded_types'] as List).contains(t.value))
            t,
      },
      savedAt: savedAt,
    );
  }
}

class CollectionSnapshot extends SnapshotItems<UserCollection> {
  CollectionSnapshot(super.source, {required this.coverage})
    : super(savedAt: coverage.savedAt ?? DateTime.now());
  final CollectionCoverage coverage;
}
