import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/backup/backup_archive.dart';
import 'package:mubangumi/core/network/rss_fetcher.dart';
import 'package:mubangumi/core/storage/browsing_store.dart';
import 'package:mubangumi/core/notifications/schedule_reminder_service.dart';
import 'package:mubangumi/models/rss_models.dart';
import 'package:mubangumi/models/schedule_models.dart';
import 'package:mubangumi/models/schedule_view.dart';
import 'package:mubangumi/state/backup_providers.dart';
import 'package:mubangumi/state/local_data_state.dart';
import 'package:mubangumi/state/rss_controller.dart';
import 'package:mubangumi/state/schedule_controller.dart';
import 'package:mubangumi/state/session_controller.dart';
import 'package:mubangumi/state/schedule_view_controller.dart';

import 'support/backup_fixtures.dart';
import 'support/backup_ui_fixtures.dart';
import 'support/schedule_fixtures.dart';

void main() {
  test(
    'backup waits for accepted preference writes even after their page was disposed',
    () async {
      final stores = BackupTestStores(
        await Directory.systemTemp.createTemp('mubangumi-pending-view-'),
      );
      addTearDown(() async {
        await stores.close();
        await stores.dir.delete(recursive: true);
      });
      final repo = stores.repository();
      final archive = BackupArchive.create(
        owner: backupOwner,
        data: {
          BackupCategory.browsing: [
            {'kind': 'schedule_view', 'view': 'board'},
          ],
        },
      );
      final preview = await repo.preview(backupOwner, archive, {
        BackupCategory.browsing,
      }, BackupImportMode.replace);
      final pending = _QueuedViews(stores.browsing);
      final controller = ScheduleViewController(pending, backupOwner.id);
      await controller.load();
      final first = controller.select(ScheduleView.today);
      final second = controller.select(ScheduleView.week);
      controller.dispose();
      final applying = repo.apply(
        backupOwner,
        preview,
        isCurrentOwner: () => true,
      );
      final rejected = expectLater(applying, throwsA(isA<BackupException>()));
      await _until(() => pending.calls == 1);
      pending.gate.complete();
      await Future.wait([first, second, rejected]);
      expect(
        await stores.browsing.readScheduleView(backupOwner.id),
        ScheduleView.week,
      );
      final exported = await repo.export(backupOwner, {
        BackupCategory.browsing,
      });
      expect(exported.data[BackupCategory.browsing]!.single['view'], 'week');
      final newPreview = await repo.preview(backupOwner, archive, {
        BackupCategory.browsing,
      }, BackupImportMode.replace);
      expect(
        await repo.apply(backupOwner, newPreview, isCurrentOwner: () => true),
        true,
      );
      expect(
        await stores.browsing.readScheduleView(backupOwner.id),
        ScheduleView.board,
      );
    },
  );
  test(
    'failed RSS reload prevents manual fetch with stale configuration until reading succeeds',
    () async {
      final store = _RecoveringRss();
      final fetcher = _PendingFetcher();
      final controller = RssController(store, fetcher);
      addTearDown(controller.dispose);
      await _until(() => controller.state.loaded);
      await controller.pauseForImport();
      store.fail = true;
      expect(await controller.resumeAfterImport(imported: true), false);
      await controller.refreshAll(force: true);
      expect(fetcher.calls, 0);
      expect(controller.state.autoRefreshPaused, true);
      store.fail = false;
      store.url = 'https://example.invalid/imported';
      fetcher.pending.complete(const RssFetchResult(entries: []));
      await controller.refreshAll(force: true);
      expect(fetcher.lastUrl, store.url);
      expect(controller.state.loaded, true);
    },
  );
  test(
    'failed schedule reload prevents stale edits until reading succeeds',
    () async {
      final store = _DelayedSchedules();
      store.schedules[backupSeason.id] = SeasonSchedule(
        season: backupSeason,
        items: [backupItem],
      );
      final controller = ScheduleController(store, MemoryScheduleReminders());
      addTearDown(controller.dispose);
      await controller.load(backupSeason);
      await controller.pauseForImport();
      store.schedules[backupSeason.id] = SeasonSchedule(
        season: backupSeason,
        items: [backupItem.copyWith(note: 'imported')],
      );
      store.failRead = true;
      expect(await controller.resumeAfterImport(), false);
      await controller.setWeekday(123, 7);
      expect(store.saveCalls, 0);
      expect(controller.state.readFailed, true);
      store.failRead = false;
      await controller.load(backupSeason);
      await controller.setWeekday(123, 7);
      expect(store.saveCalls, 1);
      expect(store.schedules[backupSeason.id]!.items.single.note, 'imported');
    },
  );
  for (final response in ['success', 'notModified', 'failure']) {
    test(
      'RSS $response arriving after import cannot restore old source data',
      () async {
        final stores = BackupTestStores(
          await Directory.systemTemp.createTemp('mubangumi-import-live-'),
        );
        final fetcher = _PendingFetcher();
        final reminders = MemoryScheduleReminders();
        final container = ProviderContainer(
          overrides: [
            backupRepositoryProvider.overrideWith(
              (ref) async => stores.repository(),
            ),
            scheduleStoreProvider.overrideWithValue(stores.schedules),
            scheduleReminderProvider.overrideWithValue(reminders),
            rssStoreProvider.overrideWithValue(stores.rss),
            rssFetcherProvider.overrideWithValue(fetcher),
            sessionProvider.overrideWith(
              (ref) =>
                  throw StateError('import must not create or refresh session'),
            ),
          ],
        );
        addTearDown(() async {
          container.dispose();
          await stores.close();
          await stores.dir.delete(recursive: true);
        });
        await stores.seed();
        final rss = container.read(rssProvider.notifier);
        await _until(() => rss.state.loaded);
        final refreshing = rss.refreshAll();
        await _until(() => fetcher.calls == 1);
        final repo = stores.repository();
        final original = await repo.export(backupOwner, {
          BackupCategory.rss,
          BackupCategory.schedules,
        });
        final incoming = BackupArchive.create(
          owner: backupOwner,
          data: {
            BackupCategory.rss: [
              for (final row in original.data[BackupCategory.rss]!)
                {
                  ...row,
                  if (row['kind'] == 'source') 'name': '已导入的名称',
                  if (row['kind'] == 'binding') 'match_keywords': '新规则',
                },
            ],
            BackupCategory.schedules: [],
          },
        );
        final preview = await repo.preview(
          backupOwner,
          incoming,
          incoming.data.keys.toSet(),
          BackupImportMode.replace,
        );
        final result = await container.read(backupApplyProvider)(
          backupOwner,
          preview,
          () => true,
        );
        expect(result.changed, true);
        expect(result.warnings, isEmpty);
        expect(container.exists(sessionProvider), false);
        expect(container.read(localImportBusyProvider), false);
        expect(await stores.schedules.listSeasons(), isEmpty);
        expect(reminders.syncs.last, isEmpty);
        expect(rss.state.autoRefreshPaused, true);
        if (response == 'failure') {
          fetcher.pending.completeError(StateError('late failure'));
        } else {
          fetcher.pending.complete(
            RssFetchResult(
              entries: const [
                RssFeedEntry(
                  guid: 'late-guid',
                  title: '字幕 1080',
                  link: 'https://example.invalid/late',
                ),
              ],
              etag: 'late-etag',
              notModified: response == 'notModified',
            ),
          );
        }
        await refreshing;
        final source = (await stores.rss.listSources()).single;
        expect(source.name, '已导入的名称');
        expect(source.etag, isEmpty);
        expect(source.lastError, isEmpty);
        expect(await stores.rss.listItems(), isEmpty);
        await rss.refreshAll(automatic: true);
        expect(fetcher.calls, 1);
        fetcher.pending = Completer<RssFetchResult>()
          ..complete(const RssFetchResult(entries: []));
        await rss.refreshAll(force: true);
        expect(fetcher.calls, 2);
        expect(rss.state.autoRefreshPaused, false);
      },
    );
  }
  test(
    'failed transaction resumes controllers and clears the import busy flag',
    () async {
      final repo = MemoryBackups(data: {})
        ..applyError = StateError('disk full');
      final schedules = MemorySchedules();
      final container = ProviderContainer(
        overrides: [
          backupRepositoryProvider.overrideWith((ref) async => repo),
          scheduleStoreProvider.overrideWithValue(schedules),
          scheduleReminderProvider.overrideWithValue(MemoryScheduleReminders()),
          rssStoreProvider.overrideWithValue(ScheduleRssStore()),
        ],
      );
      addTearDown(container.dispose);
      final archive = uiBackup();
      final preview = await repo.preview(backupOwner, archive, {
        BackupCategory.schedules,
        BackupCategory.rss,
      }, BackupImportMode.merge);
      await expectLater(
        container.read(backupApplyProvider)(backupOwner, preview, () => true),
        throwsStateError,
      );
      expect(container.read(localImportBusyProvider), false);
      expect(container.read(rssProvider).autoRefreshPaused, false);
      expect(container.read(scheduleProvider).loading, false);
      expect(
        await container.read(scheduleProvider.notifier).load(backupSeason),
        true,
      );
      expect(schedules.schedules, isEmpty);
    },
  );
  test(
    'refresh failure after commit is reported as a warning and does not offer to repeat writes',
    () async {
      final repo = MemoryBackups(data: {});
      final container = ProviderContainer(
        overrides: [
          backupRepositoryProvider.overrideWith((ref) async => repo),
          rssStoreProvider.overrideWithValue(_UnreadableRss()),
        ],
      );
      addTearDown(container.dispose);
      final archive = uiBackup();
      final preview = await repo.preview(backupOwner, archive, {
        BackupCategory.rss,
      }, BackupImportMode.merge);
      final result = await container.read(backupApplyProvider)(
        backupOwner,
        preview,
        () => true,
      );
      expect(result.changed, true);
      expect(result.warnings.single, contains('RSS 读取'));
      expect(repo.applies, 1);
      expect(container.read(localImportBusyProvider), false);
    },
  );
  test(
    'a second import cannot run while the first transaction is pending',
    () async {
      final gate = Completer<void>();
      final repo = MemoryBackups(data: {})..applyGate = gate.future;
      final container = ProviderContainer(
        overrides: [backupRepositoryProvider.overrideWith((ref) async => repo)],
      );
      addTearDown(container.dispose);
      final preview = await repo.preview(backupOwner, uiBackup(), {
        BackupCategory.pins,
      }, BackupImportMode.merge);
      final first = container.read(backupApplyProvider)(
        backupOwner,
        preview,
        () => true,
      );
      await _until(() => repo.applies == 1);
      await expectLater(
        container.read(backupApplyProvider)(backupOwner, preview, () => true),
        throwsA(isA<BackupException>()),
      );
      gate.complete();
      await first;
      expect(repo.applies, 1);
      expect(container.read(localImportBusyProvider), false);
    },
  );
  test(
    'schedule pause drains an accepted save and rejects a late permission result',
    () async {
      final store = _DelayedSchedules();
      store.schedules[backupSeason.id] = SeasonSchedule(
        season: backupSeason,
        items: [backupItem],
      );
      final reminders = _PermissionReminders();
      final controller = ScheduleController(store, reminders);
      addTearDown(controller.dispose);
      await controller.load(backupSeason);
      final permission = controller.setReminder(
        123,
        enabled: true,
        hour: 18,
        minute: 5,
      );
      store.saveGate = Completer<void>();
      final saving = controller.setWeekday(123, 4);
      await _until(() => store.saveCalls == 1);
      var paused = false;
      final pause = controller.pauseForImport().then((_) {
        paused = true;
      });
      await Future<void>.delayed(Duration.zero);
      expect(paused, false);
      store.saveGate!.complete();
      await saving;
      await pause;
      store.schedules.clear();
      await controller.resumeAfterImport();
      reminders.permission.complete(
        const ReminderPermissionResult(ReminderPermissionStatus.granted),
      );
      expect(await permission, false);
      expect(controller.state.schedule.items, isEmpty);
      expect(store.schedules, isEmpty);
    },
  );
}

