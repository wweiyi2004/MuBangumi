import 'dart:math' as math;

import '../../models/bangumi_models.dart';

class ComparedCollection {
  const ComparedCollection({
    required this.mine,
    required this.theirs,
    required this.ratingDifference,
  });

  final UserCollection mine;
  final UserCollection theirs;
  final int ratingDifference;

  double get averageRating => (mine.rate + theirs.rate) / 2;
}

class CollectionComparison {
  const CollectionComparison({
    required this.myTotal,
    required this.theirTotal,
    required this.sharedTotal,
    required this.sharedRatedTotal,
    required this.catalogOverlap,
    required this.ratingCloseness,
    required this.ratingCorrelation,
    required this.similarity,
    required this.commonFavorites,
    required this.biggestDifferences,
  });

  final int myTotal;
  final int theirTotal;
  final int sharedTotal;
  final int sharedRatedTotal;
  final double catalogOverlap;
  final double ratingCloseness;
  final double? ratingCorrelation;
  final double similarity;
  final List<ComparedCollection> commonFavorites;
  final List<ComparedCollection> biggestDifferences;

  int get similarityPercent => (similarity * 100).round();
  int get catalogOverlapPercent => (catalogOverlap * 100).round();
  int get ratingClosenessPercent => (ratingCloseness * 100).round();

  String get confidenceLabel {
    if (sharedRatedTotal >= 20 && sharedTotal >= 40) return '较高';
    if (sharedRatedTotal >= 8 && sharedTotal >= 15) return '中等';
    return '较低';
  }
}

class CollectionInsights {
  const CollectionInsights._();

  static CollectionComparison compare(
    List<UserCollection> mine,
    List<UserCollection> theirs,
  ) {
    final myById = {for (final item in mine) item.subjectId: item};
    final theirById = {for (final item in theirs) item.subjectId: item};
    final sharedIds = myById.keys.toSet().intersection(theirById.keys.toSet());
    final unionSize = myById.keys.toSet().union(theirById.keys.toSet()).length;
    final catalogOverlap = unionSize == 0 ? 0.0 : sharedIds.length / unionSize;

    final rated = <ComparedCollection>[];
    for (final id in sharedIds) {
      final myItem = myById[id]!;
      final theirItem = theirById[id]!;
      if (myItem.rate <= 0 || theirItem.rate <= 0) continue;
      rated.add(
        ComparedCollection(
          mine: myItem,
          theirs: theirItem,
          ratingDifference: (myItem.rate - theirItem.rate).abs(),
        ),
      );
    }

    final meanDifference = rated.isEmpty
        ? 9.0
        : rated.fold<int>(0, (sum, item) => sum + item.ratingDifference) /
              rated.length;
    final ratingCloseness = (1 - meanDifference / 9).clamp(0.0, 1.0);
    final correlation = rated.length < 3
        ? null
        : _pearson(
            rated.map((item) => item.mine.rate.toDouble()).toList(),
            rated.map((item) => item.theirs.rate.toDouble()).toList(),
          );
    final correlationScore = correlation == null
        ? ratingCloseness
        : ((correlation + 1) / 2).clamp(0.0, 1.0);
    final ratingSignal = correlation == null
        ? ratingCloseness
        : correlationScore * .55 + ratingCloseness * .45;
    final ratingReliability = (rated.length / 10).clamp(0.0, 1.0);
    // Small samples fall back toward catalog overlap instead of producing an
    // overconfident percentage from two or three ratings.
    final ratingWeight = .35 + .45 * ratingReliability;
    final similarity = rated.isEmpty
        ? catalogOverlap
        : ratingSignal * ratingWeight + catalogOverlap * (1 - ratingWeight);

    final commonFavorites =
        rated
            .where((item) => item.mine.rate >= 7 && item.theirs.rate >= 7)
            .toList()
          ..sort((a, b) => b.averageRating.compareTo(a.averageRating));
    final biggestDifferences = [...rated]
      ..sort((a, b) {
        final difference = b.ratingDifference.compareTo(a.ratingDifference);
        if (difference != 0) return difference;
        return b.averageRating.compareTo(a.averageRating);
      });

    return CollectionComparison(
      myTotal: myById.length,
      theirTotal: theirById.length,
      sharedTotal: sharedIds.length,
      sharedRatedTotal: rated.length,
      catalogOverlap: catalogOverlap,
      ratingCloseness: ratingCloseness,
      ratingCorrelation: correlation,
      similarity: similarity.clamp(0.0, 1.0),
      commonFavorites: commonFavorites.take(12).toList(),
      biggestDifferences: biggestDifferences
          .where((item) => item.ratingDifference >= 2)
          .take(12)
          .toList(),
    );
  }

