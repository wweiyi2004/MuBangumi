import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/storage/user_preference_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as path;

Future<void> _holdLock((String, SendPort) args) async {
  sqfliteFfiInit();
  final control = ReceivePort();
  final db = await databaseFactoryFfiNoIsolate.openDatabase(
    args.$1,
    options: OpenDatabaseOptions(singleInstance: false),
  );
  try {
    await db.execute('BEGIN EXCLUSIVE');
    args.$2.send(control.sendPort);
    await control.first;
    await db.execute('ROLLBACK');
  } finally {
    await db.close();
    control.close();
    args.$2.send(null);
  }
}

void main() {
  test(
    'opening a personal database waits for a brief external lock',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'mubangumi-sqlite-lock-',
      );
      expect(
        path.isWithin(
          Directory.systemTemp.resolveSymbolicLinksSync(),
          dir.resolveSymbolicLinksSync(),
        ),
        isTrue,
      );
      final location = path.join(dir.path, 'people.sqlite');
      final seed = UserPreferenceStore.test(databasePath: location);
      await seed.databaseForBackup();
      await seed.close();
      final replies = ReceivePort();
      final messages = StreamIterator<dynamic>(replies);
      final worker = await Isolate.spawn(_holdLock, (
        location,
        replies.sendPort,
      ));
      await messages.moveNext();
      final control = messages.current as SendPort;
      final release = Timer(
        const Duration(milliseconds: 150),
        () => control.send(null),
      );
      final store = UserPreferenceStore.test(databasePath: location);
      try {
        await store.databaseForBackup();
      } finally {
        release.cancel();
        control.send(null);
        await messages.moveNext().timeout(const Duration(seconds: 5));
        await store.close();
        await messages.cancel();
        replies.close();
        worker.kill();
        await dir.delete(recursive: true);
      }
    },
    skip: !Platform.isWindows && !Platform.isLinux,
  );
}