class _PendingFetcher extends RssFetcher {
  int calls = 0;
  String? lastUrl;
  Completer<RssFetchResult> pending = Completer<RssFetchResult>();
  @override
  Future<RssFetchResult> fetch(
    String url, {
    String etag = '',
    String lastModified = '',
  }) {
    calls++;
    lastUrl = url;
    return pending.future;
  }
}

class _UnreadableRss extends ScheduleRssStore {
  @override
  Future<List<RssSource>> listSources() async =>
      throw StateError('read failed');
}

class _DelayedSchedules extends MemorySchedules {
  bool failRead = false;
  @override
  Future<SeasonSchedule> load(SeasonKey season) async {
    if (failRead) throw StateError('read failed');
    return super.load(season);
  }

  Completer<void>? saveGate;
  int saveCalls = 0;
  @override
  Future<void> save(SeasonSchedule schedule) async {
    saveCalls++;
    await saveGate?.future;
    await super.save(schedule);
  }
}

class _RecoveringRss extends ScheduleRssStore {
  bool fail = false;
  String url = 'https://example.invalid/original';
  @override
  Future<List<RssSource>> listSources() async {
    if (fail) throw StateError('read failed');
    return [RssSource(id: 1, name: 'source', url: url)];
  }

  @override
  Future<RssSource> upsertSource(RssSource source) async => source;
  @override
  Future<int> insertItemsIgnoreDup(
    List<RssItem> items, {
    bool validateBindings = false,
  }) async => items.length;
}

class _QueuedViews implements ScheduleViewRepository {
  _QueuedViews(this.store);
  final BrowsingStore store;
  final gate = Completer<void>();
  int calls = 0;
  @override
  Future<ScheduleView?> readScheduleView(int ownerId) =>
      store.readScheduleView(ownerId);
  @override
  Future<void> saveScheduleView(int ownerId, ScheduleView view) async {
    calls++;
    if (calls == 1) await gate.future;
    await store.saveScheduleView(ownerId, view);
  }
}

class _PermissionReminders extends MemoryScheduleReminders {
  final permission = Completer<ReminderPermissionResult>();
  @override
  Future<ReminderPermissionResult> requestPermission() => permission.future;
}

Future<void> _until(bool Function() ready) async {
  for (var i = 0; i < 500 && !ready(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  expect(ready(), true);
}
