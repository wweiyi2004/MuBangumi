import 'bangumi_models.dart';

enum AnimePrize {
  good('好番剧奖', '8 分及以上', 8, 10),
  bad('坏番剧奖', '5 分及以下', 0, 5);

  const AnimePrize(this.label, this.description, this.minimum, this.maximum);
  final String label, description;
  final double minimum, maximum;
  bool permits(Subject subject) =>
      subject.id > 0 &&
      subject.type == SubjectType.anime &&
      !subject.nsfw &&
      subject.score.isFinite &&
      subject.score > 0 &&
      subject.score >= minimum &&
      subject.score <= maximum;
}

class AnimeLotteryPage {
  const AnimeLotteryPage({required this.subjects, required this.total});
  final List<Subject> subjects;
  final int total;
}
