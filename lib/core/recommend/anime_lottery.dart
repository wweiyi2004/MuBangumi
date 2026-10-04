import 'dart:math';
import '../../models/anime_lottery.dart';
import '../../models/bangumi_models.dart';

/// Randomly samples pages of the rated catalog, then draws from eligible items.
/// A bounded search can return empty without claiming the catalog is exhausted.
class AnimeLottery {
  AnimeLottery({Random? random}) : _random = random ?? Random();
  final Random _random;
  static Set<int> watchedIds(Iterable<UserCollection> collections) => {
    for (final item in collections)
      if (item.type != CollectionType.wish ||
          item.episodeStatus > 0 ||
          item.rate > 0)
        item.subjectId,
  };

  Future<Subject?> draw({
    required AnimePrize prize,
    required Future<AnimeLotteryPage> Function(int offset, int limit) fetch,
    required Set<int> Function() excludedIds,
    required bool Function() isCurrent,
  }) async {
    const size = 50;
    if (!isCurrent()) return null;
    final first = await fetch(0, size);
    if (!isCurrent() || first.total <= 0) return null;
    final pages = (first.total / size).ceil();
    final visited = <int>{};
    for (var attempt = 0; attempt < 6 && visited.length < pages; attempt++) {
      var pageIndex = _random.nextInt(pages);
      while (visited.contains(pageIndex)) {
        pageIndex = (pageIndex + 1) % pages;
      }
      visited.add(pageIndex);
      if (!isCurrent()) return null;
      final page = pageIndex == 0 ? first : await fetch(pageIndex * size, size);
      if (!isCurrent()) return null;
      final excluded = excludedIds();
      final eligible = {
        for (final subject in page.subjects)
          if (prize.permits(subject) && !excluded.contains(subject.id))
            subject.id: subject,
      }.values.toList();
      if (eligible.isNotEmpty) {
        return eligible[_random.nextInt(eligible.length)];
      }
    }
    return null;
  }
}
