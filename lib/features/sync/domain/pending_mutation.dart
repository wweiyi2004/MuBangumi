enum BangumiMutationKind { episode, collection, episodesBatch }

/// Persisted intent and its revision, independent of SQLite or UI state.
class PendingBangumiMutation {
  const PendingBangumiMutation({
    required this.id,
    required this.username,
    required this.kind,
    required this.mutationKey,
    required this.payload,
    required this.createdAt,
    required this.updatedAt,
    required this.revision,
    required this.attempts,
    required this.blocked,
    this.lastError,
    this.superseded = false,
  });

  final int id;
  final String username;
  final BangumiMutationKind kind;
  final String mutationKey;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int revision;
  final int attempts;
  final bool blocked;
  final String? lastError;
  final bool superseded;
}
