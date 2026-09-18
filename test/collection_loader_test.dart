import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/network/bangumi_api.dart';
import 'package:mubangumi/core/storage/bangumi_sync_store.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/models/library_batch.dart';

import 'support/collection_module_fixtures.dart';
import 'support/library_batch_fixtures.dart';

void main() {
  for (final cancellation in ['relogin', 'new load', 'dispose']) {
    test(
      'a refresh waiting for its local overlay cannot publish after $cancellation',
      () async {
        final api = _Api()
          ..anime = [batchFixtureCollection(2, type: SubjectType.anime)];
        final queue = _DelayedOverlay();
        final fixture = CollectionModuleFixture(api: api, queue: queue);
        addTearDown(fixture.dispose);
        final old = fixture.loader.refresh();
        await queue.started.future;
        fixture.updates.clear();
        if (cancellation == 'relogin') {
          fixture.account = const LibraryBatchAccount(
            userId: 1,
            username: 'tester',
            generation: 2,
          );
          fixture.editor.reset();
        } else if (cancellation == 'new load') {
          api.anime = [batchFixtureCollection(3, type: SubjectType.anime)];
          await fixture.loader.refresh();
          expect(fixture.view.collections.single.subjectId, 3);
          fixture.updates.clear();
        } else {
          fixture.loader.dispose();
        }
        queue.release.complete(const []);
        await old;
        expect(fixture.updates, isEmpty);
        expect(
          fixture.view.collections.single.subjectId,
          cancellation == 'new load' ? 3 : 1,
        );
      },
    );
  }

  test(
    'switching routes invalidates old pages even while queue reads are pending',
    () async {
      final api = _Api()
        ..anime = [batchFixtureCollection(2, type: SubjectType.anime)];
      final queue = _DelayedOverlay();
      final fixture = CollectionModuleFixture(api: api, queue: queue);
      addTearDown(fixture.dispose);
      final old = fixture.loader.loadInitial();
      await queue.started.future;
      fixture.loader.invalidate();
      api.anime = [batchFixtureCollection(3, type: SubjectType.anime)];
      expect(await fixture.loader.reloadAll(), isNull);
      fixture.updates.clear();
      queue.release.complete(const []);
      await old;
      expect(fixture.view.collections.single.subjectId, 3);
      expect(fixture.updates, isEmpty);
    },
  );

  test(
    'optional cache failures do not turn a completed load into an error',
    () async {
      final fixture = CollectionModuleFixture(
        api: _Api()
          ..anime = [batchFixtureCollection(2, type: SubjectType.anime)],
        cache: BatchTestCache()..failWrites = true,
      );
      addTearDown(fixture.dispose);
      await fixture.loader.loadInitial();
      expect(fixture.view.collections.single.subjectId, 2);
      expect(fixture.updates.last.isLoadingCollections, isFalse);
      expect(
        fixture.updates.every((progress) => progress.message == null),
        isTrue,
      );
    },
  );
}

class _Api extends BangumiApi {
  List<UserCollection> anime = [];
  @override
  Future<List<UserCollection>> getUserCollections(
    String username, {
    SubjectType? subjectType,
    CollectionType? collectionType,
    int? maxItems,
    Future<bool> Function(List<UserCollection>)? onPage,
  }) async => subjectType == SubjectType.anime ? anime : [];
}

class _DelayedOverlay extends MemoryBatchQueue {
  final started = Completer<void>();
  final release = Completer<List<PendingBangumiMutation>>();
  bool _used = false;
  @override
  Future<List<PendingBangumiMutation>> pendingFor(
    String username, {
    bool includeBlocked = false,
  }) {
    if (!_used) {
      _used = true;
      started.complete();
      return release.future;
    }
    return super.pendingFor(username, includeBlocked: includeBlocked);
  }
}
