import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mubangumi/core/network/bangumi_api.dart';
import 'package:mubangumi/core/network/netaba_api.dart';
import 'package:mubangumi/core/sharing/image_export.dart';
import 'package:mubangumi/core/storage/snapshot_cache.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/models/netaba_models.dart';
import 'package:mubangumi/screens/discover_page.dart';
import 'package:mubangumi/screens/library_page.dart';
import 'package:mubangumi/screens/score_trends_page.dart';
import 'package:mubangumi/state/session_controller.dart';
import 'package:mubangumi/state/subject_view_controller.dart';
import 'package:mubangumi/widgets/episode_activity_heatmap.dart';
import 'package:mubangumi/widgets/image_share_sheet.dart';
import 'package:mubangumi/widgets/score_chart_controls.dart';
import 'package:mubangumi/widgets/score_comparison_chart.dart';
import 'package:mubangumi/widgets/subject_widgets.dart';
import 'support/pm_fixtures.dart';
import 'support/ux_visuals.dart';

final _points = [
  NetabaChartPoint(DateTime(2026, 1, 1), 7.9),
  NetabaChartPoint(DateTime(2026, 2, 1), 8.4),
  NetabaChartPoint(DateTime(2026, 3, 1), 8.1),
];
final _lines = [
  ScoreComparisonLine('旅途中的故事', _points, const Color(0xFF377CC8)),
];

