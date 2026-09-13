import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/network/bangumi_api.dart';
import 'package:mubangumi/core/network/bangumi_endpoints.dart';
import 'package:mubangumi/core/storage/bangumi_sync_store.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/models/library_batch.dart';
import 'package:mubangumi/models/schedule_models.dart';
import 'package:mubangumi/state/library_batch_controller.dart';
import 'package:mubangumi/state/schedule_controller.dart';
import 'package:path/path.dart' as path;

import 'support/library_batch_fixtures.dart';
import 'support/schedule_fixtures.dart';

void main() {
  late Directory directory;
  late BatchTestQueue queue;
  final sessions = <BatchTestSession>[];
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('mubangumi-batch-');
    queue = BatchTestQueue(
      databasePath: path.join(directory.path, 'queue.sqlite'),
    );
  });
  tearDown(() async {
    for (final session in sessions) {
      await session.syncPendingChanges();
      session.dispose();
    }
    sessions.clear();
    await queue.close();
    if (directory.parent.resolveSymbolicLinksSync() !=
            Directory.systemTemp.resolveSymbolicLinksSync() ||
        !path.basename(directory.path).startsWith('mubangumi-batch-')) {
      throw StateError('Unexpected test directory');
    }
    await directory.delete(recursive: true);
  });
  BatchTestSession session({int count = 51, BatchTestCache? cache}) {
    final value = BatchTestSession(
      BatchTestApi([
        for (var id = 1; id <= count; id++) batchFixtureCollection(id),
      ]),
      queue,
      cache: cache,
    );
    sessions.add(value);
    return value;
  }

  LibraryBatchPlan plan(
    BatchTestSession session, {
    int count = 50,
    CollectionType type = CollectionType.done,
    bool complete = false,
  }) => LibraryBatchPlan(
    account: session.batchAccount!,
    kind: LibraryBatchKind.collection,
    items: [for (var id = 1; id <= count; id++) session.target(id)],
    collectionType: type,
    completeEpisodes: complete,
  );

  for (final count in [1, 50]) {
    test(
      '$count mixed-type changes preserve fields and leave unselected items untouched',
      () async {
        final owner = session(count: count + 1);
        final runner = LibraryBatchController(
          plan(owner, count: count),
          AppLibraryBatchBackend(owner),
        );
        addTearDown(runner.dispose);
        await runner.run();
        expect(runner.count(LibraryBatchStatus.saved), count);
        for (var id = 1; id <= count; id++) {
          final saved = owner.batchCollection(id)!;
          expect(saved.type, CollectionType.done);
          expect(saved.rate, 8);
          expect(saved.comment, '保留吐槽$id');
          expect(saved.tags, ['保留标签$id']);
          expect(saved.private, isTrue);
          expect(saved.episodeStatus, 3);
          expect(saved.volumeStatus, 2);
        }
        expect(owner.batchCollection(count + 1)!.type, CollectionType.doing);
        expect(
          (await queue.pendingFor(
            'batch1',
          )).where((item) => item.payload['status_only'] == true),
          hasLength(count),
        );
      },
    );
  }

  test(
    'one save failure does not lose other entries and retry enqueues only that failure',
    () async {
      final owner = session();
      queue.failingIds.add(7);
      final runner = LibraryBatchController(
        plan(owner),
        AppLibraryBatchBackend(owner),
      );
      addTearDown(runner.dispose);
      await runner.run();
      expect(runner.count(LibraryBatchStatus.saved), 49);
      expect(runner.count(LibraryBatchStatus.failed), 1);
      final before = {
        for (final item in await queue.pendingFor('batch1'))
          item.payload['subject_id']: item.id,
      };
      final calls = queue.calls;
      queue.failingIds.clear();
      await runner.run(retryFailed: true);
      expect(queue.calls, calls + 1);
      expect(runner.count(LibraryBatchStatus.saved), 50);
      for (final item in await queue.pendingFor('batch1')) {
        if (item.payload['subject_id'] != 7) {
          expect(item.id, before[item.payload['subject_id']]);
        }
      }
    },
  );

  test(
    'offline batch entries reopen and replay for their original account',
    () async {
      final owner = session();
      final runner = LibraryBatchController(
        plan(owner),
        AppLibraryBatchBackend(owner),
      );
      addTearDown(runner.dispose);
      await runner.run();
      await owner.syncPendingChanges();
      owner.dispose();
      sessions.remove(owner);
      await queue.close();
      queue = BatchTestQueue(
        databasePath: path.join(directory.path, 'queue.sqlite'),
      );
      final restarted = session();
      await restarted.refresh();
      expect(restarted.batchCollection(50)!.type, CollectionType.done);
      expect(restarted.batchCollection(51)!.type, CollectionType.doing);
      restarted.api.offline = false;
      await restarted.syncPendingChanges();
      expect(await queue.countFor('batch1'), 0);
      expect(restarted.api.replayed, hasLength(50));
      expect(await queue.countFor('batch2'), 0);
    },
  );

  test(
    'account change finishes an already submitted original-account save and stops the rest',
    () async {
      final owner = session();
      final gate = Completer<void>();
      queue.saveGate = gate.future;
      final runner = LibraryBatchController(
        plan(owner),
        AppLibraryBatchBackend(owner),
      );
      addTearDown(runner.dispose);
      final running = runner.run();
      await pumpEventQueue();
      owner.switchUser(2);
      gate.complete();
      await running;
      expect(queue.calls, 1);
      expect(runner.count(LibraryBatchStatus.saved), 1);
      expect(runner.count(LibraryBatchStatus.notStarted), 49);
      expect(await queue.countFor('batch1'), 1);
      expect(await queue.countFor('batch2'), 0);
      expect(owner.batchCollection(1)!.type, CollectionType.doing);
    },
  );

  test(
    'a later local edit is not overwritten by an older batch plan',
    () async {
      final owner = session(count: 1);
      final batch = plan(owner, count: 1);
      await owner.changeCollection(
        owner.batchCollection(1)!.subject,
        CollectionType.wish,
        completeEpisodesWhenDone: false,
        rate: 10,
      );
      final calls = queue.calls;
      final runner = LibraryBatchController(
        batch,
        AppLibraryBatchBackend(owner),
      );
      addTearDown(runner.dispose);
      await runner.run();
      expect(runner.count(LibraryBatchStatus.skipped), 1);
      expect(queue.calls, calls);
      expect(owner.batchCollection(1)!.rate, 10);
      expect(owner.batchCollection(1)!.type, CollectionType.wish);
    },
  );

  test(
    'snapshot cache failure does not turn a durable batch save into a failed item',
    () async {
      final owner = session(
        count: 1,
        cache: BatchTestCache()..failWrites = true,
      );
      final runner = LibraryBatchController(
        plan(owner, count: 1),
        AppLibraryBatchBackend(owner),
      );
      addTearDown(runner.dispose);
      await runner.run();
      expect(runner.count(LibraryBatchStatus.saved), 1);
      expect(await queue.countFor('batch1'), 1);
    },
  );

  test(
    'status patches retain earlier unsynced metadata edits and completed chapter work',
    () async {
      final owner = session(count: 2);
      final anime = owner.batchCollection(2)!;
      await owner.changeCollection(
        anime.subject,
        CollectionType.done,
        rate: 10,
        comment: '新吐槽',
        completeEpisodesWhenDone: true,
      );
      final batch = LibraryBatchPlan(
        account: owner.batchAccount!,
        kind: LibraryBatchKind.collection,
        items: [owner.target(2)],
        collectionType: CollectionType.doing,
      );
      final runner = LibraryBatchController(
        batch,
        AppLibraryBatchBackend(owner),
      );
      addTearDown(runner.dispose);
      await runner.run();
      final pending = await queue.pendingFor('batch1');
      expect(pending, hasLength(2));
      expect(pending.first.payload['complete_episodes'], isTrue);
      expect(pending.last.payload['status_only'], isTrue);
      await owner.syncPendingChanges();
      owner.api.offline = false;
      await owner.syncPendingChanges();
      expect(owner.api.server.last.type, CollectionType.doing);
      expect(owner.api.server.last.rate, 10);
      expect(owner.api.server.last.comment, '新吐槽');
      expect(owner.api.episodeUpdates.single, [201, 202]);
    },
  );

  test(
    'batch schedule additions write once to a fixed season and preserve existing arrangements',
    () async {
      final owner = session();
      final store = _CountingSchedules();
      final current = SeasonKey.current();
      final target = SeasonKey(year: current.year + 1, quarter: 0);
      final existing = ScheduleItem.fromSubject(
        owner.batchCollection(1)!.subject,
        weekday: 5,
      ).copyWith(note: '保留备注', reminderEnabled: true, reminderHour: 23);
      store.schedules[current.id] = SeasonSchedule(
        season: current,
        items: [ScheduleItem.fromSubject(owner.batchCollection(51)!.subject)],
      );
      store.schedules[target.id] = SeasonSchedule(
        season: target,
        items: [existing],
      );
      final reminders = MemoryScheduleReminders();
      final schedule = ScheduleController(store, reminders);
      addTearDown(schedule.dispose);
      await schedule.setSeason(current);
      store.saves = 0;
      final batch = LibraryBatchPlan(
        account: owner.batchAccount!,
        kind: LibraryBatchKind.schedule,
        items: [for (var id = 1; id <= 50; id++) owner.target(id)],
        season: target,
        weekday: 3,
      );
      final runner = LibraryBatchController(
        batch,
        AppLibraryBatchBackend(owner, schedule),
      );
      addTearDown(runner.dispose);
      await runner.run();
      expect(store.saves, 1);
      expect(runner.count(LibraryBatchStatus.saved), 49);
      expect(runner.count(LibraryBatchStatus.skipped), 1);
      expect(schedule.state.season, current);
      expect(schedule.state.schedule.items.single.subjectId, 51);
      final saved = store.schedules[target.id]!;
      expect(saved.items, hasLength(50));
      expect(saved.items.first.toJson(), existing.toJson());
      expect(
        saved.items
            .skip(1)
            .every((item) => item.weekday == 3 && !item.reminderEnabled),
        isTrue,
      );
    },
  );

  test(
    'status-only replay sends PATCH with only the selected status',
    () async {
      final requests = <RequestOptions>[];
      final dio =
          Dio(BaseOptions(baseUrl: BangumiNetworkRoute.official.apiBaseUrl))
            ..interceptors.add(
              InterceptorsWrapper(
                onRequest: (options, handler) {
                  requests.add(options);
                  handler.resolve(
                    Response<void>(requestOptions: options, statusCode: 204),
                  );
                },
              ),
            );
      await BangumiApi(
        dio: dio,
      ).replayPendingMutation(BangumiMutationKind.collection, {
        'subject_id': 42,
        'collection_type': 2,
        'status_only': true,
        'rate': 8,
        'comment': '本地快照',
        'episode_status': 5,
      });
      expect(requests.single.method, 'PATCH');
      expect(requests.single.path, '/users/-/collections/42');
      expect(requests.single.data, {'type': 2});
    },
  );

  test('an account guard is rechecked after awaiting token refresh', () async {
    var allowed = true, sent = 0;
    final gate = Completer<void>();
    final dio =
        Dio(BaseOptions(baseUrl: BangumiNetworkRoute.official.apiBaseUrl))
          ..interceptors.add(
            InterceptorsWrapper(
              onRequest: (options, handler) {
                sent++;
                handler.resolve(
                  Response<void>(requestOptions: options, statusCode: 204),
                );
              },
            ),
          );
    final api = BangumiApi(dio: dio)..ensureFreshToken = () => gate.future;
    final request = api.withRequestGuard(
      () => allowed,
      () => api.updateCollectionStatus(42, CollectionType.done),
    );
    await pumpEventQueue();
    allowed = false;
    gate.complete();
    await expectLater(request, throwsA(isA<BangumiApiException>()));
    expect(sent, 0);
  });

  test(
    'a late unauthorized response cannot refresh credentials or retry for another account',
    () async {
      var allowed = true, sent = 0, refreshes = 0;
      final gate = Completer<void>();
      final dio =
          Dio(BaseOptions(baseUrl: BangumiNetworkRoute.official.apiBaseUrl))
            ..interceptors.add(
              InterceptorsWrapper(
                onRequest: (options, handler) async {
                  sent++;
                  await gate.future;
                  handler.reject(
                    DioException(
                      requestOptions: options,
                      response: Response<void>(
                        requestOptions: options,
                        statusCode: 401,
                      ),
                      type: DioExceptionType.badResponse,
                    ),
                  );
                },
              ),
            );
      final api = BangumiApi(dio: dio)
        ..onUnauthorizedRefresh = () async {
          refreshes++;
          return true;
        };
      final request = api.withRequestGuard(
        () => allowed,
        () => api.updateCollectionStatus(42, CollectionType.done),
      );
      await pumpEventQueue();
      allowed = false;
      gate.complete();
      await expectLater(request, throwsA(isA<BangumiApiException>()));
      expect(sent, 1);
      expect(refreshes, 0);
    },
  );

  test(
    'same-account token refresh still permits one status patch retry',
    () async {
      final requests = <RequestOptions>[];
      final dio =
          Dio(BaseOptions(baseUrl: BangumiNetworkRoute.official.apiBaseUrl))
            ..interceptors.add(
              InterceptorsWrapper(
                onRequest: (options, handler) {
                  requests.add(options);
                  if (requests.length == 1) {
                    handler.reject(
                      DioException(
                        requestOptions: options,
                        response: Response<void>(
                          requestOptions: options,
                          statusCode: 401,
                        ),
                        type: DioExceptionType.badResponse,
                      ),
                    );
                  } else {
                    handler.resolve(
                      Response<void>(requestOptions: options, statusCode: 204),
                    );
                  }
                },
              ),
            );
      final api = BangumiApi(dio: dio)..setAccessToken('old-test-token');
      api.onUnauthorizedRefresh = () async {
        api.setAccessToken('new-test-token');
        return true;
      };
      await api.withRequestGuard(
        () => true,
        () => api.updateCollectionStatus(42, CollectionType.done),
      );
      expect(requests, hasLength(2));
      expect(requests.last.headers['Authorization'], 'Bearer new-test-token');
      expect(requests.last.data, {'type': 2});
    },
  );

  test(
    'schedule storage failure preserves existing entries and retries only new failed items',
    () async {
      final owner = session(count: 2);
      final store = _CountingSchedules();
      final season = SeasonKey.current();
      final existing = ScheduleItem.fromSubject(
        owner.batchCollection(1)!.subject,
        weekday: 5,
      ).copyWith(note: '保留');
      store.schedules[season.id] = SeasonSchedule(
        season: season,
        items: [existing],
      );
      final schedule = ScheduleController(store);
      addTearDown(schedule.dispose);
      await schedule.setSeason(season);
      store.failSave = true;
      final batch = LibraryBatchPlan(
        account: owner.batchAccount!,
        kind: LibraryBatchKind.schedule,
        items: [owner.target(1), owner.target(2)],
        season: season,
        weekday: 2,
      );
      final runner = LibraryBatchController(
        batch,
        AppLibraryBatchBackend(owner, schedule),
      );
      addTearDown(runner.dispose);
      await runner.run();
      expect(runner.count(LibraryBatchStatus.failed), 1);
      expect(runner.count(LibraryBatchStatus.skipped), 1);
      expect(
        store.schedules[season.id]!.items.single.toJson(),
        existing.toJson(),
      );
      store.failSave = false;
      await runner.run(retryFailed: true);
      expect(runner.count(LibraryBatchStatus.saved), 1);
      expect(store.schedules[season.id]!.items, hasLength(2));
      expect(
        store.schedules[season.id]!.items.first.toJson(),
        existing.toJson(),
      );
    },
  );

  test(
    'an old rejected batch cannot overwrite a newer uploaded status after restart',
    () async {
      final owner = session(count: 1);
      await owner.syncPendingChanges();
      owner.api.offline = false;
      owner.api.rejectedIds.add(1);
      final first = LibraryBatchController(
        plan(owner, count: 1),
        AppLibraryBatchBackend(owner),
      );
      addTearDown(first.dispose);
      await first.run();
      await owner.syncPendingChanges();
      final oldIssue = (await queue.blockedFor('batch1')).single;
      owner.api.rejectedIds.clear();
      final second = LibraryBatchController(
        plan(owner, count: 1, type: CollectionType.wish),
        AppLibraryBatchBackend(owner),
      );
      addTearDown(second.dispose);
      await second.run();
      await owner.syncPendingChanges();
      expect((await queue.blockedFor('batch1')).single.superseded, isTrue);
      expect(await owner.retryBlockedMutation(oldIssue), contains('旧操作不能再重试'));
      final server = owner.api.server;
      owner.dispose();
      sessions.remove(owner);
      await queue.close();
      queue = BatchTestQueue(
        databasePath: path.join(directory.path, 'queue.sqlite'),
      );
      final restarted = session(count: 1);
      restarted.api.server = server;
      restarted.api.offline = false;
      await restarted.refresh();
      expect(restarted.batchCollection(1)!.type, CollectionType.wish);
      await restarted.syncPendingChanges(retryBlocked: true);
      expect(restarted.api.replayed, isEmpty);
      final issue = (await queue.blockedFor('batch1')).single;
      expect(issue.superseded, isTrue);
      expect(await restarted.discardBlockedMutation(issue), isNull);
      expect(restarted.batchCollection(1)!.type, CollectionType.wish);
    },
  );

  test(
    'status-only pending overlays retain fresher server metadata and book progress',
    () async {
      final owner = session(count: 1);
      final runner = LibraryBatchController(
        plan(owner, count: 1),
        AppLibraryBatchBackend(owner),
      );
      addTearDown(runner.dispose);
      await runner.run();
      owner.api.server = [
        owner.api.server.single.copyWith(
          rate: 10,
          comment: '较新的吐槽',
          tags: ['较新的标签'],
          private: false,
          episodeStatus: 7,
          volumeStatus: 5,
        ),
      ];
      await owner.refresh();
      final current = owner.batchCollection(1)!;
      expect(current.type, CollectionType.done);
      expect(current.rate, 10);
      expect(current.comment, '较新的吐槽');
      expect(current.tags, ['较新的标签']);
      expect(current.private, isFalse);
      expect(current.episodeStatus, 7);
      expect(current.volumeStatus, 5);
    },
  );

  test(
    'chapter completion is opt-in and applies only to main episodes of supported types',
    () async {
      final owner = session(count: 5);
      final runner = LibraryBatchController(
        plan(owner, count: 5, complete: true),
        AppLibraryBatchBackend(owner),
      );
      addTearDown(runner.dispose);
      await runner.run();
      final pending = await queue.pendingFor('batch1');
      expect(
        pending
            .where((item) => item.payload['complete_episodes'] == true)
            .map((item) => item.payload['subject_id']),
        [2, 5],
      );
      expect(owner.batchCollection(1)!.episodeStatus, 3);
      expect(owner.batchCollection(1)!.volumeStatus, 2);
      await owner.syncPendingChanges();
      owner.api.offline = false;
      await owner.syncPendingChanges();
      expect(owner.api.episodeUpdates, [
        [201, 202],
        [501, 502],
      ]);
    },
  );

  test(
    'a later full edit retains older chapter completion in its original queue position',
    () async {
      final owner = session(count: 2);
      final subject = owner.batchCollection(2)!.subject;
      await owner.changeCollection(
        subject,
        CollectionType.done,
        completeEpisodesWhenDone: true,
      );
      await owner.setEpisode(
        subjectId: 2,
        episodeId: 201,
        type: 0,
        previousType: 2,
      );
      await owner.changeCollection(
        subject,
        CollectionType.doing,
        completeEpisodesWhenDone: false,
      );
      final pending = await queue.pendingFor('batch1');
      expect(pending, hasLength(3));
      expect(pending.first.payload['complete_episodes'], isTrue);
      expect(pending[1].payload['episode_id'], 201);
      expect(
        pending.last.payload['collection_type'],
        CollectionType.doing.value,
      );
    },
  );
}

class _CountingSchedules extends MemorySchedules {
  int saves = 0;
  bool failSave = false;
  @override
  Future<void> save(SeasonSchedule schedule) {
    saves++;
    if (failSave) return Future.error(StateError('disk full'));
    return super.save(schedule);
  }
}
