import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/auth/bangumi_oauth.dart';
import 'package:mubangumi/core/network/bangumi_api.dart';
import 'package:mubangumi/core/network/bangumi_endpoints.dart';
import 'package:mubangumi/core/storage/token_store.dart';
import 'package:mubangumi/core/storage/user_preference_store.dart';
import 'package:mubangumi/core/theme/app_theme.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/screens/home_page.dart';
import 'package:mubangumi/state/session_controller.dart';
import 'package:mubangumi/state/user_preferences_controller.dart';

void main() {
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
            sessionProvider.overrideWith((ref) => controller),
            userPreferencesProvider.overrideWith(
              (ref) => UserPreferencesController(_FakePrefRepository()),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
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

      final notify = find.byTooltip('电波提醒');
      final sync = find.byTooltip('同步收藏');
      final myQr = find.byTooltip('我的二维码');
      final scan = find.byTooltip('扫一扫');
      expect(notify, findsOneWidget);
      expect(sync, findsOneWidget);
      expect(myQr, findsOneWidget);
      expect(scan, findsOneWidget);
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
            sessionProvider.overrideWith((ref) => controller),
            userPreferencesProvider.overrideWith(
              (ref) => UserPreferencesController(_FakePrefRepository()),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
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
