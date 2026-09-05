import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/storage/schedule_store.dart';
import 'package:mubangumi/models/schedule_models.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test(
    'v1 schedules survive upgrade and reminder IDs survive restart and deletion',
    () async {
      sqfliteFfiInit();
      final directory = await Directory.systemTemp.createTemp(
        'mubangumi-schedule-test-',
      );
      final databasePath = path.join(directory.path, 'schedule.sqlite');
      final season = SeasonKey.current();
      final schedule = SeasonSchedule(
        season: season,
        items: const [
          ScheduleItem(
            subjectId: 42,
            name: 'Existing',
            nameCn: '',
            imageUrl: '',
            weekday: 1,
            reminderEnabled: true,
          ),
        ],
      );
      final oldDatabase = await databaseFactoryFfi.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) async {
            await db.execute(
              'CREATE TABLE season_schedule ('
              'season_key TEXT PRIMARY KEY NOT NULL, payload TEXT NOT NULL, updated_at INTEGER NOT NULL)',
            );
            await db.insert('season_schedule', {
              'season_key': season.id,
              'payload': jsonEncode(schedule.toJson()),
              'updated_at': 1,
            });
          },
        ),
      );
      await oldDatabase.close();
      final store = ScheduleStore.test(databasePath: databasePath);
      final restarted = ScheduleStore.test(databasePath: databasePath);
      addTearDown(() async {
        await store.close();
        await restarted.close();
        await directory.delete(recursive: true);
      });
      expect((await store.load(season)).toJson(), schedule.toJson());
      expect(await store.readReminderIds(), isNull);
      await store.writeReminderIds({123, 456});
      await store.deleteSeason(season);
      await store.close();
      expect(await restarted.listSeasons(), isEmpty);
      expect(await restarted.readReminderIds(), {123, 456});
      await restarted.writeReminderIds({});
      await restarted.close();
      expect(await store.readReminderIds(), isEmpty);
    },
  );
}
