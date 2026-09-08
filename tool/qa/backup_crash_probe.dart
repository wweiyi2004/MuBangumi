// Invoked only by backup_crash_recovery_test.dart in a disposable directory.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/backup/backup_archive.dart';

import '../../test/support/backup_fixtures.dart';

void main() {
  test('terminate before multi-database import commit', () async {
    const directory = String.fromEnvironment('BACKUP_CRASH_DIR');
    if (directory.isEmpty ||
        !File('$directory/probe-authorized').existsSync()) {
      fail('This probe requires its parent test disposable directory');
    }
    final stores = BackupTestStores(Directory(directory));
    final archive = BackupArchive.decode(
      await File('$directory/input.json').readAsBytes(),
    );
    final repo = stores.repository(
      afterWrite: (category) async {
        if (category != BackupCategory.privateDrafts) return;
        final journals = Directory(directory)
            .listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith('-journal'))
            .toList();
        // Read raw file lengths to show pages spilled before the commit. This is
        // not a normal close, thrown exception, or a manually executed rollback.
        File('$directory/crashed.json').writeAsStringSync(
          jsonEncode({
            'journals': journals.map((file) => file.lengthSync()).toList(),
            'people_bytes': File('$directory/people.sqlite').lengthSync(),
            'community_bytes': File('$directory/community.sqlite').lengthSync(),
          }),
          flush: true,
        );
        exit(77);
      },
    );
    final preview = await repo.preview(
      backupOwner,
      archive,
      archive.data.keys.toSet(),
      BackupImportMode.replace,
    );
    await repo.apply(backupOwner, preview, isCurrentOwner: () => true);
    fail('The crash hook did not run');
  });
}
