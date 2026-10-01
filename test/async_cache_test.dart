import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/network/async_cache.dart';

void main() {
  test(
    'byte budget evicts LRU pages and does not retain oversized results',
    () async {
      final cache = AsyncCache<String>(
        maxAge: const Duration(minutes: 2),
        maxEntries: 400,
        maxWeight: 10,
        weightOf: (value) => value.length,
      );
      await cache.get('a', () async => 'aaaa');
      await cache.get('b', () async => 'bbbb');
      await cache.get('a', () async => 'wrong');
      await cache.get('c', () async => 'cccc');
      expect(cache.cachedWeight, 8);
      expect(cache.cachedEntries, 2);
      expect(await cache.get('a', () async => 'wrong'), 'aaaa');
      expect(await cache.get('huge', () async => '01234567890'), '01234567890');
      expect(cache.cachedWeight, 8);
      expect(cache.cachedEntries, 2);
      expect(await cache.get('b', () async => 'new'), 'new');
      expect(cache.cachedWeight, 7);
      cache.removeWhere((key) => key == 'a');
      expect(cache.cachedWeight, 3);
      cache.clear();
      expect(cache.cachedWeight, 0);
    },
  );

  test(
    'expired bytes are reclaimed when an outstanding request completes',
    () async {
      var now = DateTime(2026);
      final cache = AsyncCache<String>(
        maxAge: const Duration(minutes: 2),
        maxEntries: 10,
        maxWeight: 10,
        weightOf: (value) => value.length,
        now: () => now,
      );
      await cache.get('a', () async => 'aaaa');
      final pending = Completer<String>();
      final request = cache.get('b', () => pending.future);
      now = now.add(const Duration(minutes: 2));
      pending.complete('bb');
      await request;
      expect(cache.cachedWeight, 2);
      expect(cache.cachedEntries, 1);
    },
  );

  test(
    'memory trim preserves in-flight coalescing and account invalidation',
    () async {
      final cache = AsyncCache<String>(
        maxAge: const Duration(minutes: 2),
        maxEntries: 10,
        maxWeight: 10,
        weightOf: (value) => value.length,
      );
      await cache.get('completed', () async => 'old');
      final pending = Completer<String>();
      final old = cache.get('account', () => pending.future);
      cache.clearCompleted();
      expect(cache.cachedWeight, 0);
      expect(
        identical(cache.get('account', () async => 'duplicate'), old),
        isTrue,
      );
      cache.clear();
      expect(await cache.get('account', () async => 'new'), 'new');
      pending.complete('old');
      await old;
      expect(await cache.get('account', () async => 'wrong'), 'new');
      expect(cache.cachedWeight, 3);
    },
  );

  test(
    'decoded JSON estimation includes nested string and container storage',
    () {
      final small = estimateJsonCacheWeight({
        'items': ['a'],
      });
      final large = estimateJsonCacheWeight({
        'items': [List.filled(1000, 'a').join()],
      });
      expect(large - small, 1998);
    },
  );

  test('coalesces requests and expires results from completion time', () async {
    var now = DateTime(2026);
    final cache = AsyncCache<int>(
      maxAge: const Duration(minutes: 2),
      maxEntries: 2,
      now: () => now,
    );
    final response = Completer<int>();
    var calls = 0;
    Future<int> load() {
      calls++;
      return response.future;
    }

    final first = cache.get('a', load);
    final second = cache.get('a', load, refresh: true);
    now = now.add(const Duration(minutes: 3));
    response.complete(1);
    expect(await first, 1);
    expect(await second, 1);
    expect(await cache.get('a', load), 1);
    expect(calls, 1);
    now = now.add(const Duration(minutes: 2));
    await cache.get('a', load);
    expect(calls, 2);
  });

  test('failure is retryable and refresh bypasses completed cache', () async {
    final cache = AsyncCache<int>(
      maxAge: const Duration(minutes: 2),
      maxEntries: 2,
    );
    await expectLater(
      cache.get('a', () async => throw StateError('offline')),
      throwsStateError,
    );
    expect(await cache.get('a', () async => 2), 2);
    expect(await cache.get('a', () async => 3, refresh: true), 3);
  });

  test(
    'invalidated late response cannot replace a new account result',
    () async {
      final cache = AsyncCache<int>(
        maxAge: const Duration(minutes: 2),
        maxEntries: 2,
      );
      final pending = Completer<int>();
      final old = cache.get('a', () => pending.future);
      cache.clear();
      expect(await cache.get('a', () async => 2), 2);
      pending.complete(1);
      await old;
      expect(await cache.get('a', () async => 3), 2);
      cache.removeWhere((key) => key == 'a');
      expect(await cache.get('a', () async => 3), 3);
    },
  );

  test('evicts least recently used completed entry at capacity', () async {
    final cache = AsyncCache<int>(
      maxAge: const Duration(minutes: 2),
      maxEntries: 2,
    );
    await cache.get('a', () async => 1);
    await cache.get('b', () async => 2);
    await cache.get('a', () async => 3);
    await cache.get('c', () async => 4);
    expect(await cache.get('a', () async => 5), 1);
    expect(await cache.get('b', () async => 6), 6);
  });
}
