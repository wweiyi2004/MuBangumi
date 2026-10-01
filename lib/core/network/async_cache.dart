/// Bounded, expiring results with one active request per key.
/// Invalidating a key also prevents an older request from repopulating it.
class AsyncCache<T> {
  AsyncCache({
    required this.maxAge,
    required this.maxEntries,
    this.maxWeight,
    this.weightOf,
    DateTime Function()? now,
  }) : assert(maxEntries > 0),
       assert(maxWeight == null || (maxWeight > 0 && weightOf != null)),
       _now = now ?? DateTime.now;

  final Duration maxAge;
  final int maxEntries;

  /// Estimated retained bytes, rather than serialized payload size.
  final int? maxWeight;
  final int Function(T value)? weightOf;
  final DateTime Function() _now;
  final _values = <String, ({T value, DateTime savedAt, int weight})>{};
  final _pending = <String, Future<T>>{};
  int _weight = 0;

  int get cachedWeight => _weight;
  int get cachedEntries => _values.length;

  void _removeValue(String key) {
    final removed = _values.remove(key);
    if (removed != null) _weight -= removed.weight;
  }

  void _expire(DateTime now) {
    final expired = _values.entries
        .where((entry) => now.difference(entry.value.savedAt) >= maxAge)
        .map((entry) => entry.key)
        .toList();
    for (final key in expired) {
      _removeValue(key);
    }
  }

  Future<T> get(String key, Future<T> Function() load, {bool refresh = false}) {
    final pending = _pending[key];
    if (pending != null) return pending;
    final now = _now();
    _expire(now);
    final cached = _values[key];
    if (!refresh && cached != null) {
      _values.remove(key);
      _values[key] = cached;
      return Future.value(cached.value);
    }
    _removeValue(key);
    late final Future<T> request;
    request = Future<T>.sync(load)
        .then((value) {
          if (identical(_pending[key], request)) {
            final completedAt = _now();
            _expire(completedAt);
            final weight = weightOf?.call(value) ?? 0;
            // A large response remains usable by its caller without displacing
            // every useful cached page or being retained after navigation.
            if (maxWeight == null || weight <= maxWeight!) {
              _values[key] = (
                value: value,
                savedAt: completedAt,
                weight: weight,
              );
              _weight += weight;
              while (_values.length > maxEntries ||
                  (maxWeight != null && _weight > maxWeight!)) {
                _removeValue(_values.keys.first);
              }
            }
          }
          return value;
        })
        .whenComplete(() {
          if (identical(_pending[key], request)) _pending.remove(key);
        });
    _pending[key] = request;
    return request;
  }

  void removeWhere(bool Function(String key) predicate) {
    for (final key in _values.keys.where(predicate).toList()) {
      _removeValue(key);
    }
    _pending.removeWhere((key, _) => predicate(key));
  }

  void clear() {
    clearCompleted();
    _pending.clear();
  }

  /// Keep request coalescing and stale-response guards during memory pressure.
  void clearCompleted() {
    _values.clear();
    _weight = 0;
  }
}

/// Conservative approximation of a decoded JSON tree without allocating a
/// second serialized copy. This is a cache budget, not a heap measurement.
int estimateJsonCacheWeight(Object? value) {
  if (value is String) return 32 + value.length * 2;
  if (value is List) {
    return 32 +
        value.length * 8 +
        value.fold<int>(
          0,
          (total, item) => total + estimateJsonCacheWeight(item),
        );
  }
  if (value is Map) {
    var bytes = 64 + value.length * 32;
    for (final entry in value.entries) {
      bytes +=
          estimateJsonCacheWeight(entry.key) +
          estimateJsonCacheWeight(entry.value);
    }
    return bytes;
  }
  return 16;
}
