import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/models/schedule_models.dart';

void main() {
  test('season key round-trips and labels', () {
    const key = SeasonKey(year: 2026, quarter: 2);
    expect(key.id, '2026-Q2');
    expect(key.label, contains('夏季'));
    expect(SeasonKey.fromId(key.id), key);
  });

  test('schedule items serialize and group by weekday', () {
    final subject = Subject(
      id: 12,
      name: 'Chobits',
      nameCn: '人形电脑天使心',
      imageUrl: '',
      summary: '',
      episodeCount: 27,
      score: 7.5,
      rank: 100,
      date: '2002-04-02',
    );
    final schedule = SeasonSchedule(
      season: const SeasonKey(year: 2026, quarter: 1),
      items: [
        ScheduleItem.fromSubject(subject, weekday: DateTime.monday),
        ScheduleItem.fromSubject(
          subject.copyWithId(99),
          weekday: null,
          sortOrder: 1,
        ),
      ],
    );

    final json = schedule.toJson();
    final restored = SeasonSchedule.fromJson(json);
    expect(restored.items, hasLength(2));
    expect(restored.itemsOn(DateTime.monday), hasLength(1));
    expect(restored.unscheduled, hasLength(1));
    expect(restored.containsSubject(12), isTrue);
  });
}

extension on Subject {
  Subject copyWithId(int id) => Subject(
    id: id,
    name: name,
    nameCn: nameCn,
    imageUrl: imageUrl,
    summary: summary,
    episodeCount: episodeCount,
    score: score,
    rank: rank,
    date: date,
    type: type,
  );
}
