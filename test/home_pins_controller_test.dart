import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/state/home_pins_controller.dart';

import 'support/memory_home_pins.dart';

void main() {
  test('a late pin read cannot replace a newer successful reload', () async {
    final first = Completer<List<int>>(), second = Completer<List<int>>();
    final repo = MemoryHomePins()..pendingRead = first.future;
    final controller = HomePinsController(repo, 1);
    addTearDown(controller.dispose);
    repo.pendingRead = second.future;
    final reload = controller.load();
    second.complete([2, 3]);
    await reload;
    first.complete([9]);
    await pumpEventQueue();
    expect(controller.state.ids, [2, 3]);
  });
  test(
    'pinning is idempotent and order persists independently for each account',
    () async {
      final repo = MemoryHomePins();
      final first = HomePinsController(repo, 1);
      addTearDown(first.dispose);
      await pumpEventQueue();
      await first.setPinned(8, true);
      await first.setPinned(9, true);
      await first.setPinned(8, true);
      expect(first.state.ids, [8, 9]);
      await first.move(9, 8);
      expect(first.state.ids, [9, 8]);
      final second = HomePinsController(repo, 2);
      addTearDown(second.dispose);
      await pumpEventQueue();
      expect(second.state.ids, isEmpty);
      await second.setPinned(5, true);
      final restarted = HomePinsController(repo, 1);
      addTearDown(restarted.dispose);
      await pumpEventQueue();
      expect(restarted.state.ids, [9, 8]);
      await restarted.setPinned(9, false);
      expect(repo.data, {
        1: [8],
        2: [5],
      });
    },
  );

  test('failed writes retain the saved order and can be retried', () async {
    final repo = MemoryHomePins()..data[1] = [1, 2];
    final controller = HomePinsController(repo, 1);
    addTearDown(controller.dispose);
    await pumpEventQueue();
    repo.failSave = true;
    await controller.move(2, 1);
    expect(controller.state.ids, [1, 2]);
    expect(controller.state.error, contains('已保留原顺序'));
    repo.failSave = false;
    await controller.move(2, 1);
    expect(controller.state.ids, [2, 1]);
  });

  test(
    'loading failures never allow blind overwrites of existing pins',
    () async {
      final repo = MemoryHomePins()
        ..data[1] = [99]
        ..failRead = true;
      final controller = HomePinsController(repo, 1);
      addTearDown(controller.dispose);
      await pumpEventQueue();
      await controller.setPinned(5, true);
      expect(repo.writes, 0);
      repo.failRead = false;
      await controller.load();
      expect(controller.state.ids, [99]);
    },
  );

  test(
    'a disposed account cannot affect its replacement through a late save',
    () async {
      final gate = Completer<void>();
      final repo = MemoryHomePins()..pendingSave = gate.future;
      final first = HomePinsController(repo, 1);
      await pumpEventQueue();
      final save = first.setPinned(7, true);
      await first.setPinned(7, true);
      expect(repo.writes, 1);
      first.dispose();
      final second = HomePinsController(repo, 2);
      addTearDown(second.dispose);
      await pumpEventQueue();
      gate.complete();
      await save;
      expect(second.state.ids, isEmpty);
      expect(repo.data[1], [7]);
    },
  );

  test(
    'home order includes only unique ongoing collections and leaves source untouched',
    () {
      final source = [
        _item(1),
        _item(2),
        _item(3, done: true),
        _item(2),
        _item(4),
      ];
      final ordered = orderHomeCollections(source, [4, 3, 99, 4, 2]);
      expect(ordered.map((item) => item.subjectId), [4, 2, 1]);
      expect(source.map((item) => item.subjectId), [1, 2, 3, 2, 4]);
      expect(orderHomeCollections(source, []).map((item) => item.subjectId), [
        1,
        2,
        4,
      ]);
    },
  );
}

UserCollection _item(int id, {bool done = false}) => UserCollection(
  subjectId: id,
  type: done ? CollectionType.done : CollectionType.doing,
  rate: 0,
  episodeStatus: 0,
  updatedAt: null,
  subject: Subject(
    id: id,
    name: '作品$id',
    nameCn: '',
    imageUrl: '',
    summary: '',
    episodeCount: 12,
    score: 8,
    rank: 1,
    date: '',
  ),
);
