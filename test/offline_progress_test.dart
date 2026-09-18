import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/network/bangumi_api.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/models/library_batch.dart';

import 'support/collection_module_fixtures.dart';
import 'support/library_batch_fixtures.dart';
import 'support/progress_fixtures.dart';

void main() {
  test(
    'offline next episode uses cached chapters and durable edits without a network read',
    () async {
      final api = _NeverApi();
      final f = CollectionModuleFixture(
        api: api,
        preferCachedReads: () => true,
      );
      addTearDown(f.dispose);
      f.cache.episodes['tester/1'] = [
        for (var id = 1; id <= 3; id++) _episode(id),
      ];
      for (var index = 0; index < 2; index++) {
        final edit = f.editor.markNextEpisode(f.view.collections.single);
        expect(await edit.timeout(const Duration(seconds: 2)), isNull);
      }
      expect(api.calls, 0);
      expect(f.view.collections.single.episodeStatus, 2);
      expect(f.queue.items.map((i) => i.payload['episode_id']), [1, 2]);
      expect(f.cache.episodes['tester/1']!.map((e) => e.type), [2, 2, 0]);
    },
  );

  test(
    'uncached chapters explain how to prepare offline use without waiting on network',
    () async {
      final api = _NeverApi();
      final f = CollectionModuleFixture(
        api: api,
        preferCachedReads: () => true,
      );
      addTearDown(f.dispose);
      expect(
        await f.editor.markNextEpisode(f.view.collections.single),
        contains('尚未缓存章节'),
      );
      expect(api.calls, 0);
      expect(f.queue.items, isEmpty);
    },
  );

  test(
    'an account change during an offline cache read never queues an edit',
    () async {
      final cache = _SlowCache();
      final f = CollectionModuleFixture(
        api: _NeverApi(),
        cache: cache,
        preferCachedReads: () => true,
      );
      addTearDown(f.dispose);
      final edit = f.editor.markNextEpisode(f.view.collections.single);
      await cache.started.future;
      f.account = const LibraryBatchAccount(
        userId: 2,
        username: 'other',
        generation: 2,
      );
      cache.answer.complete([_episode(1)]);
      expect(await edit, contains('登录状态已变化'));
      expect(f.queue.items, isEmpty);
    },
  );
}

UserEpisodeCollection _episode(int id) =>
    UserEpisodeCollection(episode: progressEpisode(id), type: 0, updatedAt: 0);

class _NeverApi extends BangumiApi {
  var calls = 0;
  @override
  Future<List<UserEpisodeCollection>> getEpisodeCollections(
    int subjectId, {
    int? episodeType = 0,
  }) {
    calls++;
    return Completer<List<UserEpisodeCollection>>().future;
  }
}

class _SlowCache extends BatchTestCache {
  final started = Completer<void>();
  final answer = Completer<List<UserEpisodeCollection>>();
  @override
  Future<List<UserEpisodeCollection>?> readEpisodeCollections(
    int subjectId, {
    String? username,
  }) {
    started.complete();
    return answer.future;
  }
}
