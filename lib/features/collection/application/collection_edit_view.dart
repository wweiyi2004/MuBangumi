import '../../../models/bangumi_models.dart';
import '../../../models/episode_edit.dart';

/// The portion of UI state an edit may read or replace. Authentication,
/// loading flags and sync counters remain owned by their respective modules.
class CollectionEditView {
  const CollectionEditView({
    this.collections = const [],
    this.updatingSubjects = const {},
    this.episodeUndo,
    this.lastEpisodeEdit,
    this.activityRevision = 0,
  });

  final List<UserCollection> collections;
  final Set<int> updatingSubjects;
  final EpisodeUndo? episodeUndo;
  final EpisodeEdit? lastEpisodeEdit;
  final int activityRevision;

  UserCollection? collectionFor(int subjectId) =>
      collections.where((item) => item.subjectId == subjectId).firstOrNull;

  CollectionEditView copyWith({
    List<UserCollection>? collections,
    Set<int>? updatingSubjects,
    EpisodeUndo? episodeUndo,
    bool clearEpisodeUndo = false,
    EpisodeEdit? lastEpisodeEdit,
    int? activityRevision,
  }) => CollectionEditView(
    collections: collections ?? this.collections,
    updatingSubjects: updatingSubjects ?? this.updatingSubjects,
    episodeUndo: clearEpisodeUndo ? null : episodeUndo ?? this.episodeUndo,
    lastEpisodeEdit: lastEpisodeEdit ?? this.lastEpisodeEdit,
    activityRevision: activityRevision ?? this.activityRevision,
  );
}
