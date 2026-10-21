import 'dart:async';

import '../../models/bangumi_models.dart';
import 'watched_guess.dart';

typedef WatchedCatalogFetch =
    Future<List<Subject>> Function({int? year, int offset, int limit});

class WatchedCatalogBatch {
  const WatchedCatalogBatch(this.subjects, {this.failed = false});
  final List<Subject> subjects;
  final bool failed;
}

/// Public catalog pages only. Selection, collections and account data stay out.
/// Keep at most two pages in flight and yield each as soon as it is ready.
/// Reuse recent successful pages across entries.
class WatchedCatalog {
  WatchedCatalog({required this.fetch, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final WatchedCatalogFetch fetch;
  final DateTime Function() _clock;
  final _pages = <String, ({DateTime at, List<Subject> subjects})>{};
  final _inFlight = <String, Future<WatchedCatalogBatch>>{};
  static const ttl = Duration(minutes: 10);

  List<Subject> get cached => {
    for (final page in _pages.values)
      if (_clock().difference(page.at) < ttl)
        for (final subject in page.subjects) subject.id: subject,
  }.values.toList();

  Stream<WatchedCatalogBatch> load(int currentYear, {int round = 0}) async* {
    final years = watchedGuessSampleYears(currentYear - 15, currentYear);
    final pages = <({int? year, int offset, int limit})>[
      (year: null, offset: round * 72, limit: 24),
      (year: null, offset: round * 72 + 24, limit: 24),
      (year: null, offset: round * 72 + 48, limit: 24),
      for (final year in years) (year: year, offset: round * 8, limit: 8),
    ];
    var cursor = 0;
    final pending = <int, Future<({int index, WatchedCatalogBatch batch})>>{};
    while (cursor < pages.length || pending.isNotEmpty) {
      while (pending.length < 2 && cursor < pages.length) {
        final index = cursor++;
        pending[index] = _page(
          pages[index],
        ).then((batch) => (index: index, batch: batch));
      }
      final ready = await Future.any(pending.values);
      pending.remove(ready.index);
      yield ready.batch;
    }
  }

  Future<WatchedCatalogBatch> _page(({int? year, int offset, int limit}) page) {
    final key = '${page.year}:${page.offset}:${page.limit}';
    final cached = _pages[key];
    if (cached != null && _clock().difference(cached.at) < ttl) {
      return Future.value(WatchedCatalogBatch(cached.subjects));
    }
    return _inFlight.putIfAbsent(key, () async {
      try {
        final subjects = await Future.sync(
          () => fetch(year: page.year, offset: page.offset, limit: page.limit),
        ).timeout(const Duration(seconds: 12));
        _pages.removeWhere((_, value) => _clock().difference(value.at) >= ttl);
        // Bound cache size even when this application survives a year change.
        if (_pages.length >= 12) _pages.remove(_pages.keys.first);
        _pages[key] = (at: _clock(), subjects: List.unmodifiable(subjects));
        return WatchedCatalogBatch(subjects);
      } catch (_) {
        return const WatchedCatalogBatch([], failed: true);
      } finally {
        _inFlight.remove(key);
      }
    });
  }
}
