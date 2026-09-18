import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/features/collection/domain/collection_reconciler.dart';
import 'package:mubangumi/features/sync/domain/pending_mutation.dart';
import 'package:mubangumi/models/bangumi_models.dart';

void main() {
  test(
    'pending status change retains review, privacy and chapter progress',
    () {
      final source = [_collection(1)];
      final merged = CollectionReconciler.overlayCollections(source, [
        _mutation(BangumiMutationKind.collection, {
          'subject_id': 1,
          'collection_type': CollectionType.onHold.value,
          'status_only': true,
          'rate': 0,
          'comment': '',
          'private': false,
          'local_episode_status': 0,
        }),
      ]);
      expect(merged.single.type, CollectionType.onHold);
      expect(merged.single.rate, 8);
      expect(merged.single.comment, '保留短评');
      expect(merged.single.private, isTrue);
      expect(merged.single.episodeStatus, 3);
      expect(source.single.type, CollectionType.doing);
    },
  );

  test(
    'old remote responses preserve newer edits even after the queue is empty',
    () {
      final remote = [_collection(1), _collection(2)];
      final local = [
        remote[0].copyWith(rate: 9),
        remote[1].copyWith(rate: 10),
        _collection(3),
      ];
      final result = CollectionReconciler.preserveChangedAfter(
        remote,
        4,
        current: local,
        subjectRevisions: {1: 5, 2: 4, 3: 6},
      );
      expect(result.map((item) => item.subjectId), [1, 2, 3]);
      expect(result.map((item) => item.rate), [9, 8, 8]);
      expect(remote, hasLength(2));
      expect(remote.first.rate, 8);
    },
  );

  test(
    'later chapter edits override completion without completing specials',
    () {
      final source = [_episode(1), _episode(2), _episode(3, episodeType: 1)];
      final result = CollectionReconciler.overlayEpisodes(1, source, [
        _mutation(BangumiMutationKind.collection, {
          'subject_id': 1,
          'complete_episodes': true,
        }),
        _mutation(BangumiMutationKind.episode, {
          'subject_id': 1,
          'episode_id': 1,
          'type': 0,
        }),
        _mutation(BangumiMutationKind.episode, {
          'subject_id': 2,
          'episode_id': 2,
          'type': 0,
        }),
        _mutation(BangumiMutationKind.episode, {
          'subject_id': 1,
          'episode_id': 1,
          'type': 2,
        }, superseded: true),
      ]);
      expect(result.map((item) => item.type), [0, 2, 0]);
      expect(source.map((item) => item.type), [0, 0, 0]);
    },
  );
}

UserCollection _collection(int id) => UserCollection.fromJson({
  'subject_id': id,
  'type': CollectionType.doing.value,
  'rate': 8,
  'ep_status': 3,
  'comment': '保留短评',
  'private': true,
  'subject': {'id': id, 'type': SubjectType.anime.value, 'name': '作品$id'},
});

UserEpisodeCollection _episode(int id, {int episodeType = 0}) =>
    UserEpisodeCollection.fromJson({
      'type': 0,
      'episode': {'id': id, 'type': episodeType, 'sort': id, 'name': 'EP$id'},
    });

PendingBangumiMutation _mutation(
  BangumiMutationKind kind,
  Map<String, dynamic> payload, {
  bool superseded = false,
}) => PendingBangumiMutation(
  id: 1,
  username: 'tester',
  kind: kind,
  mutationKey: 'test',
  payload: payload,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  revision: 1,
  attempts: 0,
  blocked: false,
  superseded: superseded,
);
