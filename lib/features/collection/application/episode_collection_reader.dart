import '../../../models/bangumi_models.dart';
import '../../../models/library_batch.dart';

/// Read access needed by episode consumers, independent of the session's UI
/// state and the collection editor's write operations.
abstract interface class EpisodeCollectionReader {
  LibraryBatchAccount? get batchAccount;
  int get episodeRevision;
  UserCollection? batchCollection(int subjectId);

  Future<List<UserEpisodeCollection>?> readEpisodeSnapshot(int subjectId);
  Future<List<UserEpisodeCollection>> loadEpisodeCollections(
    int subjectId, {
    int? episodeType,
  });
  Future<List<UserEpisodeCollection>> applyPendingEpisodeChanges(
    int subjectId,
    List<UserEpisodeCollection> source, {
    int? afterRevision,
  });
}
