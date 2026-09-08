import 'bangumi_models.dart';

class HiddenRecommendation {
  const HiddenRecommendation({
    required this.subjectId,
    required this.title,
    required this.type,
    required this.hiddenAt,
  });
  final int subjectId;
  final String title;
  final SubjectType type;
  final DateTime hiddenAt;
  factory HiddenRecommendation.fromSubject(Subject subject) =>
      HiddenRecommendation(
        subjectId: subject.id,
        title: subject.displayName,
        type: subject.type,
        hiddenAt: DateTime.now(),
      );
}