void main() {
  FilePicker.platform = _ImagePicker();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test('library and discovery persist independent view preferences', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container
        .read(subjectViewProvider('library').notifier)
        .select(SubjectView.threeColumns);
    await container
        .read(subjectViewProvider('discover').notifier)
        .select(SubjectView.list);
    final reopened = ProviderContainer();
    addTearDown(reopened.dispose);
    reopened.read(subjectViewProvider('library'));
    reopened.read(subjectViewProvider('discover'));
    await Future<void>.delayed(Duration.zero);
    expect(
      reopened.read(subjectViewProvider('library')),
      SubjectView.threeColumns,
    );
    expect(reopened.read(subjectViewProvider('discover')), SubjectView.list);
  });

  for (final library in [true, false]) {
    testWidgets(
      '${library ? 'library' : 'discover'} switches views and returns to top',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final session = _Session();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sessionProvider.overrideWith((ref) => session),
              bangumiApiProvider.overrideWithValue(_BrowseApi()),
              snapshotCacheProvider.overrideWithValue(_Cache()),
            ],
            child: MaterialApp(
              theme: await uxTheme(tester, dark: false),
              home: Scaffold(
                body: library
                    ? const LibraryPage(rememberFilters: false)
                    : const DiscoverPage(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('切换视图'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.widgetWithText(PopupMenuItem<SubjectView>, '一行 3 个'),
        );
        await tester.pumpAndSettle();
        final grid = tester.widget<SliverGrid>(find.byType(SliverGrid));
        expect(
          (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
              .crossAxisCount,
          3,
        );
        expect(find.byType(SubjectPosterCard), findsWidgets);
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -700));
        await tester.pumpAndSettle();
        expect(find.byTooltip('回到顶部'), findsOneWidget);
        await tester.tap(find.byTooltip('回到顶部'));
        await tester.pumpAndSettle();
        final scroll = tester.widget<CustomScrollView>(
          find.byType(CustomScrollView),
        );
        expect(scroll.controller!.offset, closeTo(0, 1));
        expect(find.byTooltip('回到顶部'), findsNothing);
        await tester.tap(find.byTooltip('切换视图'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.widgetWithText(PopupMenuItem<SubjectView>, '列表视图'),
        );
        await tester.pumpAndSettle();
        expect(find.byType(SubjectTile), findsWidgets);
        expect(find.byType(SubjectPosterCard), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'axes reject invalid bounds, zoom, and export only visible samples',
    (tester) async {
      var axes = const ScoreChartAxes();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, update) => Column(
                children: [
                  ScoreChartControls(
                    axes: axes,
                    points: _points,
                    onChanged: (value) => update(() => axes = value),
                  ),
                  ScoreComparisonChart(lines: _lines, axes: axes),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('坐标轴与日期'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, '评分下限'), '9');
      await tester.enterText(find.widgetWithText(TextFormField, '评分上限'), '8');
      await tester.tap(find.text('应用'));
      await tester.pumpAndSettle();
      expect(find.textContaining('上限须大于下限'), findsWidgets);
      await tester.enterText(
        find.widgetWithText(TextFormField, '评分下限'),
        '8.00',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, '评分上限'),
        '8.50',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, '开始日期'),
        '2026/02/30',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, '结束日期'),
        '2026/03/01',
      );
      await tester.tap(find.text('应用'));
      await tester.pumpAndSettle();
      expect(find.textContaining('请填写有效的起止日期'), findsWidgets);
      await tester.enterText(
        find.widgetWithText(TextFormField, '开始日期'),
        '2026/03/02',
      );
      await tester.tap(find.text('应用'));
      await tester.pumpAndSettle();
      expect(find.textContaining('结束日期不得早于开始日期'), findsWidgets);
      await tester.enterText(
        find.widgetWithText(TextFormField, '开始日期'),
        '2026/02/01',
      );
      await tester.tap(find.text('应用'));
      await tester.pumpAndSettle();
      expect(axes.minimum, 8);
      expect(axes.maximum, 8.5);
      expect(axes.start, DateTime(2026, 2, 1));
      expect(axes.end, DateTime(2026, 3, 1));
      await tester.tap(find.byTooltip('放大评分尺度'));
      await tester.pump();
      expect(axes.maximum! - axes.minimum!, closeTo(.25, .001));
      final visible = ScoreChartAxes(
        start: DateTime(2026, 2, 1),
        end: DateTime(2026, 3, 1),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScoreChartKeyPoints(lines: _lines, axes: visible),
          ),
        ),
      );
      expect(find.textContaining('7.90'), findsNothing);
      expect(find.textContaining('最高 8.40'), findsOneWidget);
      expect(find.textContaining('最新 8.10'), findsOneWidget);
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'chart share preview fits a small phone, exports PNG, dark=$dark',
      (tester) async {
        tester.view.physicalSize = const Size(320, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final picker = _ImagePicker();
        final previous = FilePicker.platform;
        FilePicker.platform = picker;
        addTearDown(() => FilePicker.platform = previous);
        final key = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: await uxTheme(tester, dark: dark),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.8)),
              child: RepaintBoundary(key: key, child: child!),
            ),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showImageShareSheet(
                    context,
                    title: '评分历史对比',
                    filename: 'comparison.png',
                    subtitle: '数据来源：netaba.re',
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ScoreComparisonChart(
                          lines: _lines,
                          markKeyPoints: true,
                        ),
                        ScoreChartKeyPoints(lines: _lines),
                      ],
                    ),
                  ),
                  child: const Text('打开分享'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('打开分享'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await captureUx(
          tester,
          key,
          'score-share-phone-${dark ? 'dark' : 'light'}',
        );
        await tester.tap(find.text('保存图片'));
        await tester.runAsync(() async {
          for (var i = 0; i < 100 && picker.bytes == null; i++) {
            await tester.pump(const Duration(milliseconds: 20));
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        });
        expect(picker.filename, 'comparison.png');
        final image = img.decodePng(picker.bytes!);
        expect(image, isNotNull);
        expect(image!.width, 1920);
        expect(image.height, greaterThan(900));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('daily activity rotates clockwise, shares, and returns to home', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 32, bottom: 20);
    tester.view.viewPadding = const FakeViewPadding(top: 32, bottom: 20);
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    final today = DateTime(2026, 10, 16);
    final counts = {
      for (var i = 0; i < 360; i++)
        activityDayKey(today.subtract(Duration(days: i))): i % 13,
    };
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          episodeActivityProvider.overrideWith((ref) async => counts),
        ],
        child: MaterialApp(
          theme: await uxTheme(tester, dark: false),
          builder: (context, child) => RepaintBoundary(key: key, child: child!),
          home: Scaffold(
            body: Center(child: EpisodeActivityHeatmap(today: today)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('放大每日追番'));
    await tester.pumpAndSettle();
    expect(tester.widget<RotatedBox>(find.byType(RotatedBox)).quarterTurns, 1);
    expect(find.byTooltip('返回'), findsOneWidget);
    final rotatedMedia = MediaQuery.of(
      tester.element(find.byType(Scaffold).last),
    );
    expect(rotatedMedia.padding.left, 32);
    expect(rotatedMedia.padding.right, 20);
    await captureUx(tester, key, 'daily-activity-landscape');
    await tester.tap(find.byTooltip('分享每日追番'));
    await tester.pumpAndSettle();
    expect(find.byType(ImageShareSheet), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('关闭分享'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('放大每日追番'), findsOneWidget);
    expect(find.byType(RotatedBox), findsNothing);
  });

  testWidgets('all trend tabs and historical comparison expose image sharing', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          netabaApiProvider.overrideWithValue(_Trends()),
          sessionProvider.overrideWith((ref) => _Session()),
        ],
        child: MaterialApp(home: const ScoreTrendsPage()),
      ),
    );
    await tester.pumpAndSettle();
    for (final name in ['涨分', '跌分', '完结波动', '长期提升']) {
      await tester.tap(find.widgetWithText(Tab, name));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('分享趋势图'));
      await tester.pumpAndSettle();
      expect(find.byType(ImageShareSheet), findsOneWidget);
      expect(find.textContaining('最高 8.40'), findsOneWidget);
      await tester.tap(find.byTooltip('关闭分享'));
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(find.widgetWithText(Tab, '历史对比'));
    await tester.tap(find.widgetWithText(Tab, '历史对比'));
    await tester.pumpAndSettle();
    expect(find.text('数据来源：netaba.re'), findsOneWidget);
    expect(find.text('分享对比图'), findsOneWidget);
    expect(find.textContaining('这里筛选的是入榜收藏'), findsNothing);
    expect(find.textContaining('直接读取'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test(
    'gallery success, denied permission, and empty results are distinguished',
    () async {
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      MethodCall? saved;
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        ImageExport.channel,
        (call) async {
          saved = call;
          return 'content://media/external/images/media/123';
        },
      );
      addTearDown(
        () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
          ImageExport.channel,
          null,
        ),
      );
      final bytes = Uint8List.fromList([137, 80, 78, 71]);
      expect(await ImageExport.saveToGallery(bytes, 'test.png'), '已保存到系统相册');
      expect(saved!.method, 'savePng');
      expect(saved!.arguments['bytes'], bytes);
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        ImageExport.channel,
        (_) async => throw PlatformException(
          code: 'permission_denied',
          message: '未获得权限',
        ),
      );
      await expectLater(
        ImageExport.saveToGallery(bytes, 'test.png'),
        throwsA(isA<PlatformException>()),
      );
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        ImageExport.channel,
        (_) async => null,
      );
      await expectLater(
        ImageExport.saveToGallery(bytes, 'test.png'),
        throwsStateError,
      );
    },
  );
}

