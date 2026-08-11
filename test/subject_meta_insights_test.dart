import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/insights/subject_meta_insights.dart';
import 'package:mubangumi/core/network/bangumi_support.dart';

void main() {
  SubjectPerson person(int id, String relation) => SubjectPerson(
    id: id,
    name: 'Person $id',
    nameCn: '人物$id',
    imageUrl: '',
    relation: relation,
    career: const [],
  );

  test('groups staff by exact role while preserving API order', () {
    final groups = groupSubjectStaffByRole([
      person(1, '原作'),
      person(2, '导演'),
      person(3, '原作'),
      person(4, ''),
    ]);

    expect(groups.map((item) => item.role), [
      '原作',
      '导演',
      subjectUnknownStaffRole,
    ]);
    expect(groups.first.people.map((item) => item.id), [1, 3]);
  });

  test('deduplicates the same person only inside the same role', () {
    final groups = groupSubjectStaffByRole([
      person(1, '原作'),
      person(1, '原作'),
      person(1, '导演'),
    ]);

    expect(groups, hasLength(2));
    expect(groups.first.people, hasLength(1));
    expect(groups.last.people, hasLength(1));
  });
}
