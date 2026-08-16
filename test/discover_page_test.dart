import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/network/bangumi_api.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/screens/discover_page.dart';
import 'package:mubangumi/state/session_controller.dart';
import 'package:mubangumi/widgets/subject_widgets.dart';

class _FakeBangumiApi extends BangumiApi {
  _FakeBangumiApi([this.subjects = const []]);

  final List<Subject> subjects;
  int? lastBrowseYear;
  int? lastStartYear;

  @override
  Future<List<Subject>> browseSubjects({
    required SubjectType type,
    int? year,
    int? month,
    String sort = 'rank',
    int limit = 24,
    int offset = 0,
  }) async {
    lastBrowseYear = year;
    return offset == 0 ? subjects : const [];
  }

  @override
  Future<List<Subject>> searchSubjects(
    String keyword, {
    int limit = 24,
    int offset = 0,
    String sort = 'match',
    int minimumRating = 0,
    int startYear = 0,
    List<String> tags = const [],
    List<String> metaTags = const [],
    SubjectType subjectType = SubjectType.anime,
  }) async {
    lastStartYear = startYear;
    return const [];
  }
}

List<Override> _overrides([BangumiApi? api]) => [
  bangumiApiProvider.overrideWithValue(api ?? _FakeBangumiApi()),
  discoverCollectionsProvider.overrideWithValue(const <UserCollection>[]),
];

/// Progress indicators animate forever; avoid pumpAndSettle for Discover loads.
Future<void> _pumpDiscoverReady(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (find.byType(SubjectPosterCard).evaluate().isNotEmpty) return;
  }
}

void main() {
  test('resolves each discover query mode without mixing browse results', () {
    expect(
      resolveDiscoverQueryMode(
        target: DiscoverSearchTarget.subject,
        keyword: '',
        tag: '',
      ),
      DiscoverQueryMode.browse,
    );
    expect(
      resolveDiscoverQueryMode(
        target: DiscoverSearchTarget.subject,
        keyword: '',
        tag: '科幻',
      ),
      DiscoverQueryMode.subjectSearch,
    );
    expect(
      resolveDiscoverQueryMode(
        target: DiscoverSearchTarget.subject,
        keyword: '',
        tag: '',
        metaTags: const ['TV'],
      ),
      DiscoverQueryMode.subjectSearch,
    );
    expect(
      resolveDiscoverQueryMode(
        target: DiscoverSearchTarget.character,
        keyword: '',
        tag: '',
      ),
      DiscoverQueryMode.characterPrompt,
    );
    expect(
      resolveDiscoverQueryMode(
        target: DiscoverSearchTarget.person,
        keyword: '福山润',
        tag: '',
      ),
      DiscoverQueryMode.personSearch,
    );
  });

  testWidgets('character and person targets show prompts before searching', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(),
        child: const MaterialApp(home: Scaffold(body: DiscoverPage())),
      ),
    );
    await tester.pump();

    await tester.tap(find.widgetWithText(ChoiceChip, '角色'));
    await tester.pump();
    expect(find.text('输入角色名开始搜索'), findsOneWidget);
    expect(find.text('动画季度榜'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, '人物'));
    await tester.pump();
    expect(find.text('输入人物名开始搜索'), findsOneWidget);
    expect(find.text('动画季度榜'), findsNothing);
  });

  testWidgets('tag deep link does not duplicate the tag as a keyword', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(),
        child: const MaterialApp(
          home: Scaffold(body: DiscoverPage(initialTag: '科幻')),
        ),
      ),
    );
    await tester.pump();

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );
    expect(find.text('标签：科幻'), findsOneWidget);
    expect(find.text('动画搜索结果'), findsOneWidget);

    await tester.tap(find.byTooltip('清空搜索'));
    await _pumpDiscoverReady(tester);
    expect(find.text('标签：科幻'), findsNothing);
    expect(find.text('动画季度榜'), findsOneWidget);
  });

  testWidgets('large subject result sets build only visible sliver children', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final subjects = [
      for (var id = 1; id <= 120; id++)
        Subject(
          id: id,
          name: 'Subject $id',
          nameCn: '条目 $id',
          imageUrl: '',
          summary: '',
          episodeCount: 12,
          score: 8,
          rank: id,
          date: '2026-01-01',
        ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(_FakeBangumiApi(subjects)),
        child: const MaterialApp(home: Scaffold(body: DiscoverPage())),
      ),
    );
    await _pumpDiscoverReady(tester);

    final builtTiles = find.byType(SubjectPosterCard).evaluate().length;
    expect(builtTiles, greaterThan(0));
    expect(builtTiles, lessThan(subjects.length));
    expect(find.text('条目 120'), findsNothing);
  });

  testWidgets('discover browse year accepts manual values within anime range', (
    tester,
  ) async {
    final api = _FakeBangumiApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(api),
        child: const MaterialApp(home: Scaffold(body: DiscoverPage())),
      ),
    );
    await tester.pump();

    await tester.tap(find.widgetWithText(OutlinedButton, '筛选'));
    await tester.pumpAndSettle();

    final yearInput = find.byKey(const ValueKey('discover-browse-year-input'));
    expect(yearInput, findsOneWidget);
    expect(
      tester.widget<TextField>(yearInput).controller!.text,
      '${DateTime.now().year}',
    );

    await tester.enterText(yearInput, '${discoverEarliestAnimeYear - 1}');
    await tester.pump();
    expect(
      find.text(
        '请输入 $discoverEarliestAnimeYear—${DateTime.now().year + 1} 年',
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.ancestor(
              of: find.text('应用筛选'),
              matching: find.byType(FilledButton),
            ),
          )
          .onPressed,
      isNull,
    );

    await tester.enterText(yearInput, '$discoverEarliestAnimeYear');
    await tester.pump();
    await tester.ensureVisible(find.text('应用筛选'));
    await tester.tap(find.text('应用筛选'));
    await tester.pumpAndSettle();
    expect(api.lastBrowseYear, discoverEarliestAnimeYear);
  });

  testWidgets('discover browse year accepts next year for upcoming seasons', (
    tester,
  ) async {
    final api = _FakeBangumiApi();
    final nextYear = DateTime.now().year + 1;
    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(api),
        child: const MaterialApp(home: Scaffold(body: DiscoverPage())),
      ),
    );
    await tester.pump();

    await tester.tap(find.widgetWithText(OutlinedButton, '筛选'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('discover-browse-year-input')),
      '$nextYear',
    );
    await tester.pump();
    await tester.ensureVisible(find.text('应用筛选'));
    await tester.tap(find.text('应用筛选'));
    await tester.pumpAndSettle();
    expect(api.lastBrowseYear, nextYear);
  });

  testWidgets('subject search sends a manually entered start year', (
    tester,
  ) async {
    final api = _FakeBangumiApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(api),
        child: const MaterialApp(home: Scaffold(body: DiscoverPage())),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField).first, '科幻');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.widgetWithText(OutlinedButton, '筛选'));
    await tester.pumpAndSettle();

    final startYearInput = find.byKey(
      const ValueKey('discover-start-year-input'),
    );
    expect(startYearInput, findsOneWidget);
    await tester.enterText(startYearInput, '$discoverEarliestAnimeYear');
    await tester.pump();
    await tester.ensureVisible(find.text('应用筛选'));
    await tester.tap(find.text('应用筛选'));
    await tester.pumpAndSettle();

    expect(api.lastStartYear, discoverEarliestAnimeYear);
  });
}
