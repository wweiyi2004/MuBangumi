import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mubangumi/core/network/bangumi_api.dart';
import 'package:mubangumi/core/network/bangumi_support.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/models/netaba_models.dart';
import 'package:mubangumi/screens/calendar_page.dart';
import 'package:mubangumi/state/session_controller.dart';
import 'package:mubangumi/widgets/daily_broadcast_poster.dart';
import 'package:mubangumi/widgets/image_share_sheet.dart';
import 'package:mubangumi/widgets/score_comparison_chart.dart';
import 'package:mubangumi/widgets/score_history_chart.dart';
import 'package:mubangumi/widgets/swipe_tab_stack.dart';
import 'support/ux_visuals.dart';

final _points = [
  NetabaChartPoint(DateTime(2026, 1, 1), 7.9),
  NetabaChartPoint(DateTime(2026, 2, 1), 8.4),
  NetabaChartPoint(DateTime(2026, 3, 1), 8.1),
];
NetabaSubjectHistory get _history => NetabaSubjectHistory(
  subject: const NetabaSubjectInfo(name: 'A long journey', nameCn: '旅途中的故事'),
  history: [
    for (final point in _points)
      NetabaHistoryPoint(recordedAt: point.at, score: point.value),
  ],
);

void main() {
  FilePicker.platform = _Picker();
  for (final compare in [false, true]) {
    testWidgets(
      '${compare ? 'comparison' : 'single history'} supports wheel, pinch and pan without navigating tabs',
      (tester) async {
        var selected = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, update) => SwipeTabStack(
                  index: selected,
                  onChanged: (index) => update(() => selected = index),
                  children: [
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: compare
                            ? ScoreComparisonChart(
                                lines: [
                                  ScoreComparisonLine(
                                    '旅途中的故事',
                                    _points,
                                    Colors.blue,
                                  ),
                                ],
                              )
                            : ScoreHistoryChart(
                                points: _points,
                                lineColor: Colors.blue,
                              ),
                      ),
                    ),
                    const Center(child: Text('另一个底栏页面')),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final plot = find.byType(CustomPaint).last;
        final center = tester.getCenter(plot);
        final firstDate = tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data ?? '')
            .firstWhere((t) => t.contains('2026'));
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: center,
            scrollDelta: const Offset(0, -180),
          ),
        );
        await tester.pump();
        expect(find.byTooltip('重置图表视图'), findsOneWidget);
        expect(find.text(firstDate), findsNothing);
        final beforePan = tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data ?? '')
            .where((t) => t.contains('2026'))
            .toList();
        final mouse = await tester.startGesture(
          center,
          kind: PointerDeviceKind.mouse,
        );
        await mouse.moveBy(const Offset(-20, 0));
        await tester.pump();
        await mouse.moveBy(const Offset(-70, 0));
        await mouse.up();
        await tester.pumpAndSettle();
        final afterPan = tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data ?? '')
            .where((t) => t.contains('2026'))
            .toList();
        expect(afterPan, isNot(equals(beforePan)));
        expect(selected, 0);
        await tester.tap(find.byTooltip('重置图表视图'));
        await tester.pump();
        expect(find.text(firstDate), findsOneWidget);
        final first = await tester.startGesture(
          center - const Offset(30, 0),
          pointer: 5,
        );
        final second = await tester.startGesture(
          center + const Offset(30, 0),
          pointer: 6,
        );
        await first.moveTo(center - const Offset(70, 0));
        await second.moveTo(center + const Offset(70, 0));
        await tester.pump();
        await first.moveTo(center - const Offset(110, 0));
        await second.moveTo(center + const Offset(110, 0));
        await tester.pump();
        await first.up();
        await second.up();
        await tester.pumpAndSettle();
        expect(find.byTooltip('重置图表视图'), findsOneWidget);
        expect(find.text(firstDate), findsNothing);
        await tester.drag(plot, const Offset(-60, 20));
        await tester.pumpAndSettle();
        expect(selected, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'bottom destinations animate for swipes and taps and preserve page state',
    (tester) async {
      var selected = 0;
      final changes = <int>[];
      final pageKeys = List.generate(5, (_) => GlobalKey<_CounterPageState>());
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, update) => Scaffold(
              body: SwipeTabStack(
                index: selected,
                onChanged: (index) {
                  changes.add(index);
                  update(() => selected = index);
                },
                children: [
                  for (var i = 0; i < 5; i++)
                    _CounterPage(key: pageKeys[i], index: i),
                ],
              ),
              bottomNavigationBar: NavigationBar(
                selectedIndex: selected,
                onDestinationSelected: (index) =>
                    update(() => selected = index),
                destinations: [
                  for (var i = 0; i < 5; i++)
                    NavigationDestination(
                      icon: const Icon(Icons.circle_outlined),
                      label: '底栏 $i',
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('计数 0'));
      await tester.pump();
      final retained = pageKeys.first.currentState;
      await tester.drag(
        find.byKey(const ValueKey('main-swipe-pages')),
        const Offset(-650, 0),
      );
      await tester.pumpAndSettle();
      expect(selected, 1);
      expect(changes, [1]);
      await tester.tap(find.text('底栏 4'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final controller = tester
          .widget<PageView>(find.byType(PageView))
          .controller!;
      expect(controller.page, inExclusiveRange(1, 4));
      await tester.pumpAndSettle();
      expect(selected, 4);
      expect(changes, [1]);
      await tester.tap(find.text('底栏 0'));
      await tester.pumpAndSettle();
      expect(pageKeys.first.currentState, same(retained));
      expect(find.text('计数 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'swipe previews a lazy destination before committing navigation',
    (tester) async {
      var selected = 0;
      var prepared = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, update) => SwipeTabStack(
                index: selected,
                onChanged: (index) => update(() => selected = index),
                onPreview: (index) {
                  if (index == 1 && !prepared) update(() => prepared = true);
                },
                children: [
                  const Center(child: Text('追番')),
                  prepared
                      ? const Center(child: Text('已准备收藏'))
                      : const SizedBox.shrink(),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(PageView)),
      );
      await gesture.moveBy(const Offset(-30, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(-90, 0));
      await tester.pump();
      expect(prepared, true);
      expect(selected, 0);
      await gesture.moveBy(const Offset(-500, 0));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(selected, 1);
      expect(find.text('已准备收藏'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'an off-ranking subject shares its history while the panel is collapsed',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScoreHistoryPanel(
              loading: false,
              error: null,
              history: _history,
              onRetry: () {},
              subjectId: 987,
              subjectTitle: '未上榜的作品',
              compact: true,
              initiallyExpanded: false,
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('分享此番评分走势'));
      await tester.pumpAndSettle();
      expect(find.byType(ImageShareSheet), findsOneWidget);
      expect(find.text('未上榜的作品 · 评分走势'), findsWidgets);
      expect(find.textContaining('最高 8.40'), findsOneWidget);
      expect(find.textContaining('最低 7.90'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'single-subject history remains readable on a small phone with large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.8)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: ScoreHistoryPanel(
                loading: false,
                error: null,
                history: _history,
                onRetry: () {},
                subjectId: 987,
                subjectTitle: '未上榜的作品',
                compact: true,
                initiallyExpanded: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('双指或滚轮缩放 · 拖动平移'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'daily broadcast shares only the selected day and exports a PNG',
    (tester) async {
      final picker = _Picker();
      FilePicker.platform = picker;
      final key = GlobalKey();
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [bangumiApiProvider.overrideWithValue(_CalendarApi())],
          child: MaterialApp(
            theme: await uxTheme(tester, dark: false),
            builder: (context, child) =>
                RepaintBoundary(key: key, child: child!),
            home: const CalendarPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('星期二 3'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('分享当天番剧'));
      await tester.pumpAndSettle();
      final poster = tester.widget<DailyBroadcastPoster>(
        find.byType(DailyBroadcastPoster),
      );
      expect(poster.subjects.map((s) => s.id), [21, 22, 23]);
      expect(find.text('星期二 · 每日放送'), findsWidgets);
      await captureUx(tester, key, 'daily-broadcast-share');
      await tester.tap(find.text('保存图片'));
      await tester.runAsync(() async {
        for (var i = 0; i < 100 && picker.bytes == null; i++) {
          await tester.pump(const Duration(milliseconds: 20));
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      expect(picker.filename, 'MuBangumi-broadcast-2.png');
      expect(img.decodePng(picker.bytes!)!.width, 1920);
      expect(tester.takeException(), isNull);
    },
  );
}

class _CounterPage extends StatefulWidget {
  const _CounterPage({super.key, required this.index});
  final int index;
  @override
  State<_CounterPage> createState() => _CounterPageState();
}

class _CounterPageState extends State<_CounterPage> {
  int count = 0;
  @override
  Widget build(BuildContext context) => Center(
    child: TextButton(
      onPressed: () => setState(() => count++),
      child: Text('计数 $count'),
    ),
  );
}

class _CalendarApi extends BangumiApi {
  @override
  Future<List<CalendarDay>> getCalendar() async => [
    for (var day = 1; day <= 2; day++)
      CalendarDay(
        weekday: day,
        weekdayLabel: day == 1 ? '星期一' : '星期二',
        subjects: [
          for (var id = day * 10 + 1; id <= day * 10 + 3; id++)
            Subject.fromJson({
              'id': id,
              'type': 2,
              'name_cn': '放送作品 $id',
              'rating': {'score': 8.1},
            }),
        ],
      ),
  ];
}

class _Picker extends FilePicker {
  Uint8List? bytes;
  String? filename;
  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    this.bytes = bytes;
    filename = fileName;
    return null;
  }
}
