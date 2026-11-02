import 'dart:convert';
import 'dart:typed_data';
import '../../models/collection_coverage.dart';
import '../../models/bangumi_models.dart';
import 'collection_insights.dart';
import 'collection_year_review.dart';

typedef CollectionSummaryInput = ({
  List<UserCollection> collections,
  SubjectType? type,
  int? year,
  int currentYear,
});

class CollectionSummary {
  CollectionSummary(this.items, this.statistics, this.review);
  final List<UserCollection> items;
  final CollectionStatistics statistics;
  final CollectionYearReview review;
}

/// Pure, sendable calculation shared by direct and background execution.
CollectionSummary summarizeCollections(CollectionSummaryInput input) {
  final items = input.collections
      .where((item) => input.type == null || item.subject.type == input.type)
      .toList();
  final statistics = CollectionStatistics(items);
  final year =
      input.year ??
      (statistics.years.contains(input.currentYear)
          ? input.currentYear
          : statistics.years.firstOrNull ?? input.currentYear);
  return CollectionSummary(
    items,
    statistics,
    CollectionYearReview(items, year),
  );
}

Uint8List encodeCollectionExport(
  ({
    DateTime at,
    String username,
    List<UserCollection> items,
    CollectionCoverage? coverage,
  })
  input,
) => Uint8List.fromList(
  utf8.encode(
    const JsonEncoder.withIndent('  ').convert({
      'schema_version': 1,
      'exported_at': input.at.toIso8601String(),
      'username': input.username,
      'count': input.items.length,
      if (input.coverage != null) 'coverage': input.coverage!.toJson(),
      'collections': [
        for (final item in input.items)
          {
            'subject_id': item.subjectId,
            'subject_type': item.subject.type.value,
            'subject_name': item.subject.name,
            'subject_name_cn': item.subject.nameCn,
            'collection_type': item.type.value,
            'rate': item.rate,
            'episode_status': item.episodeStatus,
            'volume_status': item.volumeStatus,
            'updated_at': item.updatedAt?.toIso8601String(),
            'comment': item.comment,
            'tags': item.tags,
            'private': item.private,
          },
      ],
    }),
  ),
);