  static double? _pearson(List<double> x, List<double> y) {
    final xMean = x.reduce((a, b) => a + b) / x.length;
    final yMean = y.reduce((a, b) => a + b) / y.length;
    var covariance = 0.0;
    var xVariance = 0.0;
    var yVariance = 0.0;
    for (var index = 0; index < x.length; index++) {
      final dx = x[index] - xMean;
      final dy = y[index] - yMean;
      covariance += dx * dy;
      xVariance += dx * dx;
      yVariance += dy * dy;
    }
    if (xVariance == 0 || yVariance == 0) return null;
    return covariance / math.sqrt(xVariance * yVariance);
  }
}

class CollectionStatistics {
  CollectionStatistics(List<UserCollection> collections)
    : total = collections.length,
      ratedTotal = collections.where((item) => item.rate > 0).length,
      averageRating = _averageRating(collections),
      bySubjectType = {
        for (final type in SubjectType.values)
          type: collections.where((item) => item.subject.type == type).length,
      },
      byCollectionType = {
        for (final type in CollectionType.values)
          type: collections.where((item) => item.type == type).length,
      },
      ratingDistribution = {
        for (var rating = 1; rating <= 10; rating++)
          rating: collections.where((item) => item.rate == rating).length,
      },
      years = _years(collections),
      tagCounts = _tagCounts(collections);

  final int total;
  final int ratedTotal;
  final double averageRating;
  final Map<SubjectType, int> bySubjectType;
  final Map<CollectionType, int> byCollectionType;
  final Map<int, int> ratingDistribution;
  final List<int> years;
  final Map<String, int> tagCounts;

  List<UserCollection> forYear(List<UserCollection> collections, int year) {
    final result = collections
        .where((item) => item.updatedAt?.year == year)
        .toList();
    result.sort((a, b) {
      final rate = b.rate.compareTo(a.rate);
      if (rate != 0) return rate;
      return (b.updatedAt ?? DateTime(0)).compareTo(a.updatedAt ?? DateTime(0));
    });
    return result;
  }

  static double _averageRating(List<UserCollection> collections) {
    final ratings = collections.where((item) => item.rate > 0).toList();
    if (ratings.isEmpty) return 0;
    return ratings.fold<int>(0, (sum, item) => sum + item.rate) /
        ratings.length;
  }

  static List<int> _years(List<UserCollection> collections) {
    final values = {
      for (final item in collections)
        if (item.updatedAt != null) item.updatedAt!.year,
    }.toList()..sort((a, b) => b.compareTo(a));
    return values;
  }

  static Map<String, int> _tagCounts(List<UserCollection> collections) {
    final counts = <String, int>{};
    for (final item in collections) {
      for (final raw in item.tags) {
        final tag = raw.trim();
        if (tag.isNotEmpty) counts[tag] = (counts[tag] ?? 0) + 1;
      }
    }
    final entries = counts.entries.toList()
      ..sort((a, b) {
        final count = b.value.compareTo(a.value);
        return count != 0 ? count : a.key.compareTo(b.key);
      });
    return Map.fromEntries(entries);
  }
}
