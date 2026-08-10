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

  @override
  Future<List<Subject>> browseSubjects({
    required SubjectType type,
    int? year,
    int? month,
    String sort = 'rank',
    int limit = 24,
    int offset = 0,
  }) async => offset == 0 ? subjects : const [];

  @override
  Future<List<Subject>> searchSubjects(
    String keyword, {
    int limit = 24,
    int offset = 0,
    String sort = 'match',
    int minimumRating = 0,
    int startYear = 0,
    List<String> tags = const [],
    SubjectType subjectType = SubjectType.anime,
  }) async => const [];
}

List<Override> _overrides([BangumiApi? api]) => [
  bangumiApiProvider.overrideWithValue(api ?? _FakeBangumiApi()),
  discoverCollectionsProvider.overrideWithValue(const <UserCollection>[]),
];

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
    await tester.pumpAndSettle();
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
    await tester.pumpAndSettle();

    final builtTiles = find.byType(SubjectTile).evaluate().length;
    expect(builtTiles, greaterThan(0));
    expect(builtTiles, lessThan(subjects.length));
    expect(find.text('条目 120'), findsNothing);
  });
}
