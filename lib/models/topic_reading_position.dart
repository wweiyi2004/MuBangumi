class TopicReadingPosition {
  const TopicReadingPosition({required this.postId, required this.index});
  final String postId;
  final int index;
}

abstract class TopicReadingRepository {
  Future<TopicReadingPosition?> readTopicPosition(String account, String topic);
  Future<void> saveTopicPosition(
    String account,
    String topic,
    TopicReadingPosition position,
  );
}
