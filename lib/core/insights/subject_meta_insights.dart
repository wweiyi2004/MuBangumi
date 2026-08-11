import '../network/bangumi_support.dart';

const subjectUnknownStaffRole = '职位未标注';

class SubjectStaffRoleGroup {
  const SubjectStaffRoleGroup({required this.role, required this.people});

  final String role;
  final List<SubjectPerson> people;
}

List<SubjectStaffRoleGroup> groupSubjectStaffByRole(
  Iterable<SubjectPerson> people,
) {
  final grouped = <String, List<SubjectPerson>>{};
  final seen = <(String, int)>{};
  for (final person in people) {
    final relation = person.relation.trim();
    final role = relation.isEmpty ? subjectUnknownStaffRole : relation;
    if (!seen.add((role, person.id))) continue;
    grouped.putIfAbsent(role, () => []).add(person);
  }
  return [
    for (final entry in grouped.entries)
      SubjectStaffRoleGroup(role: entry.key, people: entry.value),
  ];
}
