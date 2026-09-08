import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/backup/backup_archive.dart';
import 'package:mubangumi/core/backup/backup_plan.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/backup_fixtures.dart';

void main() {
  test(
    'abrupt process exit recovers spilled pages across all personal databases',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'mubangumi-backup-crash-',
      );
      final stores = BackupTestStores(dir);
      addTearDown(() async {
        await stores.close();
        await dir.delete(recursive: true);
      });
      await stores.seed();
      final baseline = await stores.repository().export(
        backupOwner,
        allBackupCategories,
      );
      final padding = 'x' * 1000000;
      final incoming = BackupArchive.create(
        owner: backupOwner,
        data: {
          ...baseline.data,
          BackupCategory.schedules: [
            {
              'season': backupSeason.toJson(),
              'items': [backupItem.copyWith(note: 'new').toJson()],
            },
          ],
          BackupCategory.rss: [
            for (final row in baseline.data[BackupCategory.rss]!)
              {...row, 'enabled': false},
          ],
          BackupCategory.people: [
            for (var i = 0; i < 4; i++) backupPerson('new$i', padding),
          ],
          BackupCategory.pins: [backupPin(888, 0)],
          BackupCategory.browsing: [backupSearch('new', 0)],
          BackupCategory.recommendations: [
            for (final row in baseline.data[BackupCategory.recommendations]!)
              {...row, 'title': 'new'},
          ],
          BackupCategory.communityDrafts: [
            for (var i = 0; i < 4; i++)
              {
                'target': ['group', 'new$i'],
                'title': 'new',
                'content': padding,
                'updated_at': 1,
              },
          ],
          BackupCategory.privateDrafts: [
            for (final row in baseline.data[BackupCategory.privateDrafts]!)
              {...row, 'body': 'new'},
          ],
        },
      );
      await File(
        path.join(dir.path, 'input.json'),
      ).writeAsBytes(incoming.encode(), flush: true);
      await File(
        path.join(dir.path, 'probe-authorized'),
      ).writeAsString('synthetic test data');
      await stores.close();
      final configFile = File('.dart_tool/package_config.json').absolute;
      final config =
          jsonDecode(
                await File('.dart_tool/package_config.json').readAsString(),
              )
              as Map;
      final flutterPackage = (config['packages'] as List)
          .cast<Map>()
          .singleWhere((row) => row['name'] == 'flutter');
      final sdk = path.dirname(
        path.dirname(
          Uri.parse(flutterPackage['rootUri'] as String).toFilePath(),
        ),
      );
      final executable = path.join(
        sdk,
        'bin',
        Platform.isWindows ? 'flutter.bat' : 'flutter',
      );
      // The child gets its own build directory: Windows cannot replace a native
      // sqlite3 DLL already loaded by the parent test process.
      final runner = Directory(path.join(dir.path, 'probe-runner'));
      for (final relative in ['.dart_tool', 'tool/qa', 'test/support']) {
        await Directory(
          path.join(runner.path, relative),
        ).create(recursive: true);
      }
      for (final entry in (config['packages'] as List).cast<Map>()) {
        entry['rootUri'] = entry['name'] == 'mubangumi'
            ? runner.uri.toString()
            : configFile.uri.resolve(entry['rootUri'] as String).toString();
      }
      await for (final file in Directory('lib').list(recursive: true)) {
        if (file is! File || !file.path.endsWith('.dart')) continue;
        final destination = File(path.join(runner.path, file.path));
        await destination.parent.create(recursive: true);
        await file.copy(destination.path);
      }
      await File(
        path.join(runner.path, '.dart_tool/package_config.json'),
      ).writeAsString(jsonEncode(config));
      for (final relative in [
        'pubspec.yaml',
        'pubspec.lock',
        '.dart_tool/package_graph.json',
        'tool/qa/backup_crash_probe.dart',
        'test/support/backup_fixtures.dart',
      ]) {
        await File(relative).copy(path.join(runner.path, relative));
      }
      final process = await Process.run(
        executable,
        [
          'test',
          '--no-pub',
          '--no-test-assets',
          '--reporter',
          'expanded',
          '--dart-define=BACKUP_CRASH_DIR=${dir.path}',
          'tool/qa/backup_crash_probe.dart',
        ],
        workingDirectory: runner.path,
        runInShell: Platform.isWindows,
      );
      final marker = File(path.join(dir.path, 'crashed.json'));
      expect(
        marker.existsSync(),
        true,
        reason: '${process.stdout}\n${process.stderr}',
      );
      expect(process.exitCode, isNot(0));
      final evidence = jsonDecode(await marker.readAsString()) as Map;
      expect((evidence['journals'] as List).length, 7);
      expect(
        (evidence['journals'] as List).every((size) => (size as int) > 0),
        true,
      );
      expect(evidence['people_bytes'], greaterThan(1000000));
      expect(evidence['community_bytes'], greaterThan(1000000));
      final recovered = await stores.repository().export(
        backupOwner,
        allBackupCategories,
      );
      expect(
        backupRowsDigest(recovered.data, allBackupCategories),
        backupRowsDigest(baseline.data, allBackupCategories),
      );
      final db = await databaseFactoryFfi.openDatabase(
        path.join(dir.path, 'import.sqlite'),
      );
      expect(await db.query('import_log'), isEmpty);
      await db.close();
      final repo = stores.repository();
      final retry = await repo.preview(
        backupOwner,
        incoming,
        allBackupCategories,
        BackupImportMode.replace,
      );
      expect(
        await repo.apply(backupOwner, retry, isCurrentOwner: () => true),
        true,
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
