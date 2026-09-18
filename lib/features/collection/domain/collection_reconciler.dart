import '../../../models/bangumi_models.dart';
import '../../sync/domain/pending_mutation.dart';

/// Pure merging rules shared by collection loading and local queue overlays.
/// Overlay and merge inputs remain unchanged; malformed payloads preserve the same
/// best-effort behavior as the original session implementation.
abstract final class CollectionReconciler {
  static List<UserCollection> overlayCollections(
    List<UserCollection> source,
    List<PendingBangumiMutation> pending,
  ) {
    final merged = List<UserCollection>.from(source);
    try {
      for (final mutation in pending) {
        if (mutation.superseded) continue;
        final payload = mutation.payload;
        final subjectId = (payload['subject_id'] as num?)?.toInt();
        if (subjectId == null || subjectId <= 0) continue;
        final index = merged.indexWhere((item) => item.subjectId == subjectId);
        final previous = index < 0 ? null : merged[index];
        final localEpisodeStatus = (payload['local_episode_status'] as num?)
            ?.toInt();
        if (mutation.kind != BangumiMutationKind.collection) {
          if (previous != null && localEpisodeStatus != null) {
            merged[index] = previous.copyWith(
              episodeStatus: localEpisodeStatus,
            );
          }
          continue;
        }
        if (payload['status_only'] == true && previous != null) {
          merged[index] = previous.copyWith(
            type: CollectionType.fromValue(
              (payload['collection_type'] as num).toInt(),
            ),
            episodeStatus: payload['complete_episodes'] == true
                ? localEpisodeStatus
                : null,
          );
          continue;
        }
        Subject? subject = previous?.subject;
        final subjectJson = payload['subject'];
        if (subject == null && subjectJson is Map) {
          subject = Subject.fromJson(Map<String, dynamic>.from(subjectJson));
        }
        if (subject == null || subject.id <= 0) continue;
        final collection = UserCollection(
          subjectId: subjectId,
          type: CollectionType.fromValue(
            (payload['collection_type'] as num).toInt(),
          ),
          rate: (payload['rate'] as num?)?.toInt() ?? previous?.rate ?? 0,
          episodeStatus:
              subject.type.hasEpisodes &&
                  payload['complete_episodes'] != true &&
                  previous != null
              ? previous.episodeStatus
              : localEpisodeStatus ??
                    (payload['episode_status'] as num?)?.toInt() ??
                    previous?.episodeStatus ??
                    0,
          volumeStatus:
              (payload['volume_status'] as num?)?.toInt() ??
              previous?.volumeStatus ??
              0,
          updatedAt:
              DateTime.tryParse(
                payload['local_updated_at']?.toString() ?? '',
              ) ??
              mutation.updatedAt,
          subject: subject,
          comment: payload['comment']?.toString() ?? previous?.comment ?? '',
          tags: [
            for (final value
                in payload['tags'] as List? ?? previous?.tags ?? const [])
              value.toString(),
          ],
          private: payload['private'] == true,
        );
        if (index < 0) {
          merged.add(collection);
        } else {
          merged[index] = collection;
        }
      }
    } catch (_) {}
    sortCollections(merged);
    return merged;
  }

  static List<UserEpisodeCollection> overlayEpisodes(
    int subjectId,
    List<UserEpisodeCollection> source,
    List<PendingBangumiMutation> pending,
  ) {
    final merged = List<UserEpisodeCollection>.from(source);
    try {
      for (final mutation in pending) {
        if (mutation.superseded) continue;
        final payload = mutation.payload;
        if ((payload['subject_id'] as num?)?.toInt() != subjectId) continue;
        if (mutation.kind == BangumiMutationKind.episode) {
          final episodeId = (payload['episode_id'] as num).toInt();
          final type = (payload['type'] as num).toInt();
          final index = merged.indexWhere(
            (item) => item.episode.id == episodeId,
          );
          if (index >= 0) merged[index] = merged[index].copyWith(type: type);
        } else if (mutation.kind == BangumiMutationKind.episodesBatch) {
          final episodeIds = {
            for (final value in payload['episode_ids'] as List? ?? const [])
              (value as num).toInt(),
          };
          final type = (payload['type'] as num).toInt();
          for (var index = 0; index < merged.length; index++) {
            if (episodeIds.contains(merged[index].episode.id)) {
              merged[index] = merged[index].copyWith(type: type);
            }
          }
        } else if (mutation.kind == BangumiMutationKind.collection &&
            payload['complete_episodes'] == true) {
          for (var index = 0; index < merged.length; index++) {
            if (merged[index].episode.type == 0) {
              merged[index] = merged[index].copyWith(type: 2);
            }
          }
        }
      }
    } catch (_) {}
    return merged;
  }

  /// A collection response may have started before a local edit and finish
  /// after the corresponding queue entry has already uploaded and been
  /// removed. Preserve the newer in-memory value for exactly those subjects;
  /// requests started after the edit remain server-authoritative.
  static List<UserCollection> preserveChangedAfter(
    List<UserCollection> source,
    int requestMutationRevision, {
    required List<UserCollection> current,
    required Map<int, int> subjectRevisions,
  }) {
    final merged = List<UserCollection>.from(source);
    final byId = <int, UserCollection>{};
    for (final item in current) {
      byId.putIfAbsent(item.subjectId, () => item);
    }
    for (final entry in subjectRevisions.entries) {
      if (entry.value <= requestMutationRevision) continue;
      final local = byId[entry.key];
      if (local == null) continue;
      final index = merged.indexWhere(
        (item) => item.subjectId == local.subjectId,
      );
      if (index < 0) {
        merged.add(local);
      } else {
        merged[index] = local;
      }
    }
    return merged;
  }

  static List<UserCollection> replaceType(
    List<UserCollection> current,
    SubjectType type,
    List<UserCollection> page,
  ) => [...current.where((item) => item.subject.type != type), ...page];

  static void sortCollections(List<UserCollection> items) {
    items.sort((a, b) {
      final aTime = a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime);
    });
  }
}
