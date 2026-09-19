import 'dart:async';

import '../../../core/network/bangumi_api.dart';
import '../../../core/storage/snapshot_cache.dart';
import '../../../models/bangumi_models.dart';
import '../../../models/library_batch.dart';
import '../../../models/collection_coverage.dart';
import '../domain/collection_reconciler.dart';
import 'collection_editor.dart';

class CollectionLoadProgress {
  const CollectionLoadProgress({
    this.collections,
    this.isRefreshing,
    this.isLoadingCollections,
    this.releaseInitialWait = false,
    this.message,
    this.clearMessage = false,
    this.isUsingCachedCollections,
    this.coverage,
  });

  final List<UserCollection>? collections;
  final bool? isRefreshing;
  final bool? isLoadingCollections;
  final bool releaseInitialWait;
  final String? message;
  final bool clearMessage;
  final bool? isUsingCachedCollections;
  final CollectionCoverage? coverage;
}

typedef _Load = ({
  LibraryBatchAccount account,
  int generation,
  Set<SubjectType> completedTypes,
});

/// Owns collection request lifetimes and paging. Each continuation checks both
/// the login and the load generation, including after local queue reads.
class CollectionLoader {
  CollectionLoader({
    required this._api,
    required this._snapshotCache,
    required this._editor,
    required this.syncPendingChanges,
    required this.onProgress,
    required this.messageFor,
  });

  final BangumiApi _api;
  final SnapshotCache _snapshotCache;
  final CollectionEditor _editor;
  final Future<void> Function() syncPendingChanges;
  final void Function(CollectionLoadProgress progress) onProgress;
  final String Function(Object error) messageFor;
  int _generation = 0;
  bool _disposed = false;

  _Load? _begin() {
    if (_disposed) return null;
    final account = _editor.batchAccount;
    if (account == null) return null;
    return (
      account: account,
      generation: ++_generation,
      completedTypes: <SubjectType>{},
    );
  }

  bool _current(_Load load) =>
      !_disposed &&
      load.generation == _generation &&
      _editor.isCurrentBatchAccount(load.account);

  void invalidate() => _generation++;

  Future<void> loadInitial() async {
    final load = _begin();
    if (load == null) return;
    // Initial collections must not wait for a slow pending upload.
    unawaited(syncPendingChanges());
    await _loadAnime(load, initial: true);
  }

  Future<void> refresh({bool showIndicator = true}) async {
    final load = _begin();
    if (load == null) return;
    await syncPendingChanges();
    if (!_current(load)) return;
    if (showIndicator) {
      onProgress(
        const CollectionLoadProgress(
          isRefreshing: true,
          isLoadingCollections: true,
          clearMessage: true,
        ),
      );
    }
    await _loadAnime(load, initial: false);
  }

  Future<void> _loadAnime(_Load load, {required bool initial}) async {
    final revision = _editor.episodeRevision;
    final username = load.account.username;
    try {
      final anime = await _api.getUserCollections(
        username,
        subjectType: SubjectType.anime,
        onPage: initial ? (items) => _publishPage(load, revision, items) : null,
      );
      if (!_current(load)) return;
      load.completedTypes.add(SubjectType.anime);
      var merged = CollectionReconciler.replaceType(
        _editor.collections,
        SubjectType.anime,
        anime,
      );
      merged = await _editor.overlayPendingCollections(username, merged);
      if (!_current(load)) return;
      merged = _editor.preserveCollectionsChangedAfter(merged, revision);
      CollectionReconciler.sortCollections(merged);
      onProgress(
        CollectionLoadProgress(
          collections: merged,
          coverage: _coverage(load, merged.length),
          releaseInitialWait: true,
          isRefreshing: false,
          isLoadingCollections: true,
          clearMessage: !initial,
        ),
      );
      _saveSnapshot(load, merged);
      await _loadOtherTypes(load);
    } catch (error) {
      if (!_current(load)) return;
      final hasCache = _editor.collections.isNotEmpty;
      final message = initial
          ? '${hasCache ? '收藏同步失败，已显示本地缓存' : '收藏同步失败'}：${messageFor(error)}'
          : hasCache
          ? '刷新失败，已保留本地数据：${messageFor(error)}'
          : messageFor(error);
      onProgress(
        CollectionLoadProgress(
          releaseInitialWait: true,
          isRefreshing: false,
          isLoadingCollections: false,
          isUsingCachedCollections: hasCache,
          message: message,
        ),
      );
    }
  }

