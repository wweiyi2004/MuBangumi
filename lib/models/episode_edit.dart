/// A successful local edit. The revision identifies one operation, not merely
/// an episode whose status might have changed again since the UI showed it.
class EpisodeEdit {
  const EpisodeEdit({
    required this.subjectId,
    required this.episodeId,
    required this.type,
    required this.revision,
  });
  final int subjectId;
  final int episodeId;
  final int type;
  final int revision;
}

class EpisodeUndo {
  const EpisodeUndo({
    required this.userId,
    required this.username,
    required this.authGeneration,
    required this.change,
    required this.previousType,
    required this.previousCount,
    required this.subjectTitle,
    required this.episodeLabel,
  });
  final int userId;
  final String username;
  final int authGeneration;
  final EpisodeEdit change;
  final int previousType;
  final int? previousCount;
  final String subjectTitle;
  final String episodeLabel;
  String get message =>
      '$subjectTitle · $episodeLabel已${switch (change.type) {
        2 => '标记看过',
        1 => '标记想看',
        3 => '标记抛弃',
        _ => '取消标记',
      }}';
}
