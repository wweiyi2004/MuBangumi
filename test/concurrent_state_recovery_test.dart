import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/network/bangumi_api.dart';
import 'package:mubangumi/core/network/rss_fetcher.dart';
import 'package:mubangumi/core/storage/bangumi_sync_store.dart';
import 'package:mubangumi/core/storage/rss_store.dart';
import 'package:mubangumi/core/storage/user_preference_store.dart';
import 'package:mubangumi/features/sync/application/pending_sync_controller.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/models/community_models.dart';
import 'package:mubangumi/models/rss_models.dart';
import 'package:mubangumi/state/notify_controller.dart';
import 'package:mubangumi/state/rss_controller.dart';
import 'package:mubangumi/state/session_controller.dart';
import 'package:mubangumi/state/user_preferences_controller.dart';

class DelayedPreferences implements UserPreferenceRepository {
  final initialRead = Completer<List<LocalUserPreference>>();
  final rows = <String, LocalUserPreference>{
    'alice': const LocalUserPreference(
      username: 'alice',
      note: 'existing note',
    ),
    'bob': const LocalUserPreference(username: 'bob', blocked: true),
  };
  @override
  Future<List<LocalUserPreference>> loadAll() => initialRead.future;
  @override
  Future<void> save(LocalUserPreference value) async {
    rows[value.key] = value;
  }
}

class DelayedFeed extends RssFetcher {
  final started = Completer<void>();
  final response = Completer<RssFetchResult>();
  @override
  Future<RssFetchResult> fetch(
    String url, {
    String etag = '',
    String lastModified = '',
  }) {
    started.complete();
    return response.future;
  }
}

class DelayedCompletionApi extends BangumiApi {
  final started = Completer<void>();
  final response = Completer<void>();
  int calls = 0;
  @override
  Future<void> replayPendingMutation(
    BangumiMutationKind kind,
    Map<String, dynamic> payload,
  ) {
    calls++;
    if (!started.isCompleted) started.complete();
    return response.future;
  }

  @override
  Future<List<UserEpisodeCollection>> getEpisodeCollections(
    int subjectId, {
    int? episodeType,
  }) async => [];
}

class RecoveringPreferences implements UserPreferenceRepository {
  bool failReads = true;
  int writes = 0;
  LocalUserPreference saved = const LocalUserPreference(
    username: 'alice',
    note: 'existing note',
  );
  @override
  Future<List<LocalUserPreference>> loadAll() async {
    if (failReads) throw StateError('temporarily unreadable');
    return [saved];
  }

  @override
  Future<void> save(LocalUserPreference value) async {
    writes++;
    saved = value;
  }
}

