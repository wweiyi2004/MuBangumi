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
  });

  final List<UserCollection> collections;
  final Set<int> updatingSubjects;
  final EpisodeUndo? episodeUndo;
  final EpisodeEdit? lastEpisodeEdit;

  UserCollection? collectionFor(int subjectId) =>
      collections.where((item) => item.subjectId == subjectId).firstOrNull;

  CollectionEditView copyWith({
    List<UserCollection>? collections,
    Set<int>? updatingSubjects,
    EpisodeUndo? episodeUndo,
    bool clearEpisodeUndo = false,
    EpisodeEdit? lastEpisodeEdit,
  }) => CollectionEditView(
    collections: collections ?? this.collections,
    updatingSubjects: updatingSubjects ?? this.updatingSubjects,
    episodeUndo: clearEpisodeUndo ? null : episodeUndo ?? this.episodeUndo,
    lastEpisodeEdit: lastEpisodeEdit ?? this.lastEpisodeEdit,
  );
}
