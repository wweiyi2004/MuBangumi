/// Bounded, expiring results with one active request per key.
/// Invalidating a key also prevents an older request from repopulating it.
class AsyncCache<T> {
  AsyncCache({
    required this.maxAge,
    required this.maxEntries,
    DateTime Function()? now,
  }) : assert(maxEntries > 0),
       _now = now ?? DateTime.now;

  final Duration maxAge;
  final int maxEntries;
  final DateTime Function() _now;
  final _values = <String, ({T value, DateTime savedAt})>{};
  final _pending = <String, Future<T>>{};

  Future<T> get(String key, Future<T> Function() load, {bool refresh = false}) {
    final pending = _pending[key];
    if (pending != null) return pending;
    final now = _now();
    _values.removeWhere((_, entry) => now.difference(entry.savedAt) >= maxAge);
    final cached = _values.remove(key);
    if (!refresh && cached != null) {
      _values[key] = cached;
      return Future.value(cached.value);
    }
    late final Future<T> request;
    request = Future<T>.sync(load)
        .then((value) {
          if (identical(_pending[key], request)) {
            _values[key] = (value: value, savedAt: _now());
            while (_values.length > maxEntries) {
              _values.remove(_values.keys.first);
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
    _values.removeWhere((key, _) => predicate(key));
    _pending.removeWhere((key, _) => predicate(key));
  }

  void clear() {
    _values.clear();
    _pending.clear();
  }
}