void main() {
  test(
    'editing blocking during initial preference load preserves the saved note',
    () async {
      final repository = DelayedPreferences();
      final original = repository.rows.values.toList();
      final controller = UserPreferencesController(repository);
      addTearDown(controller.dispose);
      expect(controller.state.isLoading, true);
      final editing = controller.setBlocked('alice', true);
      repository.initialRead.complete(original);
      await editing;
      await Future<void>.delayed(Duration.zero);
      expect(
        repository.rows['alice']!.note,
        'existing note',
        reason:
            'changing only blocked must not overwrite the note with an unloaded default',
      );
      expect(controller.state.isBlocked('bob'), true);
    },
  );

  test(
    'unreadable preferences cannot be overwritten and edits recover after storage returns',
    () async {
      final repository = RecoveringPreferences();
      final controller = UserPreferencesController(repository);
      addTearDown(controller.dispose);
      await controller.load();
      await expectLater(controller.setBlocked('alice', true), throwsStateError);
      expect(repository.writes, 0);
      repository.failReads = false;
      await controller.setBlocked('alice', true);
      expect(repository.saved.note, 'existing note');
      expect(repository.saved.blocked, true);
    },
  );

  test(
    'deleting an RSS source during refresh must not leave orphan unread items',
    () async {
      final store = RssStore.test(databasePath: ':memory:');
      addTearDown(store.close);
      final source = await store.upsertSource(
        const RssSource(id: 0, name: 'audit', url: 'https://example.test/rss'),
      );
      await store.upsertBinding(
        RssBinding(
          id: 0,
          sourceId: source.id,
          subjectId: 42,
          subjectName: 'Anime',
          matchKeywords: 'Anime',
        ),
      );
      final fetcher = DelayedFeed();
      final controller = RssController(store, fetcher);
      addTearDown(controller.dispose);
      await controller.reload();
      final refreshing = controller.refreshAll();
      await fetcher.started.future;
      await controller.deleteSource(source.id);
      expect(await store.listSources(), isEmpty);
      expect(await store.listBindings(), isEmpty);
      fetcher.response.complete(
        const RssFetchResult(
          entries: [
            RssFeedEntry(
              guid: 'late-item',
              title: 'Anime 01',
              link: 'https://example.test/1',
            ),
          ],
        ),
      );
      await refreshing;
      expect(
        await store.listItems(),
        isEmpty,
        reason:
            'the deleted source must not insert a late result into the real SQLite database',
      );
    },
  );

  test(
    'signing out during completion sync must not permanently block pending chapter work',
    () async {
      final store = BangumiSyncStore(databasePath: ':memory:');
      addTearDown(store.close);
      await store.enqueue(
        username: 'alice',
        kind: BangumiMutationKind.collection,
        mutationKey: 'collection:42',
        payload: {
          'subject_id': 42,
          'collection_type': CollectionType.done.value,
          'complete_episodes': true,
        },
      );
      SyncAccount? account = (generation: 1, username: 'alice');
      final api = DelayedCompletionApi();
      final sync = PendingSyncController(
        api: api,
        store: store,
        readAccount: () => account,
        onProgress: (_, _) {},
        messageFor: (e) => e.toString(),
      );
      addTearDown(sync.dispose);
      final work = sync.sync();
      await api.started.future;
      account = null;
      api.response.complete();
      await work;
      expect(await store.countFor('alice'), 1);
      expect(
        await store.blockedCountFor('alice'),
        0,
        reason:
            'account cancellation is not a server rejection; remaining work should resume at next login',
      );
      account = (generation: 2, username: 'alice');
      await sync.sync();
      expect(api.calls, 2);
      expect(await store.countFor('alice'), 0);
    },
  );

  test(
    'late notice poll cannot restore a badge cleared by successful mark-all-read',
    () async {
      final old = Completer<CommunityPageResult<BangumiNotice>>();
      var calls = 0;
      final controller = NotifyBadgeController(
        isAuthenticated: () => true,
        noticeLoader: () {
          calls++;
          return calls == 1
              ? old.future
              : Future.value(
                  const CommunityPageResult<BangumiNotice>(data: [], total: 2),
                );
        },
      );
      addTearDown(controller.dispose);
      controller.updateSession(SessionPhase.signedIn);
      final work = controller.refresh();
      controller.clearLocally();
      expect(controller.state.unreadCount, 0);
      old.complete(
        const CommunityPageResult<BangumiNotice>(data: [], total: 7),
      );
      await work;
      expect(
        controller.state.unreadCount,
        0,
        reason:
            'a poll started before marking all read must not overwrite the newer result',
      );
      await controller.refresh();
      expect(calls, 2);
      expect(controller.state.unreadCount, 2);
    },
  );

  for (final singleRead in [false, true]) {
    test(
      'a newer ${singleRead ? 'single read' : 'page count'} survives an older poll',
      () async {
        final old = Completer<CommunityPageResult<BangumiNotice>>();
        final controller = NotifyBadgeController(
          isAuthenticated: () => true,
          noticeLoader: () => old.future,
        );
        addTearDown(controller.dispose);
        controller.setUnreadCount(5);
        controller.updateSession(SessionPhase.signedIn);
        final work = controller.refresh();
        if (singleRead) {
          controller.markOneReadLocally();
        } else {
          controller.setUnreadCount(4);
        }
        old.complete(
          const CommunityPageResult<BangumiNotice>(data: [], total: 5),
        );
        await work;
        expect(controller.state.unreadCount, 4);
        expect(controller.state.isLoading, false);
      },
    );
  }
}