  Future<void> _loadOtherTypes(_Load load) async {
    final username = load.account.username;
    try {
      // Load remaining types sequentially to avoid flooding the network after
      // login; publish each page while keeping unrelated cached types visible.
      for (final type in SubjectType.values.where(
        (type) => type != SubjectType.anime,
      )) {
        if (!_current(load)) return;
        final revision = _editor.episodeRevision;
        final items = await _api.getUserCollections(
          username,
          subjectType: type,
          onPage: (items) => _publishPage(load, revision, items),
        );
        if (!_current(load)) return;
        load.completedTypes.add(type);
        var merged = CollectionReconciler.replaceType(
          _editor.collections,
          type,
          items,
        );
        merged = await _editor.overlayPendingCollections(username, merged);
        if (!_current(load)) return;
        merged = _editor.preserveCollectionsChangedAfter(merged, revision);
        CollectionReconciler.sortCollections(merged);
        onProgress(
          CollectionLoadProgress(
            collections: merged,
            coverage: _coverage(load, merged.length),
            isLoadingCollections: true,
            isRefreshing: false,
          ),
        );
        _saveSnapshot(load, merged);
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }
      if (!_current(load)) return;
      onProgress(
        const CollectionLoadProgress(
          isLoadingCollections: false,
          isRefreshing: false,
          isUsingCachedCollections: false,
        ),
      );
    } catch (error) {
      if (!_current(load)) return;
      onProgress(
        CollectionLoadProgress(
          isLoadingCollections: false,
          isRefreshing: false,
          isUsingCachedCollections: _editor.collections.isNotEmpty,
          message: _editor.collections.isNotEmpty
              ? '部分收藏同步失败，已保留本地数据：${messageFor(error)}'
              : '部分收藏同步失败：${messageFor(error)}',
        ),
      );
    }
  }

  Future<bool> _publishPage(
    _Load load,
    int revision,
    List<UserCollection> items,
  ) async {
    if (!_current(load)) return false;
    if (items.isEmpty) return true;
    final byId = {
      for (final item in _editor.collections) item.subjectId: item,
      for (final item in items) item.subjectId: item,
    };
    var merged = await _editor.overlayPendingCollections(
      load.account.username,
      byId.values.toList(),
    );
    if (!_current(load)) return false;
    merged = _editor.preserveCollectionsChangedAfter(merged, revision);
    CollectionReconciler.sortCollections(merged);
    onProgress(
      CollectionLoadProgress(
        collections: merged,
        coverage: _coverage(load, merged.length),
        releaseInitialWait: true,
        isRefreshing: false,
        isLoadingCollections: true,
      ),
    );
    return true;
  }

  /// Used after route changes. Returns an error for the route notice while
  /// publishing loading state through the same guarded path as normal loads.
  Future<String?> reloadAll() async {
    final load = _begin();
    if (load == null) return null;
    await syncPendingChanges();
    if (!_current(load)) return null;
    final revision = _editor.episodeRevision;
    try {
      final pages = await Future.wait([
        for (final type in SubjectType.values)
          _api.getUserCollections(load.account.username, subjectType: type),
      ]);
      if (!_current(load)) return null;
      load.completedTypes.addAll(SubjectType.values);
      var merged = await _editor.overlayPendingCollections(
        load.account.username,
        [for (final page in pages) ...page],
      );
      if (!_current(load)) return null;
      merged = _editor.preserveCollectionsChangedAfter(merged, revision);
      onProgress(
        CollectionLoadProgress(
          collections: merged,
          coverage: _coverage(load, merged.length),
          isRefreshing: false,
          isLoadingCollections: false,
          clearMessage: true,
          isUsingCachedCollections: false,
        ),
      );
      _saveSnapshot(load, merged);
      return null;
    } catch (error) {
      if (!_current(load)) return null;
      final message = messageFor(error);
      onProgress(
        CollectionLoadProgress(
          isRefreshing: false,
          isLoadingCollections: false,
          isUsingCachedCollections: _editor.collections.isNotEmpty,
          message: message,
        ),
      );
      return message;
    }
  }

  CollectionCoverage _coverage(_Load load, int count) {
    final complete = load.completedTypes.length == SubjectType.values.length;
    return CollectionCoverage(
      loadedCount: count,
      sourceTotal: complete ? count : null,
      completeness: complete
          ? CollectionCompleteness.complete
          : CollectionCompleteness.partial,
      loadedTypes: load.completedTypes,
    );
  }

  void _saveSnapshot(_Load load, List<UserCollection> collections) {
    unawaited(() async {
      try {
        if (!_current(load)) return;
        await _snapshotCache.writeCollections(
          load.account.username,
          CollectionSnapshot(
            collections,
            coverage: _coverage(load, collections.length),
          ),
        );
      } catch (_) {
        // Collections are usable even when an optional cache write fails.
      }
    }());
  }

  void dispose() {
    _disposed = true;
    invalidate();
  }
}
