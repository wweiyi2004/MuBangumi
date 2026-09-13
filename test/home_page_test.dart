import 'package:mubangumi/core/storage/browsing_store.dart';
import 'support/memory_home_pins.dart';
import 'support/ux_visuals.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/auth/bangumi_oauth.dart';
import 'package:mubangumi/core/network/bangumi_api.dart';
import 'package:mubangumi/core/network/bangumi_endpoints.dart';
import 'package:mubangumi/core/storage/token_store.dart';
import 'package:mubangumi/core/storage/user_preference_store.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/screens/home_page.dart';
import 'package:mubangumi/state/session_controller.dart';
import 'package:mubangumi/state/user_preferences_controller.dart';

final _homeBoundary = GlobalKey();

void main() {
  for (final scale in [1.0, 1.8]) {
    testWidgets(
      'phone exposes all four shortcuts before ongoing collections at scale $scale',
      (tester) async {
        tester.view.physicalSize = const Size(320, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        var scheduleOpens = 0;
        var discoverOpens = 0;
        final controller = _StubSessionController();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              homePinsRepositoryProvider.overrideWithValue(MemoryHomePins()),
              sessionProvider.overrideWith((ref) => controller),
              userPreferencesProvider.overrideWith(
                (ref) => UserPreferencesController(_FakePrefRepository()),
              ),
            ],
            child: MaterialApp(
              theme: await uxTheme(tester, dark: false),
              builder: (context, child) => RepaintBoundary(
                key: _homeBoundary,
                child: MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
              ),
              home: Scaffold(
                body: HomePage(
                  onDiscover: () => discoverOpens++,
                  onSchedule: () => scheduleOpens++,
                ),
              ),
            ),
          ),
        );
        controller.setSessionState(
          const SessionState(
            phase: SessionPhase.signedIn,
            user: BangumiUser(
              id: 1,
              username: 'tester',
              nickname: '小沐',
              avatarUrl: '',
            ),
            isLoadingCollections: true,
            isRefreshing: true,
          ),
        );
        await tester.pump();
        expect(tester.getTopLeft(find.text('继续追')).dy, lessThan(300 * scale));
        expect(
          tester
              .getTopLeft(
                find.byKey(const ValueKey('home-collection-skeleton')),
              )
              .dy,
          greaterThan(
            tester
                .getBottomLeft(find.byKey(const Key('home-quick-actions')))
                .dy,
          ),
        );
        for (final title in ['新番表', '每日放送', '番会荐', '找新番']) {
          expect(find.text(title).hitTestable(), findsOneWidget);
        }
        await captureUx(tester, _homeBoundary, 'home_shortcuts_phone_$scale');
        await tester.tap(find.text('新番表'));
        await tester.tap(find.text('找新番'));
        expect(scheduleOpens, 1);
        expect(discoverOpens, 1);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.byTooltip('我的二维码'), findsNothing);
        await tester.tap(find.byTooltip('更多操作'));
        await tester.pumpAndSettle();
        expect(find.text('我的二维码'), findsOneWidget);
        expect(find.text('扫一扫'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'desktop keeps notify and sync pinned at the window top-right while '
    'content scrolls',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final controller = _StubSessionController();
      // Disposed by the ProviderScope container when the tree is torn down.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            homePinsRepositoryProvider.overrideWithValue(MemoryHomePins()),
            sessionProvider.overrideWith((ref) => controller),
            userPreferencesProvider.overrideWith(
              (ref) => UserPreferencesController(_FakePrefRepository()),
            ),
          ],
          child: MaterialApp(
            theme: await uxTheme(tester, dark: false),
            builder: (context, child) =>
                RepaintBoundary(key: _homeBoundary, child: child!),
            home: Scaffold(
              body: HomePage(onDiscover: () {}, onSchedule: () {}),
            ),
          ),
        ),
      );
      controller.setSessionState(
        SessionState(
          phase: SessionPhase.signedIn,
          user: const BangumiUser(
            id: 1,
            username: 'wweiyi',
            nickname: '维依',
            avatarUrl: '',
          ),
          collections: [
            for (var i = 1; i <= 12; i++)
              UserCollection(
                subjectId: i,
                type: CollectionType.doing,
                rate: 0,
                episodeStatus: 1,
                updatedAt: DateTime(2026, 8, 1),
                subject: Subject(
                  id: i,
                  name: '动画 $i',
                  nameCn: '动画 $i',
                  imageUrl: '',
                  summary: '',
                  episodeCount: 12,
                  score: 7,
                  rank: 100,
                  date: '2026-08-01',
                ),
              ),
          ],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await captureUx(tester, _homeBoundary, 'home_shortcuts_desktop');
      final notify = find.byTooltip('电波提醒');
      final sync = find.byTooltip('同步收藏');
      final myQr = find.byTooltip('我的二维码');
      final scan = find.byTooltip('扫一扫');
      expect(notify, findsOneWidget);
      expect(sync, findsOneWidget);
      expect(myQr, findsOneWidget);
      expect(scan, findsOneWidget);
      final actionsBefore = tester.getTopLeft(
        find.byKey(const Key('home-quick-actions')),
      );
      final notifyBefore = tester.getTopRight(notify);
      final syncBefore = tester.getTopRight(sync);
      final scanBefore = tester.getTopRight(scan);
      // The last button anchors to the window's top-right with page padding.
      expect(scanBefore.dx, greaterThan(1360));
      expect(scanBefore.dx, lessThan(1400));
      expect(scanBefore.dy, lessThan(120));

      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -600),
      );
      await tester.pump();

      // Still pinned at the same spot after the content scrolled.
      expect(
        tester.getTopLeft(find.byKey(const Key('home-quick-actions'))),
        actionsBefore,
      );
      expect(tester.getTopRight(notify), notifyBefore);
      expect(tester.getTopRight(sync), syncBefore);
      expect(tester.getTopRight(scan), scanBefore);
    },
  );

  testWidgets(
    'shows a poster skeleton instead of empty copy while collections sync',
    (tester) async {
      final controller = _StubSessionController();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            homePinsRepositoryProvider.overrideWithValue(MemoryHomePins()),
            sessionProvider.overrideWith((ref) => controller),
            userPreferencesProvider.overrideWith(
              (ref) => UserPreferencesController(_FakePrefRepository()),
            ),
          ],
          child: MaterialApp(
            theme: await uxTheme(tester, dark: false),
            builder: (context, child) =>
                RepaintBoundary(key: _homeBoundary, child: child!),
            home: Scaffold(
              body: HomePage(onDiscover: () {}, onSchedule: () {}),
            ),
          ),
        ),
      );
      controller.setSessionState(
        const SessionState(
          phase: SessionPhase.signedIn,
          user: BangumiUser(
            id: 1,
            username: 'wweiyi',
            nickname: '维依',
            avatarUrl: '',
          ),
          isLoadingCollections: true,
        ),
      );
      await tester.pump();

      expect(find.text('还没有进行中的收藏'), findsNothing);
      expect(
        find.byKey(const ValueKey('home-collection-skeleton')),
        findsOneWidget,
      );
    },
  );
}

class _StubSessionController extends SessionController {
  _StubSessionController()
    : super(BangumiApi(), BangumiOAuth(), _EmptyTokenStore());

  void setSessionState(SessionState value) => state = value;
}

class _EmptyTokenStore extends TokenStore {
  @override
  Future<String?> read() async => null;

  @override
  Future<String?> readRefreshToken() async => null;

  @override
  Future<DateTime?> readExpiresAt() async => null;

  @override
  Future<OAuthConfig?> readOAuthConfig() async => null;

  @override
  Future<BangumiNetworkRoute> readNetworkRoute() async =>
      BangumiNetworkRoute.official;

  @override
  Future<void> clear() async {}
}

class _FakePrefRepository extends UserPreferenceRepository {
  @override
  Future<List<LocalUserPreference>> loadAll() async => const [];

  @override
  Future<void> save(LocalUserPreference preference) async {}
}
