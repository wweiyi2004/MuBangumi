import 'package:mubangumi/core/storage/browsing_store.dart';
import 'package:mubangumi/models/recommendation_feedback.dart';

class MemoryRecommendationFeedback implements RecommendationFeedbackRepository {
  final records = <int, Map<int, HiddenRecommendation>>{};
  final failedSubjects = <int>{};
  bool failRead = false;
  Future<List<HiddenRecommendation>>? pendingRead;
  Future<void>? pendingWrite;
  int writes = 0;
  Future<void> _writes = Future.value();
  @override
  Future<List<HiddenRecommendation>> readHiddenRecommendations(
    int ownerId,
  ) async {
    await _writes;
    if (failRead) throw StateError('read failed');
    return pendingRead ?? (records[ownerId]?.values.toList() ?? []);
  }

  Future<void> _write(int ownerId, int id, HiddenRecommendation? item) {
    writes++;
    final result = _writes.then((_) async {
      await pendingWrite;
      if (failedSubjects.contains(id)) throw StateError('write failed');
      final map = records.putIfAbsent(ownerId, () => {});
      if (item == null) {
        map.remove(id);
      } else {
        map[id] = item;
      }
    });
    _writes = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  @override
  Future<void> hideRecommendation(int ownerId, HiddenRecommendation item) =>
      _write(ownerId, item.subjectId, item);
  @override
  Future<void> restoreRecommendation(int ownerId, int subjectId) =>
      _write(ownerId, subjectId, null);
}
