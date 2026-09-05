import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/network/async_cache.dart';

void main() {
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
