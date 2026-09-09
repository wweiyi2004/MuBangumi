import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/network/bangumi_api.dart';
import 'package:mubangumi/core/network/bangumi_support.dart';
import 'package:mubangumi/core/storage/snapshot_cache.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/models/subject_search_filter.dart';
import 'package:mubangumi/screens/discover_page.dart';
import 'package:mubangumi/state/session_controller.dart';
import 'package:mubangumi/widgets/subject_widgets.dart';

import 'support/ux_visuals.dart';

final _collections = StateProvider<List<UserCollection>>((_) => []);
final _boundary = GlobalKey();

Subject _subject(int id, {double score = 8.1, String date = '2010-01-01'}) =>
    Subject(
      id: id,
      name: '候选作品$id',
      nameCn: '',
      imageUrl: '',
      summary: '',
      episodeCount: 12,
      score: score,
      rank: id,
      date: date,
    );

UserCollection _owned(int id) => UserCollection(
  subjectId: id,
  type: CollectionType.values[id % CollectionType.values.length],
  rate: 0,
  episodeStatus: 0,
  updatedAt: null,
  subject: _subject(id),
);

class _Api extends BangumiApi {
  List<Subject> items = [];
  final calls =
      <
        ({
          String keyword,
          int offset,
          num rating,
          bool exclusive,
          int start,
          int end,
        })
      >[];
  bool failNextPage = false;
  Completer<List<Subject>>? pending;

  @override
  Future<List<Subject>> browseSubjects({
    required SubjectType type,
    int? year,
    int? month,
    String sort = 'rank',
    int limit = 24,
    int offset = 0,
  }) async => [];

  @override
  Future<List<Subject>> searchSubjects(
    String keyword, {
    int limit = 24,
    int offset = 0,
    String sort = 'match',
    num minimumRating = 0,
    bool ratingExclusive = false,
    int startYear = 0,
    int endYear = 0,
    List<String> tags = const [],
    List<String> metaTags = const [],
    SubjectType subjectType = SubjectType.anime,
  }) async {
    calls.add((
      keyword: keyword,
      offset: offset,
      rating: minimumRating,
      exclusive: ratingExclusive,
      start: startYear,
      end: endYear,
    ));
    if (offset > 0 && failNextPage) {
      failNextPage = false;
      throw Exception('offline');
    }
    final waiting = pending;
    pending = null;
    if (waiting != null) return waiting.future;
    // Intentionally return unfiltered server rows to exercise local boundaries.
    return items.skip(offset).take(limit).toList();
  }
}

class _Cache extends SnapshotCache {
  @override
  Future<List<Subject>?> readDiscoverBrowse(String key) async => null;
  @override
  Future<void> writeDiscoverBrowse(String key, List<Subject> values) async {}
}

