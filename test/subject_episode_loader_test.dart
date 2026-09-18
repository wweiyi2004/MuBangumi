import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/network/bangumi_api.dart';
import 'package:mubangumi/core/storage/snapshot_cache.dart';
import 'package:mubangumi/features/collection/application/episode_collection_reader.dart';
import 'package:mubangumi/features/subject_detail/application/subject_episode_loader.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/models/library_batch.dart';

void main() {
  test('late disk restoration cannot overwrite live progress', () async {
    final f = _Fixture();
    addTearDown(f.loader.dispose);
    final cached = Completer<List<UserEpisodeCollection>?>();
    f.reader.cached = cached.future;
    f.reader.live = Future.value([_item(2)]);
    await f.loader.load();
    f.updates.clear();
    cached.complete([_item(0)]);
    await Future<void>.delayed(Duration.zero);
    expect(f.updates, isEmpty);
  });

  test(
    'cache merge finishing after the network also loses to the fresh result',
    () async {
      final f = _Fixture();
      addTearDown(f.loader.dispose);
      final live = Completer<List<UserEpisodeCollection>>();
      final overlay = Completer<List<UserEpisodeCollection>>();
      f.reader.cached = Future.value([_item(0)]);
      f.reader.live = live.future;
      f.reader.overlay = overlay.future;
      final load = f.loader.load();
      await f.reader.overlayStarted.future;
      live.complete([_item(2)]);
      await load;
      f.updates.clear();
      overlay.complete([_item(0)]);
      await Future<void>.delayed(Duration.zero);
      expect(f.updates, isEmpty);
      expect(f.reader.requestRevision, 7);
    },
  );

  for (final invalidation in ['relogin', 'new request', 'dispose']) {
    test('old episode responses cannot publish after $invalidation', () async {
      final f = _Fixture();
      addTearDown(f.loader.dispose);
      final oldResponse = Completer<List<UserEpisodeCollection>>();
      f.reader.live = oldResponse.future;
      final old = f.loader.load();
      if (invalidation == 'relogin') {
        f.reader.account = const LibraryBatchAccount(
          userId: 1,
          username: 'tester',
          generation: 2,
        );
      } else if (invalidation == 'new request') {
        f.reader.live = Future.value([_item(2)]);
        await f.loader.load(silent: true);
        expect(f.updates.where((u) => u.types != null).last.types, {1: 2});
      } else {
        f.loader.dispose();
      }
      f.updates.clear();
      oldResponse.complete([_item(0)]);
      await old;
      expect(f.updates, isEmpty);
    });
  }

  test(
    'offline errors retain cached progress and retry clears the error',
    () async {
      final f = _Fixture();
      addTearDown(f.loader.dispose);
      final offline = Completer<List<UserEpisodeCollection>>();
      final savedAt = DateTime(2026, 1, 2);
      f.reader.cached = Future.value(
        SnapshotItems([_item(2)], savedAt: savedAt),
      );
      f.reader.live = offline.future;
      final load = f.loader.load();
      await f.reader.overlayStarted.future;
      await Future<void>.delayed(Duration.zero);
      offline.completeError(StateError('offline'));
      await load;
      expect(f.updates.where((u) => u.types != null).last.types, {1: 2});
      expect(f.updates.where((u) => u.types != null).last.fromCache, isTrue);
      expect(f.updates.where((u) => u.types != null).last.cachedAt, savedAt);
      expect(
        f.updates.where((u) => u.error != null).single.error,
        '章节加载失败，请重试',
      );
      expect(f.updates.last.loading, isFalse);
      f.updates.clear();
      f.reader.live = Future.value([_item(0)]);
      await f.loader.load();
      expect(f.updates.first.clearError, isTrue);
      expect(f.updates.where((u) => u.types != null).last.types, {1: 0});
      expect(f.updates.where((u) => u.types != null).last.fromCache, isFalse);
      expect(f.updates.every((u) => u.error == null), isTrue);
    },
  );

  test(
    'uncollected subjects use public episodes without reading account storage',
    () async {
      final f = _Fixture();
      addTearDown(f.loader.dispose);
      f.reader.account = null;
      f.reader.collected = false;
      await f.loader.load();
      expect(f.api.calls, 1);
      expect(f.reader.snapshotReads, 0);
      expect(f.reader.liveReads, 0);
      expect(f.updates.where((u) => u.types != null).single.types, isEmpty);
      expect(
        f.updates.where((u) => u.episodes != null).single.episodes!.single.id,
        1,
      );
    },
  );

  test(
    'a silent refresh does not replace a usable view with loading or an error',
    () async {
      final f = _Fixture();
      addTearDown(f.loader.dispose);
      final failed = Completer<List<UserEpisodeCollection>>();
      f.reader.live = failed.future;
      final load = f.loader.load(silent: true);
      failed.completeError(StateError('offline'));
      await load;
      expect(f.reader.snapshotReads, 0);
      expect(
        f.updates.any(
          (u) => u.loading == true || u.error != null || u.episodes != null,
        ),
        isFalse,
      );
      expect(f.updates.last.loading, isFalse);
    },
  );
}

final _subject = Subject.fromJson({'id': 1, 'type': 2, 'name': '测试作品'});
UserEpisodeCollection _item(int type) => UserEpisodeCollection.fromJson({
  'type': type,
  'episode': {'id': 1, 'type': 0, 'sort': 1, 'name': 'EP1'},
});

class _Fixture {
  _Fixture() {
    loader = SubjectEpisodeLoader(
      subject: _subject,
      api: api,
      collections: reader,
      onProgress: updates.add,
    );
  }
  final reader = _Reader();
  final api = _Api();
  final updates = <SubjectEpisodeProgress>[];
  late final SubjectEpisodeLoader loader;
}

class _Reader implements EpisodeCollectionReader {
  LibraryBatchAccount? account = const LibraryBatchAccount(
    userId: 1,
    username: 'tester',
    generation: 1,
  );
  bool collected = true;
  Future<List<UserEpisodeCollection>?> cached = Future.value(null);
  Future<List<UserEpisodeCollection>> live = Future.value([]);
  Future<List<UserEpisodeCollection>>? overlay;
  final overlayStarted = Completer<void>();
  int snapshotReads = 0, liveReads = 0;
  int? requestRevision;
  @override
  LibraryBatchAccount? get batchAccount => account;
  @override
  int get episodeRevision => 7;
  @override
  UserCollection? batchCollection(int subjectId) =>
      collected ? UserCollection.fromJson({'subject_id': 1}) : null;
  @override
  Future<List<UserEpisodeCollection>?> readEpisodeSnapshot(int subjectId) {
    snapshotReads++;
    return cached;
  }

  @override
  Future<List<UserEpisodeCollection>> loadEpisodeCollections(
    int subjectId, {
    int? episodeType,
  }) {
    liveReads++;
    return live;
  }

  @override
  Future<List<UserEpisodeCollection>> applyPendingEpisodeChanges(
    int subjectId,
    List<UserEpisodeCollection> source, {
    int? afterRevision,
  }) {
    requestRevision = afterRevision;
    if (!overlayStarted.isCompleted) overlayStarted.complete();
    return overlay ?? Future.value(source);
  }
}

class _Api extends BangumiApi {
  int calls = 0;
  @override
  Future<List<Episode>> getEpisodes(
    int subjectId, {
    int? episodeType = 0,
  }) async {
    calls++;
    return [_item(0).episode];
  }
}
