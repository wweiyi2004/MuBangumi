import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/models/library_batch.dart';
import 'package:mubangumi/state/library_batch_controller.dart';

import 'support/library_batch_fixtures.dart';

void main() {
  LibraryBatchPlan plan() => LibraryBatchPlan(
    account: const LibraryBatchAccount(
      userId: 1,
      username: 'batch1',
      generation: 1,
    ),
    kind: LibraryBatchKind.collection,
    items: [
      for (var id = 1; id <= 50; id++)
        LibraryBatchItem(
          subject: batchFixtureCollection(id).subject,
          revision: 0,
        ),
    ],
  );
  test(
    'rapid start taps share one sequential run and retry only failed items',
    () async {
      final backend = _Backend()..failures.add(3);
      final runner = LibraryBatchController(plan(), backend);
      addTearDown(runner.dispose);
      final first = runner.run(), second = runner.run();
      expect(identical(first, second), isTrue);
      await first;
      expect(backend.calls, hasLength(50));
      expect(backend.peak, 1);
      expect(runner.count(LibraryBatchStatus.saved), 49);
      backend.failures.clear();
      await runner.run(retryFailed: true);
      expect(backend.calls.sublist(50), [3]);
      expect(runner.count(LibraryBatchStatus.saved), 50);
    },
  );
  test(
    'stopping permits the current save to finish but starts no later item',
    () async {
      final backend = _Backend()..gate = Completer<void>();
      final runner = LibraryBatchController(plan(), backend);
      addTearDown(runner.dispose);
      final running = runner.run();
      await pumpEventQueue();
      runner.stop();
      backend.gate!.complete();
      await running;
      expect(backend.calls, [1]);
      expect(runner.count(LibraryBatchStatus.saved), 1);
      expect(runner.count(LibraryBatchStatus.notStarted), 49);
    },
  );
  test(
    'account replacement and route disposal both stop further dispatch',
    () async {
      for (final dispose in [false, true]) {
        final backend = _Backend()..gate = Completer<void>();
        final runner = LibraryBatchController(plan(), backend);
        final running = runner.run();
        await pumpEventQueue();
        if (dispose) {
          runner.dispose();
        } else {
          backend.current = false;
        }
        backend.gate!.complete();
        await running;
        expect(backend.calls, [1]);
        if (!dispose) runner.dispose();
      }
    },
  );
}

class _Backend implements LibraryBatchBackend {
  @override
  void finish(LibraryBatchPlan plan) {}
  final calls = <int>[], failures = <int>{};
  bool current = true;
  int active = 0, peak = 0;
  Completer<void>? gate;
  @override
  bool isCurrent(LibraryBatchAccount account) => current;
  @override
  Future<LibraryBatchOutcome> changeCollection(
    LibraryBatchPlan plan,
    LibraryBatchItem item,
  ) async {
    calls.add(item.id);
    active++;
    if (active > peak) peak = active;
    await gate?.future;
    await Future<void>.delayed(Duration.zero);
    active--;
    return LibraryBatchOutcome(
      failures.contains(item.id)
          ? LibraryBatchStatus.failed
          : LibraryBatchStatus.saved,
    );
  }

  @override
  Future<LibraryBatchGroupResult> addToSchedule(
    LibraryBatchPlan plan,
    List<LibraryBatchItem> items,
    bool Function() allowed,
  ) async => const LibraryBatchGroupResult({});
}
