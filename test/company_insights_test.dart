import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/insights/company_insights.dart';
import 'package:mubangumi/core/network/bangumi_support.dart';
import 'package:mubangumi/models/bangumi_models.dart';

void main() {
  MonoLinkedSubject link(int id, String staff) => MonoLinkedSubject(
    id: id,
    name: 'Subject $id',
    nameCn: '作品$id',
    imageUrl: '',
    staff: staff,
    type: SubjectType.anime,
  );

  Subject subject(int id, String date) => Subject(
    id: id,
    name: 'Subject $id',
    nameCn: '作品$id',
    imageUrl: '',
    summary: '',
    episodeCount: 12,
    score: 0,
    rank: 0,
    date: date,
  );

  test('counts exact company credit labels by frequency', () {
    final counts = countCompanyRoles([
      link(1, '动画制作'),
      link(2, '动画制作'),
      link(3, '制作协力'),
      link(4, ''),
    ]);

    expect(counts.keys.first, '动画制作');
    expect(counts['动画制作'], 2);
    expect(counts['制作协力'], 1);
    expect(counts[companyUnknownRole], 1);
  });

  test('groups only dated credits by descending year and date', () {
    final links = [link(1, '动画制作'), link(2, '制作协力'), link(3, '')];
    final credits = buildCompanyWorkCredits(links, {
      1: subject(1, '2024-01-01'),
      2: subject(2, '2025-04-03'),
      3: subject(3, ''),
    });
    final grouped = groupCompanyCreditsByYear(credits);

    expect(grouped.keys, [2025, 2024]);
    expect(grouped[2025]!.single.link.id, 2);
    expect(credits.last.year, isNull);
  });

  test('merges multiple company positions into one work credit', () {
    final credits = buildCompanyWorkCredits(
      [link(1, '动画制作'), link(1, '原作'), link(2, '制作协力')],
      {1: subject(1, '2024-01-01'), 2: subject(2, '2023-01-01')},
    );

    expect(credits, hasLength(2));
    expect(credits.first.roles, ['动画制作', '原作']);
    expect(credits.first.role, '动画制作 / 原作');
    expect(
      uniqueCompanyWorkLinks(credits.expand((item) => item.links)),
      hasLength(2),
    );
  });

  test('rejects malformed and implausible release years', () {
    expect(companySubjectYear(subject(1, '2026-08-11')), 2026);
    expect(companySubjectYear(subject(2, 'unknown')), isNull);
    expect(companySubjectYear(subject(3, '1200-01-01')), isNull);
  });
}
