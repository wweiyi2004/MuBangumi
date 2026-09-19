import 'package:mubangumi/navigation/app_destination.dart';
import 'package:mubangumi/navigation/app_router.dart';
import 'package:mubangumi/widgets/continue_watching_tile.dart';
import 'support/memory_recommendation_feedback.dart';
import 'support/memory_home_pins.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/auth/bangumi_oauth.dart';
import 'package:mubangumi/core/network/bangumi_api.dart';
import 'package:mubangumi/core/network/bangumi_endpoints.dart';
import 'package:mubangumi/core/storage/browsing_store.dart';
import 'package:mubangumi/core/storage/snapshot_cache.dart';
import 'package:mubangumi/core/storage/token_store.dart';
import 'package:mubangumi/core/theme/app_theme.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/screens/discover_page.dart';
import 'package:mubangumi/screens/fan_recommend_page.dart';
import 'package:mubangumi/screens/home_page.dart';
import 'package:mubangumi/screens/library_page.dart';
import 'package:mubangumi/state/notify_controller.dart';
import 'package:mubangumi/state/session_controller.dart';
import 'package:mubangumi/state/local_data_state.dart';
import 'package:mubangumi/widgets/subject_widgets.dart';

void main() {
  testWidgets(
    'local import refreshes saved filters without replacing the page or login',
    (tester) async {
      final repo = _Repository()
        ..settings['alice'] = {'subject_type': 1, 'collection_type': 2};
      await _show(tester, const LibraryPage(), repo);
      expect(_visibleIds(tester), {3});
      final pageState = tester.state(find.byType(LibraryPage));
      final container = ProviderScope.containerOf(
        tester.element(find.byType(LibraryPage)),
      );
      final session = container.read(sessionProvider.notifier);
      repo.settings['alice'] = {'subject_type': null, 'collection_type': null};
      container.read(localBrowsingEpochProvider.notifier).state++;
      await tester.pumpAndSettle();
      expect(_visibleIds(tester), {1, 2, 3, 4});
      expect(
        identical(tester.state(find.byType(LibraryPage)), pageState),
        true,
      );
      expect(
        identical(container.read(sessionProvider.notifier), session),
        true,
      );
    },
  );
  testWidgets(
    'home view-all reaches entries beyond the preview and ignores saved filters',
    (tester) async {
      final repo = _Repository()
        ..settings['alice'] = {'subject_type': 1, 'collection_type': 2};
      final session = _Session()
        ..setCollections([
          for (var id = 1; id <= 20; id++)
            _collection(
              id,
              id.isEven ? SubjectType.book : SubjectType.anime,
              CollectionType.doing,
            ),
          _collection(21, SubjectType.anime, CollectionType.done),
        ]);
      await _show(
        tester,
        HomePage(onDiscover: () {}, onSchedule: () {}),
        repo,
        session: session,
      );
      expect(find.byType(ContinueWatchingTile), findsNWidgets(18));
      await tester.tap(find.text('查看全部（20）'));
      await tester.pumpAndSettle();
      expect(find.text('找到 20 部'), findsOneWidget);
      expect(_selected(tester, '全部类型'), isTrue);
      expect(_selected(tester, '进行中'), isTrue);
      expect(repo.libraryReads, 0);
      final scroll = find
          .descendant(
            of: find.byType(LibraryPage),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.text('作品20'),
        400,
        scrollable: scroll,
      );
      expect(find.text('作品20'), findsOneWidget);
    },
  );

  testWidgets(
    'collection filters restore after reopening and save explicit all values',
    (tester) async {
      final repo = _Repository()
        ..settings['alice'] = {
          'subject_type': 1,
          'collection_type': 2,
          'sort': 'title',
          'progress': 'all',
          'minimum_rating': 6,
        };
      await _show(tester, const LibraryPage(), repo);
      expect(_visibleIds(tester), {3});
      expect(find.text('按标题'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, '全部类型'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, '全部状态'));
      await tester.pumpAndSettle();
      expect(repo.settings['alice']!['subject_type'], isNull);
      expect(repo.settings['alice']!['collection_type'], isNull);
      await _show(tester, const LibraryPage(), repo);
      expect(_selected(tester, '全部类型'), isTrue);
      expect(_selected(tester, '全部状态'), isTrue);
      expect(_visibleIds(tester), {1, 2, 3, 4});
    },
  );

  testWidgets(
    'late preferences cannot overwrite a filter the user just selected',
    (tester) async {
      final gate = Completer<Map<String, dynamic>?>();
      final repo = _Repository()..pendingPreferences = gate.future;
      await _show(tester, const LibraryPage(), repo);
      await tester.tap(find.widgetWithText(ChoiceChip, '全部类型'));
      gate.complete({'subject_type': 1, 'collection_type': 2});
      await tester.pumpAndSettle();
      expect(_selected(tester, '全部类型'), isTrue);
      expect(_selected(tester, '进行中'), isTrue);
      expect(_visibleIds(tester), {1, 4});
    },
  );

  testWidgets(
    'account switch restores that account rather than a late old preference',
    (tester) async {
      final gate = Completer<Map<String, dynamic>?>();
      final repo = _Repository()..pendingPreferences = gate.future;
      final session = _Session();
      await _show(tester, const LibraryPage(), repo, session: session);
      repo.pendingPreferences = null;
      repo.settings['bob'] = {'subject_type': 2, 'collection_type': 2};
      session.switchAccount('bob');
      await tester.pumpAndSettle();
      gate.complete({'subject_type': 1, 'collection_type': 2});
      await tester.pumpAndSettle();
      expect(_visibleIds(tester), {2});
    },
  );

  testWidgets('malformed optional preferences fall back to usable filters', (
    tester,
  ) async {
    final repo = _Repository()
      ..settings['alice'] = {
        'subject_type': 'invalid',
        'collection_type': 999,
        'sort': 'unknown',
        'progress': null,
        'minimum_rating': 6.0,
      };
    await _show(tester, const LibraryPage(), repo);
    expect(_visibleIds(tester), {1});
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'recent search restores its target and only confirmed typing is remembered',
    (tester) async {
      final repo = _Repository()
        ..history['alice'] = [
          const RecentSearch(keyword: '银河', subjectType: SubjectType.book),
        ];
      final api = _Api();
      await _show(tester, const DiscoverPage(), repo, api: api);
      await tester.tap(find.text('书籍 · 银河'));
      await tester.pumpAndSettle();
      expect(api.lastKeyword, '银河');
      expect(api.lastType, SubjectType.book);
      await tester.enterText(find.byType(TextField).first, '半截');
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        repo.history['alice']!.any((item) => item.keyword == '半截'),
        isFalse,
      );
      await tester.enterText(find.byType(TextField).first, '完整查询');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(repo.history['alice']!.first.keyword, '完整查询');
      await tester.tap(find.byTooltip('清空搜索'));
      await tester.pumpAndSettle();
      expect(find.text('书籍 · 完整查询'), findsOneWidget);
      repo.failClear = true;
      await tester.tap(find.text('清空历史'));
      await tester.pumpAndSettle();
      expect(find.text('未能清空搜索历史，请重试'), findsOneWidget);
      expect(find.text('书籍 · 完整查询'), findsOneWidget);
      repo.failClear = false;
      await tester.tap(find.text('清空历史'));
      await tester.pumpAndSettle();
      expect(find.text('最近搜索'), findsNothing);
    },
  );

  testWidgets('recent history follows the current account', (tester) async {
    final repo = _Repository()
      ..history['alice'] = [const RecentSearch(keyword: 'alice query')]
      ..history['bob'] = [const RecentSearch(keyword: 'bob query')];
    final session = _Session();
    await _show(tester, const DiscoverPage(), repo, session: session);
    expect(find.text('动画 · alice query'), findsOneWidget);
    session.switchAccount('bob');
    await tester.pumpAndSettle();
    expect(find.text('动画 · alice query'), findsNothing);
    expect(find.text('动画 · bob query'), findsOneWidget);
  });

  testWidgets(
    'recommendation network failure offers retry instead of blaming filters',
    (tester) async {
      final api = _Api()..mode = 'failure';
      await _show(
        tester,
        const FanRecommendPage(),
        _Repository(),
        api: api,
        width: 320,
      );
      await _recommend(tester);
      expect(find.text('暂时无法获取推荐，请稍后重试'), findsOneWidget);
      expect(find.textContaining('放宽评分'), findsNothing);
      api.mode = 'success';
      await tester.ensureVisible(find.text('重试'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(find.text('候选动画'), findsOneWidget);
      expect(find.text('暂时无法获取推荐，请稍后重试'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('successful empty recommendation suggests adjusting filters', (
    tester,
  ) async {
    await _show(tester, const FanRecommendPage(), _Repository());
    await _recommend(tester);
    expect(find.textContaining('放宽评分'), findsOneWidget);
    expect(find.text('重试'), findsNothing);
  });

  testWidgets('partial recommendations remain usable with a retry notice', (
    tester,
  ) async {
    await _show(
      tester,
      const FanRecommendPage(),
      _Repository(),
      api: _Api()..mode = 'partial',
    );
    await _recommend(tester);
    expect(find.text('候选动画'), findsOneWidget);
    expect(find.text('部分内容未能加载，当前推荐可能不完整'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets(
    'a failed refresh retains the previously loaded recommendations',
    (tester) async {
      final api = _Api()..mode = 'success';
      await _show(tester, const FanRecommendPage(), _Repository(), api: api);
      await _recommend(tester);
      api.mode = 'failure';
      await _recommend(tester);
      expect(find.text('候选动画'), findsOneWidget);
      expect(find.text('暂时无法获取推荐，已保留上次结果，请重试'), findsOneWidget);
    },
  );
}

bool _selected(WidgetTester tester, String label) =>
    tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label)).selected;
Set<int> _visibleIds(WidgetTester tester) => tester
    .widgetList<SubjectTile>(find.byType(SubjectTile))
    .map((tile) => tile.subject.id)
    .toSet();
Future<void> _recommend(WidgetTester tester) async {
  await tester.ensureVisible(find.text('开始推荐'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('开始推荐'));
  await tester.pumpAndSettle();
}

Future<void> _show(
  WidgetTester tester,
  Widget page,
  _Repository repo, {
  _Api? api,
  _Session? session,
  double width = 390,
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  tester.view.physicalSize = Size(width, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        homePinsRepositoryProvider.overrideWithValue(MemoryHomePins()),
        recommendationFeedbackRepositoryProvider.overrideWithValue(
          MemoryRecommendationFeedback(),
        ),
        sessionProvider.overrideWith((ref) => session ?? _Session()),
        bangumiApiProvider.overrideWithValue(api ?? _Api()),
        browsingRepositoryProvider.overrideWithValue(repo),
        snapshotCacheProvider.overrideWithValue(_NoCache()),
        discoverCollectionsProvider.overrideWithValue(const []),
        notifyBadgeProvider.overrideWith(
          (ref) => NotifyBadgeController(
            isAuthenticated: () => false,
            initiallyForeground: false,
          ),
        ),
      ],
      child: AppRouteScope(
        resolve: AppRouter.resolve,
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: page),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _Repository implements BrowsingRepository {
  final settings = <String, Map<String, dynamic>>{};
  final history = <String, List<RecentSearch>>{};
  Future<Map<String, dynamic>?>? pendingPreferences;
  int libraryReads = 0;
  bool failClear = false;
  @override
  Future<Map<String, dynamic>?> readLibrary(String account) {
    libraryReads++;
    return pendingPreferences ?? Future.value(settings[account]);
  }

  @override
  Future<void> saveLibrary(String account, Map<String, dynamic> data) async {
    settings[account] = Map.of(data);
  }

  @override
  Future<List<RecentSearch>> readSearches(String account) async =>
      history[account] ?? const [];
  @override
  Future<void> rememberSearch(String account, RecentSearch search) async {
    history[account] = [
      search,
      ...?history[account]?.where((item) => item.key != search.key),
    ].take(12).toList();
  }

  @override
  Future<void> clearSearches(String account) async {
    if (failClear) throw StateError('disk unavailable');
    history[account] = [];
  }
}

class _Session extends SessionController {
  _Session() : super(BangumiApi(), BangumiOAuth(), _TokenStore()) {
    state = SessionState(
      phase: SessionPhase.signedIn,
      user: const BangumiUser(
        id: 1,
        username: 'alice',
        nickname: 'Alice',
        avatarUrl: '',
      ),
      collections: [
        _collection(1, SubjectType.anime, CollectionType.doing),
        _collection(2, SubjectType.anime, CollectionType.done),
        _collection(3, SubjectType.book, CollectionType.done),
        _collection(4, SubjectType.book, CollectionType.doing),
      ],
    );
  }
  void setCollections(List<UserCollection> items) =>
      state = state.copyWith(collections: items);
  void switchAccount(String name) => state = state.copyWith(
    user: BangumiUser(id: 2, username: name, nickname: name, avatarUrl: ''),
  );
}

UserCollection _collection(int id, SubjectType type, CollectionType status) =>
    UserCollection(
      subjectId: id,
      type: status,
      rate: 8,
      episodeStatus: 0,
      updatedAt: null,
      subject: Subject(
        id: id,
        type: type,
        name: '作品$id',
        nameCn: '',
        imageUrl: '',
        summary: '',
        episodeCount: 12,
        score: 8,
        rank: 100,
        date: '',
        tags: const ['科幻'],
      ),
    );
const _candidate = Subject(
  id: 99,
  name: '候选动画',
  nameCn: '',
  imageUrl: '',
  summary: '',
  episodeCount: 12,
  score: 8.5,
  rank: 100,
  date: '2026-01-01',
  tags: ['科幻'],
);

class _Api extends BangumiApi {
  String mode = 'empty';
  int searches = 0;
  String? lastKeyword;
  SubjectType? lastType;
  @override
  Future<List<Subject>> browseSubjects({
    required SubjectType type,
    int? year,
    int? month,
    String sort = 'rank',
    int limit = 24,
    int offset = 0,
  }) async {
    if (mode == 'failure' || mode == 'partial') throw StateError('offline');
    return mode == 'success' ? [_candidate] : [];
  }

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
    lastKeyword = keyword;
    lastType = subjectType;
    searches++;
    if (mode == 'failure' || (mode == 'partial' && searches > 1)) {
      throw StateError('offline');
    }
    return mode == 'success' || mode == 'partial' ? [_candidate] : [];
  }
}

class _NoCache extends SnapshotCache {
  @override
  Future<List<Subject>?> readDiscoverBrowse(String key) async => null;
  @override
  Future<void> writeDiscoverBrowse(String key, List<Subject> subjects) async {}
}

class _TokenStore extends TokenStore {
  @override
  Future<String?> read() => Completer<String?>().future;
  @override
  Future<String?> readRefreshToken() async => null;
  @override
  Future<DateTime?> readExpiresAt() async => null;
  @override
  Future<OAuthConfig?> readOAuthConfig() async => null;
  @override
  Future<BangumiNetworkRoute> readNetworkRoute() async =>
      BangumiNetworkRoute.official;
}
