import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/network/netaba_api.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/models/netaba_models.dart';
import 'package:mubangumi/screens/score_comparison_page.dart';
import 'package:mubangumi/state/session_controller.dart';
import 'package:mubangumi/widgets/image_share_sheet.dart';
import 'package:mubangumi/widgets/score_comparison_chart.dart';
import 'package:mubangumi/widgets/score_date_range_selector.dart';
import 'support/pm_fixtures.dart';
import 'support/ux_visuals.dart';

final _dates = [
  for (var day = 0; day <= 90; day += 10) DateTime(2026, 1, 1 + day),
];
final _subject = Subject.fromJson({'id': 1, 'name_cn': '测试作品'});

Future<void> _show(WidgetTester tester, _History api) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        netabaApiProvider.overrideWithValue(api),
        sessionProvider.overrideWith((ref) => PmTestSession()),
      ],
      child: MaterialApp(home: ScoreComparisonPage(initial: [_subject])),
    ),
  );
  await tester.pumpAndSettle();
}

RangeSlider _slider(WidgetTester tester) => tester.widget<RangeSlider>(
  find.byKey(const ValueKey('score-date-range-slider')),
);

Future<void> _drag(
  WidgetTester tester, {
  required bool start,
  required double distance,
}) async {
  final finder = find.byKey(const ValueKey('score-date-range-slider'));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  final rect = tester.getRect(finder);
  final slider = _slider(tester);
  final value = start ? slider.values.start : slider.values.end;
  final x = rect.left + 24 + (rect.width - 48) * value / slider.max;
  await tester.dragFrom(Offset(x, rect.center.dy), Offset(distance, 0));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('both date handles update the plot, auto scale and shared image', (
    tester,
  ) async {
    final api = _History();
    await _show(tester, api);
    expect(_slider(tester).values, const RangeValues(0, 90));
    final originalLabels = tester
        .widget<Semantics>(
          find.byWidgetPredicate(
            (widget) =>
                widget is Semantics &&
                (widget.properties.label?.startsWith('作品评分历史对比') ?? false),
          ),
        )
        .properties
        .value!;
    expect(originalLabels, contains('评分 2.00 至 9.00'));
    await tester.tap(find.text('坐标轴与日期'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, '评分下限'), '0');
    await tester.enterText(find.widgetWithText(TextFormField, '评分上限'), '10');
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ScoreComparisonChart>(find.byType(ScoreComparisonChart))
          .axes
          .minimum,
      0,
    );
    await _drag(tester, start: true, distance: 140);
    final firstWindow = _slider(tester).values;
    expect(firstWindow.start, greaterThan(0));
    expect(firstWindow.end, 90);
    await _drag(tester, start: false, distance: -100);
    final secondWindow = _slider(tester).values;
    expect(secondWindow.start, firstWindow.start);
    expect(secondWindow.end, lessThan(90));
    expect(secondWindow.end, greaterThan(secondWindow.start));
    final chart = tester.widget<ScoreComparisonChart>(
      find.byType(ScoreComparisonChart),
    );
    expect(chart.axes.start, DateTime(2026, 1, 1 + secondWindow.start.round()));
    expect(chart.axes.end, DateTime(2026, 1, 1 + secondWindow.end.round()));
    expect(chart.axes.minimum, isNull);
    expect(
      chart.lines.single.points,
      hasLength(10),
      reason:
          'The full source remains available when either handle is expanded again.',
    );
    final currentLabels = tester
        .widget<Semantics>(
          find.byWidgetPredicate(
            (widget) =>
                widget is Semantics &&
                (widget.properties.label?.startsWith('作品评分历史对比') ?? false),
          ),
        )
        .properties
        .value!;
    expect(currentLabels, contains('评分 7.00 至 9.00'));
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '全部时间'))
          .selected,
      false,
    );
    await tester.ensureVisible(find.text('分享对比图'));
    await tester.tap(find.text('分享对比图'));
    await tester.pumpAndSettle();
    expect(find.byType(ImageShareSheet), findsOneWidget);
    expect(find.textContaining('最低 3.00'), findsNothing);
    expect(find.textContaining('最低 8.'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭分享'));
    await tester.pumpAndSettle();
    await _drag(tester, start: true, distance: -1000);
    await _drag(tester, start: false, distance: 1000);
    expect(_slider(tester).values, const RangeValues(0, 90));
    expect(
      api.calls,
      1,
      reason: 'Moving date handles never triggers another network load.',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'date handles can expand a thirty-day preset back into earlier history',
    (tester) async {
      await _show(tester, _History());
      await tester.tap(find.text('近 30 天'));
      await tester.pumpAndSettle();
      expect(_slider(tester).max, 90);
      expect(_slider(tester).values, const RangeValues(60, 90));
      final initial = tester.widget<ScoreComparisonChart>(
        find.byType(ScoreComparisonChart),
      );
      expect(initial.axes.start, DateTime(2026, 3, 2));
      await _drag(tester, start: true, distance: -1000);
      expect(_slider(tester).values, const RangeValues(0, 90));
      final expanded = tester.widget<ScoreComparisonChart>(
        find.byType(ScoreComparisonChart),
      );
      expect(expanded.axes.start, DateTime(2026, 1, 1));
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '近 30 天'))
            .selected,
        false,
      );
    },
  );

  testWidgets(
    'a window between samples keeps the date handles available to recover',
    (tester) async {
      await _show(tester, _History());
      _slider(tester).onChanged!(const RangeValues(3, 5));
      await tester.pumpAndSettle();
      expect(find.text('当前日期范围内暂无历史评分，可拖动日期指针调整'), findsOneWidget);
      expect(_slider(tester).max, 90);
      expect(
        tester
            .widget<ActionChip>(find.widgetWithText(ActionChip, '分享对比图'))
            .onPressed,
        isNull,
      );
      await _drag(tester, start: false, distance: 1000);
      expect(find.text('当前日期范围内暂无历史评分，可拖动日期指针调整'), findsNothing);
      expect(
        find.byKey(const ValueKey('score-comparison-plot')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [320.0, 1000.0]) {
    testWidgets(
      'date range fits large text at $width and disables a single-day history',
      (tester) async {
        tester.view.physicalSize = Size(width, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final key = GlobalKey();
        var range = DateTimeRange(start: _dates.first, end: _dates.last);
        await tester.pumpWidget(
          MaterialApp(
            theme: await uxTheme(tester, dark: false),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.8)),
              child: child!,
            ),
            home: Scaffold(
              body: Center(
                child: RepaintBoundary(
                  key: key,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: StatefulBuilder(
                      builder: (context, update) => ScoreDateRangeSelector(
                        dates: _dates,
                        start: range.start,
                        end: range.end,
                        onChanged: (value) => update(() => range = value),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await captureUx(tester, key, 'score-date-handles-${width.toInt()}');
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ScoreDateRangeSelector(
                dates: [DateTime(2026, 1, 1)],
                onChanged: (_) => fail('single day must be disabled'),
              ),
            ),
          ),
        );
        expect(_slider(tester).onChanged, isNull);
        expect(find.text('仅有一天的历史记录'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class _History extends NetabaApi {
  int calls = 0;
  @override
  Future<NetabaSubjectHistory> getSubjectHistory(int id) async {
    calls++;
    return NetabaSubjectHistory(
      subject: const NetabaSubjectInfo(name: '测试作品', nameCn: ''),
      history: [
        for (var i = 0; i < _dates.length; i++)
          NetabaHistoryPoint(
            recordedAt: _dates[i],
            score: i == 0 ? 3 : 8 + i / 100,
          ),
      ],
    );
  }
}