Future<void> _show(
  WidgetTester tester,
  _Api api, {
  bool browse = false,
  double width = 800,
  double height = 900,
  double scale = 1,
  bool dark = false,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final theme = await uxTheme(tester, dark: dark);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        bangumiApiProvider.overrideWithValue(api),
        snapshotCacheProvider.overrideWithValue(_Cache()),
        discoverCollectionsProvider.overrideWith(
          (ref) => ref.watch(_collections),
        ),
      ],
      child: RepaintBoundary(
        key: _boundary,
        child: MaterialApp(
          theme: theme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(body: DiscoverPage(initialTag: browse ? '' : '恋爱')),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _open(WidgetTester tester) async {
  final button = find.byTooltip('筛选').evaluate().isNotEmpty
      ? find.byTooltip('筛选')
      : find.widgetWithText(OutlinedButton, '筛选');
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _fill(WidgetTester tester, String key, String value) async {
  final field = find.byKey(ValueKey(key));
  await tester.ensureVisible(field);
  await tester.enterText(field, value);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}

Future<void> _apply(WidgetTester tester) async {
  await tester.ensureVisible(find.text('应用筛选'));
  await tester.tap(find.text('应用筛选'));
  await tester.pumpAndSettle();
}

Set<int> _visible(WidgetTester tester) => tester
    .widgetList<SubjectPosterCard>(find.byType(SubjectPosterCard))
    .map((card) => card.subject.id)
    .toSet();

void main() {
  test('request contains decimal comparator and inclusive year endpoints', () {
    final filter = BangumiSupport.subjectSearchFilter(
      subjectType: SubjectType.anime,
      minimumRating: 8.1,
      ratingExclusive: true,
      startYear: 2007,
      endYear: 2011,
    );
    expect(filter['rating'], ['>8.1']);
    expect(filter['air_date'], ['>=2007-01-01', '<2012-01-01']);
    expect(
      BangumiSupport.subjectSearchFilter(
        subjectType: SubjectType.book,
        endYear: 2000,
      )['air_date'],
      ['<2001-01-01'],
    );
  });

  test(
    'numeric filters reject unknown values and preserve exact boundaries',
    () {
      const inclusive = SubjectSearchFilter(
        minimumRating: 8.1,
        startYear: 2007,
        endYear: 2011,
      );
      expect(inclusive.permits(_subject(1, date: '2007-01-01')), isTrue);
      expect(inclusive.permits(_subject(1, date: '2011-12-31')), isTrue);
      for (final row in [
        _subject(1, date: '2006-12-31'),
        _subject(1, date: '2012-01-01'),
        _subject(1, date: ''),
        _subject(1, score: 0),
        _subject(1, score: 8),
        _subject(1, score: double.nan),
      ]) {
        expect(inclusive.permits(row), isFalse);
      }
      const strict = SubjectSearchFilter(
        minimumRating: 8,
        ratingExclusive: true,
      );
      expect(strict.permits(_subject(1, score: 8)), isFalse);
      expect(strict.permits(_subject(1, score: 8.1)), isTrue);
      for (final filter in [
        const SubjectSearchFilter(startYear: 2011, endYear: 2007),
        const SubjectSearchFilter(minimumRating: 10.1),
        const SubjectSearchFilter(minimumRating: double.nan),
      ]) {
        expect(filter.validate, throwsArgumentError);
      }
    },
  );

  testWidgets(
    'empty keyword can search by range and decimal score, then clear',
    (tester) async {
      final api = _Api()
        ..items = [
          _subject(1, date: '2007-01-01'),
          _subject(2, score: 8),
          _subject(3, date: '2011-12-31'),
          _subject(4, date: '2012-01-01'),
        ];
      await _show(tester, api, browse: true);
      await _open(tester);
      await tester.tap(find.widgetWithText(ChoiceChip, '条件搜索'));
      await tester.pump();
      await _fill(tester, 'discover-minimum-rating-input', '8.1');
      await _fill(tester, 'discover-start-year-input', '2007');
      await _fill(tester, 'discover-end-year-input', '2011');
      await _apply(tester);
      expect(api.calls.last, (
        keyword: '',
        offset: 0,
        rating: 8.1,
        exclusive: false,
        start: 2007,
        end: 2011,
      ));
      expect(_visible(tester), {1, 3});
      expect(find.text('2007–2011 年（含）'), findsOneWidget);
      await tester.tap(find.text('清除筛选').first);
      await tester.pumpAndSettle();
      expect(find.text('动画季度榜'), findsOneWidget);
      expect(find.text('2007–2011 年（含）'), findsNothing);
    },
  );

  testWidgets('strict rating applies and invalid drafts cannot submit', (
    tester,
  ) async {
    final api = _Api()..items = [_subject(1, score: 8), _subject(2)];
    await _show(tester, api);
    await _open(tester);
    await _fill(tester, 'discover-minimum-rating-input', '8.0');
    final strictChip = find.widgetWithText(ChoiceChip, '大于 >');
    await tester.ensureVisible(strictChip);
    await tester.pumpAndSettle();
    await tester.tap(strictChip);
    await tester.pump();
    expect(tester.widget<ChoiceChip>(strictChip).selected, isTrue);
    await _fill(tester, 'discover-start-year-input', '2011');
    await _fill(tester, 'discover-end-year-input', '2007');
    expect(find.text('截止年份不能早于起始年份'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '应用筛选'))
          .onPressed,
      isNull,
    );
    await _fill(tester, 'discover-end-year-input', '2012');
    await _fill(tester, 'discover-start-year-input', '2007');
    await _fill(tester, 'discover-minimum-rating-input', '8.15');
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '应用筛选'))
          .onPressed,
      isNull,
    );
    await _fill(tester, 'discover-minimum-rating-input', '8.0');
    await _apply(tester);
    expect(api.calls.last.exclusive, isTrue);
    expect(_visible(tester), {2});
    expect(find.text('评分 > 8.0'), findsOneWidget);
  });

  testWidgets(
    'hidden full page keeps raw offset and supports failed-page retry',
    (tester) async {
      final api = _Api()
        ..items = [for (var id = 1; id <= 25; id++) _subject(id)];
      await _show(tester, api);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(DiscoverPage)),
      );
      container.read(_collections.notifier).state = [
        for (var id = 1; id <= 24; id++) _owned(id),
      ];
      await _open(tester);
      await tester.ensureVisible(
        find.byKey(const ValueKey('discover-hide-collected')),
      );
      await tester.tap(find.byKey(const ValueKey('discover-hide-collected')));
      await _apply(tester);
      expect(_visible(tester), isEmpty);
      expect(find.text('当前已加载条目均被筛除'), findsOneWidget);
      api.failNextPage = true;
      await tester.ensureVisible(find.text('加载更多'));
      await tester.tap(find.text('加载更多'));
      await tester.pumpAndSettle();
      expect(find.text('后续结果加载失败，请重试'), findsOneWidget);
      await tester.tap(find.text('重试加载'));
      await tester.pumpAndSettle();
      expect(api.calls.skip(api.calls.length - 2).map((call) => call.offset), [
        24,
        24,
      ]);
      expect(_visible(tester), {25});
      // Switching account / updating the current collection changes visibility
      // without discarding the raw search pages.
      container.read(_collections.notifier).state = [_owned(25)];
      await tester.pumpAndSettle();
      expect(_visible(tester), isNot(contains(25)));
      expect(_visible(tester), contains(1));
    },
  );

  testWidgets('an older search cannot replace newly applied conditions', (
    tester,
  ) async {
    final pending = Completer<List<Subject>>();
    final api = _Api()
      ..pending = pending
      ..items = [_subject(2, score: 9)];
    await _show(tester, api);
    // Open the sheet without waiting for the intentionally pending request.
    await _open(tester);
    await _fill(tester, 'discover-minimum-rating-input', '8.1');
    await _apply(tester);
    pending.complete([_subject(1, score: 9)]);
    await tester.pumpAndSettle();
    expect(_visible(tester), {2});
  });

  testWidgets(
    'dismissed draft and a switch of subject type do not leak filters',
    (tester) async {
      final api = _Api()..items = [_subject(1)];
      await _show(tester, api);
      await _open(tester);
      await _fill(tester, 'discover-end-year-input', '2000');
      Navigator.of(tester.element(find.byType(BottomSheet))).pop();
      await tester.pumpAndSettle();
      expect(api.calls.length, 1);
      expect(_visible(tester), {1});
      await _open(tester);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('discover-end-year-input')),
            )
            .controller!
            .text,
        '',
      );
      await _fill(tester, 'discover-end-year-input', '2000');
      await _apply(tester);
      await tester.tap(find.widgetWithText(ChoiceChip, '书籍'));
      await tester.pumpAndSettle();
      expect(find.text('2000 年及以前'), findsNothing);
      expect(find.text('书籍年度榜'), findsOneWidget);
    },
  );

  for (final width in [320.0, 390.0, 1200.0]) {
    for (final scale in [1.0, 1.8]) {
      for (final dark in [false, true]) {
        testWidgets('filter sheet works at $width / $scale / dark=$dark', (
          tester,
        ) async {
          final api = _Api()..items = [_subject(1)];
          await _show(
            tester,
            api,
            width: width,
            height: width == 320 ? 640 : 900,
            scale: scale,
            dark: dark,
          );
          await _open(tester);
          await _fill(tester, 'discover-minimum-rating-input', '8.1');
          final name = 'discover-filters-${width.toInt()}-$scale-$dark';
          await tester.ensureVisible(find.text('动画筛选'));
          await tester.pump(const Duration(milliseconds: 250));
          await captureUx(tester, _boundary, '$name-score');
          await _fill(tester, 'discover-start-year-input', '2007');
          await _fill(tester, 'discover-end-year-input', '2011');
          await tester.ensureVisible(find.text('播出年份区间'));
          await tester.pump(const Duration(milliseconds: 250));
          await captureUx(tester, _boundary, '$name-years');
          await _apply(tester);
          await captureUx(tester, _boundary, '$name-results');
          expect(api.calls.last.end, 2011);
          expect(_visible(tester), contains(1));
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
