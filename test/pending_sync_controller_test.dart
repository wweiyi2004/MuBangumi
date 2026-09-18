import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/network/bangumi_api.dart';
import 'package:mubangumi/core/storage/bangumi_sync_store.dart';
import 'package:mubangumi/features/sync/application/pending_sync_controller.dart';

void main() {
  test(
    'old counts cannot publish after the same username logs in again',
    () async {
      final store = _Queue()..countResult = Completer<int>();
      SyncAccount account = (generation: 1, username: 'tester');
      final updates = <SyncProgress>[];
      final sync = PendingSyncController(
        api: _Api(),
        store: store,
        readAccount: () => account,
        onProgress: (_, progress) => updates.add(progress),
        messageFor: (_) => 'error',
      );
      addTearDown(sync.dispose);
      final old = sync.refreshCount();
      account = (generation: 2, username: 'tester');
      store.countResult!.complete(7);
      expect(await old, 7);
      expect(updates, isEmpty);
      await sync.refreshCount();
      expect(updates.single.pendingCount, 7);
    },
  );

  testWidgets(
    'a transient error retries after delay and disposal cancels further retries',
    (tester) async {
      final store = _Queue()..items.add(_mutation('tester'));
      final api = _Api()..fail = true;
      final sync = PendingSyncController(
        api: api,
        store: store,
        readAccount: () => (generation: 1, username: 'tester'),
        onProgress: (_, _) {},
        messageFor: (_) => 'offline',
      );
      await sync.sync();
      expect(api.calls, 1);
      await tester.pump(const Duration(seconds: 19));
      expect(api.calls, 1);
      await tester.pump(const Duration(seconds: 1));
      expect(api.calls, 2);
      sync.dispose();
      await tester.pump(const Duration(minutes: 5));
      expect(api.calls, 2);
      expect(store.items, hasLength(1));
    },
  );

  testWidgets(
    'new-account uploads wait for the old upload then resume automatically',
    (tester) async {
      final store = _Queue()..items.add(_mutation('old'));
      final api = _Api()..firstUpload = Completer<void>();
      SyncAccount account = (generation: 1, username: 'old');
      final updates = <SyncAccount>[];
      final sync = PendingSyncController(
        api: api,
        store: store,
        readAccount: () => account,
        onProgress: (owner, _) => updates.add(owner),
        messageFor: (_) => 'error',
      );
      addTearDown(sync.dispose);
      final old = sync.sync();
      await tester.pump();
      expect(api.calls, 1);
      account = (generation: 2, username: 'new');
      sync.cancelRetry();
      updates.clear();
      store.items.add(_mutation('new'));
      final joined = sync.sync();
      expect(api.calls, 1);
      api.firstUpload!.complete();
      await old;
      await joined;
      await tester.pump(Duration.zero);
      expect(api.calls, 2);
      expect(store.items, isEmpty);
      expect(updates, isNotEmpty);
      expect(updates.every((owner) => owner == account), isTrue);
    },
  );
}

PendingBangumiMutation _mutation(String username) => PendingBangumiMutation(
  id: username == 'old' ? 1 : 2,
  username: username,
  kind: BangumiMutationKind.episode,
  mutationKey: 'episode:1',
  payload: const {'subject_id': 1, 'episode_id': 1, 'type': 2},
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  revision: 1,
  attempts: 0,
  blocked: false,
);

class _Api extends BangumiApi {
  var calls = 0;
  bool fail = false;
  Completer<void>? firstUpload;

  @override
  Future<void> replayPendingMutation(
    BangumiMutationKind kind,
    Map<String, dynamic> payload,
  ) async {
    calls++;
    if (calls == 1 && firstUpload != null) await firstUpload!.future;
    if (fail) throw const BangumiApiException('offline', retryable: true);
  }
}

class _Queue extends BangumiSyncStore {
  final items = <PendingBangumiMutation>[];
  Completer<int>? countResult;

  @override
  Future<List<PendingBangumiMutation>> pendingFor(
    String username, {
    bool includeBlocked = false,
  }) async => items.where((item) => item.username == username).toList();
  @override
  Future<int> countFor(String username) =>
      countResult?.future ??
      Future.value(items.where((item) => item.username == username).length);
  @override
  Future<int> blockedCountFor(String username) async => 0;
  @override
  Future<bool> removeIfUnchanged(PendingBangumiMutation mutation) async =>
      items.remove(mutation);
  @override
  Future<bool> markFailure(
    PendingBangumiMutation mutation,
    String error, {
    required bool blocked,
  }) async => true;
}
