import 'package:mubangumi/core/network/bangumi_api.dart';
import 'package:mubangumi/features/collection/application/collection_edit_view.dart';
import 'package:mubangumi/features/collection/application/collection_editor.dart';
import 'package:mubangumi/features/collection/application/collection_loader.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/models/library_batch.dart';

import 'library_batch_fixtures.dart';

/// Constructs only collection modules: no session bootstrap, credentials or
/// Riverpod container. Reuses the existing in-memory queue/cache test doubles.
class CollectionModuleFixture {
  CollectionModuleFixture({
    BangumiApi? api,
    MemoryBatchQueue? queue,
    BatchTestCache? cache,
    bool Function()? preferCachedReads,
  }) : queue = queue ?? MemoryBatchQueue(),
       cache = cache ?? BatchTestCache() {
    editor = CollectionEditor(
      api: api ?? BangumiApi(),
      snapshotCache: this.cache,
      syncStore: this.queue,
      readAccount: () => account,
      readView: () => view,
      writeView: (next) => view = next,
      isAlive: () => true,
      syncPendingChanges: () async {
        syncCalls++;
      },
      refreshPendingCount: (username) => this.queue.countFor(username ?? ''),
      messageFor: (error) => error.toString(),
      preferCachedReads: preferCachedReads,
    );
    loader = CollectionLoader(
      api: api ?? BangumiApi(),
      snapshotCache: this.cache,
      editor: editor,
      syncPendingChanges: () async {
        syncCalls++;
      },
      onProgress: (progress) {
        updates.add(progress);
        view = view.copyWith(collections: progress.collections);
      },
      messageFor: (error) => error.toString(),
    );
  }

  final MemoryBatchQueue queue;
  final BatchTestCache cache;
  LibraryBatchAccount? account = const LibraryBatchAccount(
    userId: 1,
    username: 'tester',
    generation: 1,
  );
  CollectionEditView view = CollectionEditView(
    collections: [batchFixtureCollection(1, type: SubjectType.anime)],
  );
  late final CollectionEditor editor;
  late final CollectionLoader loader;
  final updates = <CollectionLoadProgress>[];
  int syncCalls = 0;

  void dispose() {
    loader.dispose();
    editor.dispose();
  }
}
