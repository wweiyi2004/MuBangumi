import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/storage/serial_task_queue.dart';

void main() {
  test('an idle queue does not depend on an expired scheduling zone', () async {
    final microtasks = <void Function()>[];
    late SerialTaskQueue queue;
    var ran = false;
    runZoned(
      () {
        queue = SerialTaskQueue();
        queue.run(() async {
          ran = true;
        });
        while (microtasks.isNotEmpty) {
          microtasks.removeAt(0)();
        }
      },
      zoneSpecification: ZoneSpecification(
        scheduleMicrotask: (self, parent, zone, action) {
          microtasks.add(() => zone.runGuarded(action));
        },
      ),
    );
    expect(ran, isTrue);
    expect(
      await queue.run(() async => 2).timeout(const Duration(seconds: 1)),
      2,
    );
  });
  test(
    'reentrant requests retain FIFO order and failures do not poison the queue',
    () async {
      final queue = SerialTaskQueue();
      final order = <int>[];
      final gate = Completer<void>();
      final first = queue.run(() async {
        order.add(1);
        await gate.future;
        throw StateError('fixture');
      });
      final expectation = expectLater(first, throwsStateError);
      final second = queue.run(() async {
        order.add(2);
        unawaited(
          queue.run(() async {
            order.add(3);
          }),
        );
      });
      gate.complete();
      await expectation;
      await second;
      await queue.done;
      expect(order, [1, 2, 3]);
    },
  );
}
