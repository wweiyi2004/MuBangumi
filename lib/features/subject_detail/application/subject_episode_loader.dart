import 'dart:async';

import '../../../core/network/bangumi_api.dart';
import '../../../core/storage/snapshot_cache.dart';
import '../../../models/bangumi_models.dart';
import '../../../models/library_batch.dart';
import '../../collection/application/episode_collection_reader.dart';

class SubjectEpisodeProgress {
  const SubjectEpisodeProgress({
    this.episodes,
    this.types,
    this.loading,
    this.error,
    this.clearError = false,
    this.fromCache,
    this.cachedAt,
  });

  final List<Episode>? episodes;
  final Map<int, int>? types;
  final bool? loading;
  final String? error;
  final bool clearError;
  final bool? fromCache;
  final DateTime? cachedAt;
}

/// Loads public episodes or the current account's progress. Disk restoration
/// and network requests run independently; a late cache cannot replace a fresh
/// response, and every publication belongs to one request and one login.
class SubjectEpisodeLoader {
  SubjectEpisodeLoader({
    required this.subject,
    required this._api,
    required this._collections,
    required this.onProgress,
  });

  final Subject subject;
  final BangumiApi _api;
  final EpisodeCollectionReader _collections;
  final void Function(SubjectEpisodeProgress progress) onProgress;
  int _generation = 0;
  bool _disposed = false;

  bool _current(int generation, LibraryBatchAccount? account) {
    if (_disposed || generation != _generation) return false;
    final current = _collections.batchAccount;
    return current?.generation == account?.generation &&
        current?.userId == account?.userId &&
        current?.username == account?.username;
  }

  /// Silent loads update progress after a collection edit without replacing
  /// the visible list with a spinner or reporting an optional refresh failure.
  Future<void> load({bool silent = false}) async {
    if (_disposed || !subject.type.hasEpisodes) return;
    final generation = ++_generation;
    final account = _collections.batchAccount;
    final revision = _collections.episodeRevision;
    final hasCollection = _collections.batchCollection(subject.id) != null;
    var networkApplied = false;
    if (!silent) {
      onProgress(const SubjectEpisodeProgress(loading: true, clearError: true));
    }

    Future<void> restoreCache() async {
      if (!hasCollection) return;
      try {
        final cached = await _collections.readEpisodeSnapshot(subject.id);
        if (cached == null ||
            !_current(generation, account) ||
            networkApplied) {
          return;
        }
        final local = await _collections.applyPendingEpisodeChanges(
          subject.id,
          cached,
          afterRevision: revision,
        );
        if (!_current(generation, account) || networkApplied) return;
        _publishItems(
          local,
          fromCache: true,
          cachedAt: cached is SnapshotItems<UserEpisodeCollection>
              ? cached.savedAt
              : null,
        );
      } catch (_) {
        // Optional storage must not delay or fail the live request.
      }
    }

    if (!silent) unawaited(restoreCache());
    try {
      if (hasCollection) {
        final items = await _collections.loadEpisodeCollections(
          subject.id,
          episodeType: null,
        );
        if (!_current(generation, account)) return;
        networkApplied = true;
        _publishItems(items);
      } else {
        final episodes = await _api.getEpisodes(subject.id, episodeType: null);
        if (!_current(generation, account)) return;
        networkApplied = true;
        onProgress(
          SubjectEpisodeProgress(
            episodes: episodes,
            types: const {},
            fromCache: false,
          ),
        );
      }
    } catch (_) {
      if (!silent && _current(generation, account)) {
        onProgress(const SubjectEpisodeProgress(error: '章节加载失败，请重试'));
      }
    } finally {
      if (_current(generation, account)) {
        onProgress(const SubjectEpisodeProgress(loading: false));
      }
    }
  }

  void _publishItems(
    List<UserEpisodeCollection> items, {
    bool fromCache = false,
    DateTime? cachedAt,
  }) {
    onProgress(
      SubjectEpisodeProgress(
        episodes: [for (final item in items) item.episode],
        types: {for (final item in items) item.episode.id: item.type},
        fromCache: fromCache,
        cachedAt: cachedAt,
      ),
    );
  }

  void dispose() {
    _disposed = true;
    _generation++;
  }
}
