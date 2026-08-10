import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/insights/collection_insights.dart';
import 'package:mubangumi/models/bangumi_models.dart';

void main() {
  test('identical catalogs and ratings produce full similarity', () {
    final mine = [
      _collection(1, 6),
      _collection(2, 7),
      _collection(3, 8),
      _collection(4, 9),
    ];
    final result = CollectionInsights.compare(mine, [...mine]);

    expect(result.sharedTotal, 4);
    expect(result.sharedRatedTotal, 4);
    expect(result.catalogOverlap, 1);
    expect(result.ratingCorrelation, closeTo(1, .0001));
    expect(result.similarity, closeTo(1, .0001));
  });

  test('opposite ratings score below matching ratings', () {
    final mine = [
      for (var index = 1; index <= 10; index++) _collection(index, index),
    ];
    final opposite = [
      for (var index = 1; index <= 10; index++) _collection(index, 11 - index),
    ];

    final matching = CollectionInsights.compare(mine, [...mine]);
    final different = CollectionInsights.compare(mine, opposite);

    expect(different.ratingCorrelation, closeTo(-1, .0001));
    expect(different.similarity, lessThan(matching.similarity));
    expect(different.similarityPercent, lessThan(50));
  });

  test(
    'constant identical ratings use closeness when correlation is undefined',
    () {
      final mine = [
        for (var index = 1; index <= 4; index++) _collection(index, 8),
      ];
      final result = CollectionInsights.compare(mine, [...mine]);

      expect(result.ratingCorrelation, isNull);
      expect(result.ratingCloseness, 1);
      expect(result.similarity, 1);
    },
  );

  test('statistics aggregate years, tags and ratings', () {
    final collections = [
      _collection(1, 8, year: 2025, tags: const ['科幻', '原创']),
      _collection(2, 0, year: 2025, tags: const ['科幻']),
      _collection(3, 10, year: 2024, tags: const ['治愈']),
    ];
    final statistics = CollectionStatistics(collections);

    expect(statistics.total, 3);
    expect(statistics.ratedTotal, 2);
    expect(statistics.averageRating, 9);
    expect(statistics.years, [2025, 2024]);
    expect(statistics.tagCounts.entries.first.key, '科幻');
    expect(statistics.forYear(collections, 2025), hasLength(2));
  });
}

UserCollection _collection(
  int id,
  int rate, {
  int year = 2025,
  List<String> tags = const [],
}) => UserCollection(
  subjectId: id,
  type: CollectionType.done,
  rate: rate,
  episodeStatus: 12,
  updatedAt: DateTime(year, 6, 1),
  subject: Subject(
    id: id,
    name: 'Subject $id',
    nameCn: '条目 $id',
    imageUrl: '',
    summary: '',
    episodeCount: 12,
    score: 8,
    rank: id,
    date: '$year-01-01',
  ),
  tags: tags,
);
