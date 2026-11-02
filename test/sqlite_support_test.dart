import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/storage/serial_task_queue.dart';
import 'package:mubangumi/core/storage/sqlite_support.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  test(
    'concurrent callers share a connection which can reopen after close',
    () async {
      final connection = SqliteConnection();
      addTearDown(connection.close);
      final ready = Completer<void>();
      var openings = 0;
      Future<Database> create() async {
        openings++;
        await ready.future;
        return sqliteFactory.openDatabase(
          inMemoryDatabasePath,
          options: OpenDatabaseOptions(singleInstance: false),
        );
      }

      final first = connection.open(create);
      final second = connection.open(create);
      expect(openings, 1);
      ready.complete();
      final databases = await Future.wait([first, second]);
      expect(identical(databases[0], databases[1]), isTrue);
      await databases[0].execute('CREATE TABLE sample (value INTEGER)');
      await databases[0].insert('sample', {'value': 7});
      expect((await databases[1].query('sample')).single['value'], 7);

      await connection.close();
      expect(databases[0].isOpen, isFalse);
      final reopened = await connection.open(create);
      expect(openings, 2);
      expect(reopened.isOpen, isTrue);
      expect(identical(reopened, databases[0]), isFalse);
    },
  );

  test(
    'opening failure reaches all callers and a later attempt can succeed',
    () async {
      final connection = SqliteConnection();
      addTearDown(connection.close);
      final pending = Completer<Database>();
      final failure = StateError('synthetic open failure');
      var openings = 0;
      Future<Database> create() {
        openings++;
        return openings == 1
            ? pending.future
            : sqliteFactory.openDatabase(
                inMemoryDatabasePath,
                options: OpenDatabaseOptions(singleInstance: false),
              );
      }

      final first = expectLater(
        connection.open(create),
        throwsA(same(failure)),
      );
      final second = expectLater(
        connection.open(create),
        throwsA(same(failure)),
      );
      pending.completeError(failure);
      await Future.wait([first, second]);
      expect(openings, 1);
      expect((await connection.open(create)).isOpen, isTrue);
      expect(openings, 2);
    },
  );

  test(
    'queued tasks keep their order and continue after a visible failure',
    () async {
      final queue = SerialTaskQueue();
      final pending = Completer<int>();
      final failure = StateError('synthetic write failure');
      final order = <String>[];
      final first = queue.run(() {
        order.add('first');
        return pending.future;
      });
      final second = queue.run(() async {
        order.add('second');
        return 7;
      });
      final failed = expectLater(first, throwsA(same(failure)));
      await Future<void>.delayed(Duration.zero);
      expect(order, ['first']);
      pending.completeError(failure);
      await failed;
      expect(await second, 7);
      await queue.done;
      expect(order, ['first', 'second']);
    },
  );
}
