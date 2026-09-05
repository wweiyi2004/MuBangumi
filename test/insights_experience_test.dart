import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/auth/bangumi_oauth.dart';
import 'package:mubangumi/core/insights/collection_insights.dart';
import 'package:mubangumi/core/insights/collection_year_review.dart';
import 'package:mubangumi/core/network/bangumi_api.dart';
import 'package:mubangumi/core/network/bangumi_endpoints.dart';
import 'package:mubangumi/core/network/netaba_api.dart';
import 'package:mubangumi/core/storage/token_store.dart';
import 'package:mubangumi/core/theme/app_theme.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/models/netaba_models.dart';
import 'package:mubangumi/screens/collection_stats_page.dart';
import 'package:mubangumi/screens/score_trends_page.dart';
import 'package:mubangumi/state/session_controller.dart';

const _screenshots = bool.fromEnvironment('INSIGHT_SCREENSHOTS');
final _boundary = GlobalKey();

void main() {
  test('review groups latest updates locally and excludes missing dates', () {
    final year = CollectionYearReview([
      _collection(1, rate: 10, month: 1),
      _collection(2, rate: 8, month: 3),
      _collection(3, rate: 0, month: 3),
      _collection(4, rate: 9, year: 2025),
      _collection(5, rate: 10, dated: false),
    ], 2026);
    expect(year.items.map((item) => item.subjectId), [1, 2, 3]);
    expect(year.statistics.averageRating, 9);
    expect(year.statistics.ratedTotal, 2);
    expect(year.activeMonths, 2);
    expect(year.peakMonths, [3]);
    expect(year.months, [1, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
    expect(year.forMonth(3).map((item) => item.subjectId), [2, 3]);
    expect(year.forMonth(2), isEmpty);
  });

  test('review handles empty years, tied months and duplicate user tags', () {
    final empty = CollectionYearReview([], 2026);
    expect(empty.peakMonths, isEmpty);
    expect(empty.activeMonths, 0);
    final review = CollectionYearReview([
      _collection(1, month: 1, tags: [' 治愈 ', '治愈', '']),
      _collection(2, month: 2, tags: ['治愈']),
    ], 2026);
    expect(review.peakMonths, [1, 2]);
    expect(review.statistics.tagCounts, {'治愈': 2});
  });

  test('year selector and review agree at local year boundaries', () {
    final source = _collection(1);
    final boundary = UserCollection.fromJson({
      ...source.toJson(),
      'updated_at': DateTime(2026, 1, 1).toUtc().toIso8601String(),
    });
    final stats = CollectionStatistics([boundary]);
    expect(stats.years, [2026]);
    expect(stats.forYear([boundary], 2026), hasLength(1));
    expect(CollectionYearReview([boundary], 2026).months.first, 1);
  });

  testWidgets('annual month selection filters memories and keeps annual totals', (
    tester,
  ) async {
    await _show(tester, _stats(), size: const Size(1100, 1100));
    expect(find.text('小暮 的收藏手账'), findsOneWidget);
    await tester.tap(find.text('年度回顾'));
    await tester.pumpAndSettle();
    expect(find.text('最高 9 分'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('3月 · 1 条更新'));
    await tester.tap(find.byTooltip('3月 · 1 条更新'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('3 月的收藏片段'));
    expect(find.text('作品 2'), findsOneWidget);
    expect(find.text('作品 1'), findsNothing);
    // March is unrated, but the annual highest rating stays visible in the tree.
    expect(find.text('最高 9 分'), findsOneWidget);
    await tester.tap(find.text('查看全年'));
    await tester.pumpAndSettle();
    expect(find.text('作品 1'), findsOneWidget);
  });

  testWidgets(
    'type changes recompute annual data and empty years remain usable',
    (tester) async {
      await _show(tester, _stats(), size: const Size(1100, 1100));
      await tester.tap(find.text('年度回顾'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, '书籍'));
      await tester.pumpAndSettle();
      expect(find.text('这一年，暂时还没有可回顾的记录。'), findsOneWidget);
      await tester.tap(find.byType(DropdownButton<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2025 年').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('1 条收藏更新'), findsOneWidget);
      expect(find.text('最高 8 分'), findsOneWidget);
    },
  );

  testWidgets('a slow or failed long-term feed does not block recent trends', (
    tester,
  ) async {
    final api = _Trends();
    await _show(tester, const ScoreTrendsPage(), api: api);
    api.trending.complete(NetabaTrending(up: [_trend(1)]));
    await tester.pump();
    await tester.pump();
    expect(find.text('作品 1'), findsOneWidget);
    api.reputation.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(find.text('作品 1'), findsOneWidget);
    await tester.tap(find.text('长期提升'));
    await tester.pumpAndSettle();
    expect(find.text('长期提升榜暂时加载失败'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets('personal trend filter keeps original rank and own rating', (
    tester,
  ) async {
    final api = _readyTrends();
    await _show(
      tester,
      const ScoreTrendsPage(),
      api: api,
      size: const Size(1100, 1100),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('我的收藏'));
    await tester.pumpAndSettle();
    expect(find.text('作品 1'), findsNothing);
    expect(find.text('作品 2'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('你评 8 分'), findsOneWidget);
    await tester.tap(find.text('跌分'));
    await tester.pumpAndSettle();
    expect(find.text('这份榜单里还没有你的收藏'), findsOneWidget);
    await tester.tap(find.text('全部作品'));
    await tester.pumpAndSettle();
    expect(find.text('-0.30'), findsOneWidget);
    await tester.tap(find.text('完结波动'));
    await tester.pumpAndSettle();
    expect(find.text('0.00'), findsOneWidget);
    expect(find.byIcon(Icons.trending_flat_rounded), findsOneWidget);
  });

  testWidgets('refresh keeps existing rows and retries failed data', (
    tester,
  ) async {
    final api = _readyTrends();
    await _show(tester, const ScoreTrendsPage(), api: api);
    await tester.pumpAndSettle();
    api.trending = Completer<NetabaTrending>();
    api.reputation = Completer<List<NetabaTrendingItem>>();
    await tester.tap(find.byTooltip('刷新榜单'));
    await tester.pump();
    expect(find.text('作品 1'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    api.trending.completeError(StateError('offline'));
    api.reputation.complete([]);
    await tester.pumpAndSettle();
    expect(find.text('刷新失败，已保留当前榜单'), findsOneWidget);
    api.trending = Completer<NetabaTrending>()
      ..complete(NetabaTrending(up: [_trend(4)]));
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('作品 4'), findsOneWidget);
    expect(find.text('作品 1'), findsNothing);
  });

  for (final width in [320.0, 1200.0]) {
    for (final scale in [1.0, 1.8]) {
      testWidgets('insights layout at width $width and scale $scale', (
        tester,
      ) async {
        final dark = scale > 1;
        final label = '${width.toInt()}_${scale}_$dark';
        await _show(
          tester,
          _stats(),
          size: Size(width, 1100),
          scale: scale,
          dark: dark,
        );
        await tester.pumpAndSettle();
        await _capture(tester, 'overview_$label');
        // Exercise all lazy sections, not only the first viewport.
        final list = find.byType(ListView);
        for (var i = 0; i < 6; i++) {
          await tester.drag(list, const Offset(0, -500));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        await tester.drag(list, const Offset(0, 5000));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('年度回顾'));
        await tester.tap(find.text('年度回顾'));
        await tester.pumpAndSettle();
        await _capture(tester, 'annual_$label');
        for (var i = 0; i < 5; i++) {
          await tester.drag(find.byType(ListView), const Offset(0, -500));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        await _show(
          tester,
          const ScoreTrendsPage(),
          api: _readyTrends(),
          size: Size(width, 1100),
          scale: scale,
          dark: dark,
        );
        await tester.pumpAndSettle();
        await _capture(tester, 'trends_$label');
        await tester.drag(find.byType(ListView).first, const Offset(0, -600));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}

Widget _stats() => CollectionStatsPage(
  username: 'tester',
  displayName: '小暮',
  collections: [
    _collection(1, month: 1, rate: 9, tags: ['治愈', '日常']),
    _collection(2, month: 3, rate: 0, tags: ['治愈']),
    _collection(3, year: 2025, type: SubjectType.book),
  ],
);

Future<void> _show(
  WidgetTester tester,
  Widget page, {
  _Trends? api,
  Size size = const Size(1100, 1100),
  double scale = 1,
  bool dark = false,
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  var theme = dark ? AppTheme.dark : AppTheme.light;
  if (_screenshots) {
    await tester.runAsync(() async {
      final bytes = await File('C:/Windows/Fonts/msyh.ttc').readAsBytes();
      await (FontLoader(
        'InsightTestFont',
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    });
    theme = theme.copyWith(
      textTheme: theme.textTheme.apply(fontFamily: 'InsightTestFont'),
      chipTheme: theme.chipTheme.copyWith(
        labelStyle: (theme.chipTheme.labelStyle ?? theme.textTheme.labelLarge!)
            .copyWith(fontFamily: 'InsightTestFont'),
        secondaryLabelStyle:
            (theme.chipTheme.secondaryLabelStyle ?? theme.textTheme.labelLarge!)
                .copyWith(fontFamily: 'InsightTestFont'),
      ),
    );
  }
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionProvider.overrideWith((ref) => _Session()),
        if (api != null) netabaApiProvider.overrideWithValue(api),
      ],
      child: MaterialApp(
        theme: theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: RepaintBoundary(key: _boundary, child: child!),
        ),
        home: page,
      ),
    ),
  );
  await tester.pump();
}

Future<void> _capture(WidgetTester tester, String name) async {
  if (!_screenshots) return;
  await tester.runAsync(() async {
    final boundary =
        _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(
      '.dart_tool/insights_$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

UserCollection _collection(
  int id, {
  int year = 2026,
  int month = 1,
  int rate = 8,
  bool dated = true,
  SubjectType type = SubjectType.anime,
  List<String> tags = const [],
}) => UserCollection(
  subjectId: id,
  type: CollectionType.done,
  rate: rate,
  episodeStatus: 12,
  updatedAt: dated ? DateTime(year, month, 12) : null,
  tags: tags,
  comment: '喜欢这部作品平静又温柔的表达。',
  subject: Subject(
    id: id,
    name: '作品 $id',
    nameCn: '',
    imageUrl: '',
    summary: '',
    episodeCount: 12,
    score: 8.2,
    rank: 42,
    date: '2020-01-01',
    type: type,
  ),
);

NetabaTrendingItem _trend(int id, {double delta = .25}) => NetabaTrendingItem(
  bgmId: id,
  scoreDelta: delta,
  name: '作品 $id',
  nameCn: '',
  history: [
    for (var day = 1; day <= 12; day++)
      NetabaHistoryPoint(
        recordedAt: DateTime(2026, 8, day),
        score: 8 + delta * day / 12,
        rank: 42,
      ),
  ],
);

_Trends _readyTrends() => _Trends()
  ..trending.complete(
    NetabaTrending(
      up: [_trend(1), _trend(2)],
      down: [_trend(3, delta: -.3)],
      done: [_trend(4, delta: 0)],
    ),
  )
  ..reputation.complete([_trend(5)]);

class _Trends extends NetabaApi {
  var trending = Completer<NetabaTrending>();
  var reputation = Completer<List<NetabaTrendingItem>>();
  @override
  Future<NetabaTrending> getTrending() => trending.future;
  @override
  Future<List<NetabaTrendingItem>> getScoreIncreases() => reputation.future;
}

class _Session extends SessionController {
  _Session() : super(BangumiApi(), BangumiOAuth(), _Tokens()) {
    state = SessionState(
      phase: SessionPhase.signedIn,
      collections: [_collection(2)],
    );
  }
}

class _Tokens extends TokenStore {
  @override
  Future<BangumiNetworkRoute> readNetworkRoute() =>
      Completer<BangumiNetworkRoute>().future;
  @override
  Future<String?> read() async => null;
  @override
  Future<String?> readRefreshToken() async => null;
  @override
  Future<DateTime?> readExpiresAt() async => null;
  @override
  Future<OAuthConfig?> readOAuthConfig() async => null;
}
