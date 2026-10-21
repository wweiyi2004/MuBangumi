import 'dart:math';
import '../../models/anime_lottery.dart';
import '../../models/bangumi_models.dart';

/// Randomly samples pages of the rated catalog, then draws from eligible items.
/// A bounded search can return empty without claiming the catalog is exhausted.
class AnimeLottery {
  AnimeLottery({Random? random, DateTime Function()? clock})
    : _random = random ?? Random(),
      _clock = clock ?? DateTime.now;
  final Random _random;
  final DateTime Function() _clock;
  final _pages = <(AnimePrize, int), ({DateTime at, AnimeLotteryPage page})>{};
  final _drawn = <int>{};
  static const cacheLifetime = Duration(minutes: 5);

  /// Public pages can be reused; draw history belongs to the active account.
  void resetHistory() => _drawn.clear();

  Subject? _choose(
    AnimePrize prize,
    Iterable<Subject> subjects,
    Set<int> excluded,
  ) {
    final eligible = {
      for (final subject in subjects)
        if (prize.permits(subject) &&
            !excluded.contains(subject.id) &&
            !_drawn.contains(subject.id))
          subject.id: subject,
    }.values.toList();
    if (eligible.isEmpty) return null;
    final result = eligible[_random.nextInt(eligible.length)];
    if (_drawn.length >= 2000) _drawn.remove(_drawn.first);
    _drawn.add(result.id);
    return result;
  }

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
    _pages.removeWhere(
      (_, entry) => _clock().difference(entry.at) >= cacheLifetime,
    );
    final warm = _choose(
      prize,
      _pages.entries
          .where((entry) => entry.key.$1 == prize)
          .expand((entry) => entry.value.page.subjects),
      excludedIds(),
    );
    if (warm != null) return warm;
    Future<AnimeLotteryPage> pageAt(int offset) async {
      final key = (prize, offset);
      final cached = _pages[key];
      if (cached != null) return cached.page;
      final page = await fetch(offset, size);
      // A stale request must not mutate this draw's public cache/history.
      if (isCurrent()) {
        if (_pages.length >= 12) _pages.remove(_pages.keys.first);
        _pages[key] = (at: _clock(), page: page);
      }
      return page;
    }

    final first = await pageAt(0);
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
      final page = pageIndex == 0 ? first : await pageAt(pageIndex * size);
      if (!isCurrent()) return null;
      final excluded = excludedIds();
      final result = _choose(prize, page.subjects, excluded);
      if (result != null) return result;
    }
    return null;
  }
}
