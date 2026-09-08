import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/backup/backup_archive.dart';
import 'package:mubangumi/core/backup/backup_plan.dart';
import 'package:mubangumi/core/storage/community_draft_store.dart';
import 'package:mubangumi/core/storage/pm_draft_store.dart';
import 'package:mubangumi/core/storage/user_preference_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as path;

import 'support/backup_fixtures.dart';

void main() {
  late BackupTestStores source, target;
  late BackupArchive archive;
  setUp(() async {
    source = BackupTestStores(
      await Directory.systemTemp.createTemp('mubangumi-backup-source-'),
    );
    target = BackupTestStores(
      await Directory.systemTemp.createTemp('mubangumi-backup-target-'),
    );
    await source.seed();
    archive = await source.repository().export(
      backupOwner,
      allBackupCategories,
    );
  });
  tearDown(() async {
    await source.close();
    await target.close();
    await source.dir.delete(recursive: true);
    await target.dir.delete(recursive: true);
  });
  Future<bool> importAll({
    BackupArchive? input,
    BackupImportMode mode = BackupImportMode.replace,
  }) async {
    final repo = target.repository();
    final file = input ?? archive;
    final preview = await repo.preview(
      backupOwner,
      file,
      file.data.keys.toSet(),
      mode,
    );
    return repo.apply(backupOwner, preview, isCurrentOwner: () => true);
  }

  test(
    'all personal categories restore into clean real databases and reopen identically',
    () async {
      expect(await importAll(), true);
      await target.close();
      final restored = await target.repository().export(
        backupOwner,
        allBackupCategories,
      );
      expect(
        backupRowsDigest(restored.data, allBackupCategories),
        backupRowsDigest(archive.data, allBackupCategories),
      );
      expect(
        (await target.schedules.load(backupSeason)).items.single.toJson(),
        backupItem.toJson(),
      );
      expect((await target.pm.read(11, backupDraftId)).draft!.body, ' 原样\n保留 ');
      expect(await target.browsing.readHomePins(11), [123, 456]);
      expect(
        (await target.rss.listBindings()).single.sourceId,
        (await target.rss.listSources()).single.id,
      );
      expect(await target.rss.listItems(), isEmpty);
      expect(await target.schedules.readReminderIds(), isNull);
    },
  );
  test('archive excludes caches, reminder ledger and other accounts', () {
    final encoded = utf8.decode(archive.encode());
    for (final text in [
      'CACHE-SECRET',
      'CACHE-ITEM',
      'OTHER-OWNER',
      'ids_json',
      'revision',
      'deleted',
      'change_id',
    ]) {
      expect(encoded, isNot(contains(text)));
    }
    expect(archive.data.keys.toSet(), allBackupCategories);
  });
  test(
    'duplicate import is a no-op with no additional audit or revision',
    () async {
      await importAll();
      final revision = (await target.pm.read(11, backupDraftId)).revision;
      expect(await importAll(), false);
      expect((await target.pm.read(11, backupDraftId)).revision, revision);
      final db = await databaseFactoryFfi.openDatabase(
        path.join(target.dir.path, 'import.sqlite'),
      );
      expect(
        (await db.rawQuery('SELECT COUNT(*) AS n FROM import_log')).single['n'],
        1,
      );
      await db.close();
    },
  );
  test('replace preserves other accounts and excluded categories', () async {
    await target.seed();
    final oldOther = await target.repository().export(otherBackupOwner, {
      BackupCategory.browsing,
      BackupCategory.pins,
      BackupCategory.privateDrafts,
      BackupCategory.communityDrafts,
    });
    await importAll(
      input: BackupArchive.create(
        owner: backupOwner,
        data: {
          BackupCategory.pins: [backupPin(789, 0)],
        },
      ),
    );
    expect(await target.browsing.readHomePins(11), [789]);
    expect(await target.browsing.readHomePins(22), [999]);
    final newOther = await target.repository().export(
      otherBackupOwner,
      oldOther.data.keys.toSet(),
    );
    expect(newOther.data, oldOther.data);
    expect(
      (await target.schedules.load(backupSeason)).items.single.subjectId,
      123,
    );
    expect((await target.rss.listItems()).single.title, 'CACHE-ITEM');
  });
  test('wrong owner fails before opening target files', () async {
    await expectLater(
      target.repository().preview(
        otherBackupOwner,
        archive,
        allBackupCategories,
        BackupImportMode.replace,
      ),
      throwsA(isA<BackupException>()),
    );
    expect(await target.dir.list().toList(), isEmpty);
  });
  test('same UID renamed account rebinds username-keyed local data', () async {
    const renamed = BackupOwner(11, 'renamed');
    final repo = target.repository();
    final preview = await repo.preview(
      renamed,
      archive,
      allBackupCategories,
      BackupImportMode.replace,
    );
    await repo.apply(renamed, preview, isCurrentOwner: () => true);
    expect(await target.browsing.readLibrary('alice'), isNull);
    expect(await target.browsing.readLibrary('renamed'), isNotNull);
    expect(
      await target.community.load(
        communityDraftKey('renamed', ['group', 'demo'])!,
      ),
      isNotNull,
    );
  });
  test('a changed preview cannot overwrite newer local preferences', () async {
    final repo = target.repository();
    final preview = await repo.preview(
      backupOwner,
      archive,
      allBackupCategories,
      BackupImportMode.replace,
    );
    await target.browsing.saveHomePins(11, [999]);
    await expectLater(
      repo.apply(backupOwner, preview, isCurrentOwner: () => true),
      throwsA(isA<BackupException>()),
    );
    expect(await target.browsing.readHomePins(11), [999]);
    expect(await target.schedules.listSeasons(), isEmpty);
  });
  for (final failAt in BackupCategory.values) {
    test(
      'failure after ${failAt.name} rolls back every database and audit',
      () async {
        final repo = target.repository(
          afterWrite: (category) async {
            if (category == failAt) {
              throw const FileSystemException('simulated disk failure');
            }
          },
        );
        final preview = await repo.preview(
          backupOwner,
          archive,
          allBackupCategories,
          BackupImportMode.replace,
        );
        await expectLater(
          repo.apply(backupOwner, preview, isCurrentOwner: () => true),
          throwsA(isA<FileSystemException>()),
        );
        await target.close();
        final empty = await target.repository().export(
          backupOwner,
          allBackupCategories,
        );
        expect(empty.data.values.every((rows) => rows.isEmpty), true);
        final db = await databaseFactoryFfi.openDatabase(
          path.join(target.dir.path, 'import.sqlite'),
        );
        expect(await db.rawQuery('SELECT * FROM import_log'), isEmpty);
        await db.close();
        expect(await importAll(), true);
      },
    );
  }
  test(
    'account changing during transaction rolls back already written data',
    () async {
      var current = true;
      final repo = target.repository(
        afterWrite: (_) async {
          current = false;
        },
      );
      final preview = await repo.preview(
        backupOwner,
        archive,
        allBackupCategories,
        BackupImportMode.replace,
      );
      await expectLater(
        repo.apply(backupOwner, preview, isCurrentOwner: () => current),
        throwsA(isA<BackupException>()),
      );
      expect(await target.schedules.listSeasons(), isEmpty);
    },
  );
  test(
    'imported and deleted drafts reject saves or clears from stale editors',
    () async {
      await importAll();
      final oldPm = await target.pm.read(11, backupDraftId);
      final key = communityDraftKey('alice', ['group', 'demo'])!;
      final oldCommunity = await target.community.loadVersioned(key);
      final changed = BackupArchive.create(
        owner: backupOwner,
        data: {
          BackupCategory.privateDrafts: [
            for (final row in archive.data[BackupCategory.privateDrafts]!)
              {...row, 'body': '导入的新草稿'},
          ],
          BackupCategory.communityDrafts: [],
        },
      );
      await importAll(input: changed);
      await expectLater(
        target.pm.clear(11, backupDraftId, expectedRevision: oldPm.revision),
        throwsA(isA<PmDraftConflict>()),
      );
      await expectLater(
        target.community.saveVersioned(key, (
          title: '',
          content: '迟到保存',
        ), expectedRevision: oldCommunity.revision),
        throwsA(isA<CommunityDraftConflict>()),
      );
      expect((await target.pm.read(11, backupDraftId)).draft!.body, '导入的新草稿');
      expect(await target.community.load(key), isNull);
    },
  );
  test(
    'RSS preserves unchanged cached items and invalidates changed matching rules',
    () async {
      await target.seed();
      final local = await target.repository().export(backupOwner, {
        BackupCategory.rss,
      });
      BackupArchive rssWithRule(String? keywords) => BackupArchive.create(
        owner: backupOwner,
        data: {
          BackupCategory.rss: [
            for (final row in local.data[BackupCategory.rss]!)
              {
                ...row,
                if (row['kind'] == 'source') 'name': '改名',
                if (row['kind'] == 'binding' && keywords != null)
                  'match_keywords': keywords,
              },
          ],
        },
      );
      final oldId = (await target.rss.listSources()).single.id;
      await importAll(input: rssWithRule(null));
      final newId = (await target.rss.listSources()).single.id;
      expect(newId, greaterThan(oldId));
      expect((await target.rss.listItems()).single.sourceId, newId);
      expect((await target.rss.listSources()).single.etag, 'CACHE-SECRET');
      await importAll(input: rssWithRule('different'));
      expect(await target.rss.listItems(), isEmpty);
      expect((await target.rss.listSources()).single.etag, isEmpty);
    },
  );
  test('queued writes are drained before backup snapshot', () async {
    final write = target.people.save(
      const LocalUserPreference(username: 'person', note: 'queued'),
    );
    final snapshot = await target.repository().export(backupOwner, {
      BackupCategory.people,
    });
    await write;
    expect(snapshot.data[BackupCategory.people]!.single['note'], 'queued');
  });
  test(
    'pre-2.1 schedule payload exports with disabled reminder defaults',
    () async {
      final oldItem = backupItem.toJson()
        ..remove('reminderEnabled')
        ..remove('reminderHour')
        ..remove('reminderMinute');
      final legacy = {
        'season': backupSeason.toJson(),
        'items': [oldItem],
      };
      final db = await databaseFactoryFfi.openDatabase(
        await source.schedules.databaseForBackup(),
        options: OpenDatabaseOptions(singleInstance: false),
      );
      await db.update(
        'season_schedule',
        {'payload': jsonEncode(legacy)},
        where: 'season_key = ?',
        whereArgs: [backupSeason.id],
      );
      await db.close();
      final exported = await source.repository().export(backupOwner, {
        BackupCategory.schedules,
      });
      final item =
          (exported.data[BackupCategory.schedules]!.single['items'] as List)
                  .single
              as Map;
      expect(item['reminderEnabled'], false);
      expect(item['reminderHour'], 20);
      expect(item['reminderMinute'], 0);
      expect(item['note'], backupItem.note);
      await importAll(input: exported);
      expect(
        (await target.schedules.load(
          backupSeason,
        )).items.single.reminderEnabled,
        false,
      );
    },
  );
}