Subject _subject(int id) =>
    Subject.fromJson({'id': id, 'type': 2, 'name_cn': '收藏作品 $id', 'eps': 12});

class _Session extends PmTestSession {
  _Session() {
    state = state.copyWith(
      collections: [
        for (var id = 1; id <= 60; id++)
          UserCollection(
            subjectId: id,
            type: CollectionType.doing,
            rate: 8,
            episodeStatus: 3,
            updatedAt: null,
            subject: _subject(id),
          ),
      ],
    );
  }
}

class _BrowseApi extends BangumiApi {
  @override
  Future<List<Subject>> browseSubjects({
    required SubjectType type,
    int? year,
    int? month,
    String sort = 'rank',
    int limit = 24,
    int offset = 0,
  }) async => [
    for (var id = offset + 1; id <= offset + limit && id <= 60; id++)
      _subject(id),
  ];
}

class _Cache extends SnapshotCache {
  @override
  Future<List<Subject>?> readDiscoverBrowse(String key) async => null;
  @override
  Future<void> writeDiscoverBrowse(String key, List<Subject> values) async {}
}

class _ImagePicker extends FilePicker {
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

class _Trends extends NetabaApi {
  NetabaTrendingItem get item => NetabaTrendingItem(
    bgmId: 1,
    scoreDelta: .2,
    name: '旅途中的故事',
    nameCn: '',
    history: [
      for (final p in _points)
        NetabaHistoryPoint(recordedAt: p.at, score: p.value),
    ],
  );
  @override
  Future<NetabaTrending> getTrending() async =>
      NetabaTrending(up: [item], down: [item], done: [item]);
  @override
  Future<List<NetabaTrendingItem>> getScoreIncreases() async => [item];
  @override
  Future<NetabaSubjectHistory> getSubjectHistory(int id) async =>
      NetabaSubjectHistory(
        subject: const NetabaSubjectInfo(name: '', nameCn: ''),
        history: item.history,
      );
}
