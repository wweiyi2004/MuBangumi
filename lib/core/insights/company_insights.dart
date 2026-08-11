import '../../models/bangumi_models.dart';
import '../network/bangumi_support.dart';

const companyUnknownRole = '职位未标注';

class CompanyWorkCredit {
  CompanyWorkCredit({required this.link, this.subject}) : links = [link];

  CompanyWorkCredit._({required this.links, this.subject}) : link = links.first;

  final MonoLinkedSubject link;
  final List<MonoLinkedSubject> links;
  final Subject? subject;

  List<String> get roles =>
      {for (final item in links) normalizedCompanyRole(item.staff)}.toList();

  String get role => roles.join(' / ');

  String get eps => {
    for (final item in links)
      if (item.eps.trim().isNotEmpty) item.eps.trim(),
  }.join(' / ');

  int? get year => companySubjectYear(subject);
}

String normalizedCompanyRole(String role) {
  final value = role.trim();
  return value.isEmpty ? companyUnknownRole : value;
}

int? companySubjectYear(Subject? subject) {
  if (subject == null) return null;
  final match = RegExp(r'^(\d{4})').firstMatch(subject.date.trim());
  if (match == null) return null;
  final year = int.tryParse(match.group(1)!);
  return year != null && year >= 1800 && year <= 2200 ? year : null;
}

List<MonoLinkedSubject> uniqueCompanyWorkLinks(
  Iterable<MonoLinkedSubject> links,
) {
  final unique = <int, MonoLinkedSubject>{};
  for (final link in links) {
    unique.putIfAbsent(link.id, () => link);
  }
  return unique.values.toList();
}

List<CompanyWorkCredit> buildCompanyWorkCredits(
  Iterable<MonoLinkedSubject> links,
  Map<int, Subject> details,
) {
  final grouped = <int, List<MonoLinkedSubject>>{};
  for (final link in links) {
    grouped.putIfAbsent(link.id, () => []).add(link);
  }
  return [
    for (final entry in grouped.entries)
      CompanyWorkCredit._(links: entry.value, subject: details[entry.key]),
  ];
}

Map<String, int> countCompanyRoles(Iterable<MonoLinkedSubject> links) {
  final counts = <String, int>{};
  final seen = <(int, String)>{};
  for (final link in links) {
    final role = normalizedCompanyRole(link.staff);
    if (!seen.add((link.id, role))) continue;
    counts.update(role, (value) => value + 1, ifAbsent: () => 1);
  }
  final entries = counts.entries.toList()
    ..sort((a, b) {
      final byCount = b.value.compareTo(a.value);
      return byCount != 0 ? byCount : a.key.compareTo(b.key);
    });
  return Map.fromEntries(entries);
}

Map<int, List<CompanyWorkCredit>> groupCompanyCreditsByYear(
  Iterable<CompanyWorkCredit> credits,
) {
  final grouped = <int, List<CompanyWorkCredit>>{};
  for (final credit in credits) {
    final year = credit.year;
    if (year == null) continue;
    grouped.putIfAbsent(year, () => []).add(credit);
  }
  for (final items in grouped.values) {
    items.sort((a, b) {
      final byDate = (b.subject?.date ?? '').compareTo(a.subject?.date ?? '');
      return byDate != 0
          ? byDate
          : a.link.displayName.compareTo(b.link.displayName);
    });
  }
  final years = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
  return {for (final year in years) year: grouped[year]!};
}
