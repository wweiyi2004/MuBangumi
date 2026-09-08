import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/auth/bangumi_oauth.dart';
import 'package:mubangumi/core/network/bangumi_api.dart';
import 'package:mubangumi/core/network/bangumi_endpoints.dart';
import 'package:mubangumi/core/storage/bangumi_sync_store.dart';
import 'package:mubangumi/core/storage/token_store.dart';
import 'package:mubangumi/core/theme/app_theme.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/screens/home_page.dart';
import 'package:mubangumi/screens/library_page.dart';
import 'package:mubangumi/screens/profile_page.dart';
import 'package:mubangumi/state/notify_controller.dart';
import 'package:mubangumi/state/session_controller.dart';
import 'package:mubangumi/widgets/collection_sync_status.dart';
import 'package:mubangumi/widgets/profile_collection_summary.dart';
import 'package:mubangumi/widgets/subject_widgets.dart';
import 'package:mubangumi/widgets/sync_issues_sheet.dart';

const _screenshots = bool.fromEnvironment('SMALL_UX_SCREENSHOTS');
final _boundary = GlobalKey();

void main() {
  for (final target in [
    (label: '进行中', ids: {1, 2}, filter: '进行中'),
    (label: '已完成', ids: {3, 4}, filter: '已完成'),
    (label: '总收藏', ids: {1, 2, 3, 4, 5}, filter: '全部状态'),
  ]) {
    testWidgets(
      'profile ${target.label} opens matching collections across all types',
      (tester) async {
        final session = _Session();
        await _show(
          tester,
          session,
          const ProfilePage(),
          size: const Size(390, 1200),
        );
        if (target.label == '进行中') await _capture(tester, 'profile');
        final link = find.descendant(
          of: find.byType(ProfileCollectionSummary),
          matching: find.text(target.label),
        );
        await tester.ensureVisible(link);
        await tester.pumpAndSettle();
        await tester.tap(link);
        await tester.pumpAndSettle();
        expect(find.byType(LibraryPage), findsOneWidget);
        expect(
          tester
              .widgetList<SubjectTile>(find.byType(SubjectTile))
              .map((tile) => tile.subject.id)
              .toSet(),
          target.ids,
        );
        expect(
          tester
              .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '全部类型'))
              .selected,
          isTrue,
        );
        expect(
          tester
              .widget<ChoiceChip>(
                find.widgetWithText(ChoiceChip, target.filter),
              )
              .selected,
          isTrue,
        );
        expect(find.text('我的收藏'), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byType(ProfilePage), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final home in [true, false]) {
    testWidgets(
      'sync status is visible in ${home ? 'home' : 'library'} and disappears when done',
      (tester) async {
        final session = _Session()..counts(pending: 3);
        await _show(
          tester,
          session,
          home
              ? HomePage(onDiscover: () {}, onSchedule: () {})
              : const LibraryPage(),
        );
        expect(find.text('已保存在本机 · 3 项待同步'), findsOneWidget);
        if (home) await _capture(tester, 'home');
        session.counts();
        await tester.pump();
        expect(find.textContaining('项待同步'), findsNothing);
        expect(tester.getSize(find.byType(CollectionSyncStatus)).height, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'manual sync coalesces rapid taps and clears the status on completion',
    (tester) async {
      final gate = Completer<void>();
      final session = _Session()
        ..counts(pending: 2)
        ..syncGate = gate.future;
      await _show(tester, session, const CollectionSyncStatus());
      await tester.tap(find.text('立即同步'));
      await tester.tap(find.text('立即同步'));
      await tester.pump();
      expect(session.syncCalls, 1);
      expect(find.text('正在同步修改 · 2 项'), findsOneWidget);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.textContaining('同步修改'), findsNothing);
      expect(find.byType(TextButton), findsNothing);
    },
  );

  testWidgets('failed sync entries open their existing management sheet', (
    tester,
  ) async {
    final session = _Session()..counts(pending: 5, blocked: 2);
    await _show(tester, session, const CollectionSyncStatus());
    expect(find.text('已保存在本机 · 2 项同步失败 · 3 项待同步'), findsOneWidget);
    await tester.tap(find.text('查看问题'));
    await tester.pumpAndSettle();
    expect(find.byType(SyncIssuesSheet), findsOneWidget);
    expect(session.issueLoads, 1);
    expect(session.syncCalls, 0);
  });

  testWidgets('a sync failure preserves the pending status and permits retry', (
    tester,
  ) async {
    final session = _Session()
      ..counts(pending: 2)
      ..failSync = true;
    await _show(tester, session, const CollectionSyncStatus());
    await tester.tap(find.text('立即同步'));
    await tester.pumpAndSettle();
    expect(find.text('暂时无法同步，修改已保存在本机'), findsOneWidget);
    expect(find.text('已保存在本机 · 2 项待同步'), findsOneWidget);
    session.failSync = false;
    await tester.tap(find.text('立即同步'));
    await tester.pumpAndSettle();
    expect(session.syncCalls, 2);
    expect(find.textContaining('项待同步'), findsNothing);
  });

  for (final width in [320.0, 1200.0]) {
    for (final dark in [false, true]) {
      testWidgets(
        'interactive stats and sync states fit $width at large text, dark=$dark',
        (tester) async {
          final session = _Session()..counts(pending: 123, blocked: 2);
          await _show(
            tester,
            session,
            SingleChildScrollView(
              child: Column(
                children: [
                  ProfileCollectionSummary(
                    doing: 12345,
                    done: 98765,
                    total: 111110,
                    onDoingTap: () {},
                    onDoneTap: () {},
                    onTotalTap: () {},
                  ),
                  const CollectionSyncStatus(),
                ],
              ),
            ),
            size: Size(width, 1000),
            scale: 1.8,
            dark: dark,
          );
          expect(tester.takeException(), isNull);
          session.counts(pending: 3, syncing: true);
          await tester.pump();
          expect(find.text('正在同步修改 · 3 项'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

Future<void> _show(
  WidgetTester tester,
  _Session session,
  Widget page, {
  Size size = const Size(390, 1000),
  double scale = 1,
  bool dark = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  var theme = dark ? AppTheme.dark : AppTheme.light;
  if (_screenshots) {
    await tester.runAsync(() async {
      final bytes = await File('C:/Windows/Fonts/msyh.ttc').readAsBytes();
      await (FontLoader(
        'SmallUxFont',
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    });
    theme = theme.copyWith(
      textTheme: theme.textTheme.apply(fontFamily: 'SmallUxFont'),
    );
  }
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionProvider.overrideWith((ref) => session),
        notifyBadgeProvider.overrideWith(
          (ref) => NotifyBadgeController(
            isAuthenticated: () => false,
            initiallyForeground: false,
          ),
        ),
      ],
      child: MaterialApp(
        theme: theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: RepaintBoundary(key: _boundary, child: child!),
        ),
        home: Scaffold(
          body: page is ProfilePage || page is HomePage || page is LibraryPage
              ? page
              : Padding(padding: const EdgeInsets.all(12), child: page),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _capture(WidgetTester tester, String name) async {
  if (!_screenshots) return;
  await tester.runAsync(() async {
    final boundary =
        _boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(
      '.dart_tool/small_ux_$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

class _Session extends SessionController {
  _Session() : super(BangumiApi(), BangumiOAuth(), _TokenStore()) {
    state = SessionState(
      phase: SessionPhase.signedIn,
      user: const BangumiUser(
        id: 1,
        username: 'tester',
        nickname: '测试用户',
        avatarUrl: '',
      ),
      collections: [
        _collection(1, SubjectType.anime, CollectionType.doing),
        _collection(2, SubjectType.book, CollectionType.doing),
        _collection(3, SubjectType.anime, CollectionType.done),
        _collection(4, SubjectType.game, CollectionType.done),
        _collection(5, SubjectType.music, CollectionType.wish),
      ],
    );
  }
  int syncCalls = 0;
  int issueLoads = 0;
  bool failSync = false;
  Future<void>? syncGate;
  void counts({int pending = 0, int blocked = 0, bool syncing = false}) =>
      state = state.copyWith(
        pendingSyncCount: pending,
        blockedSyncCount: blocked,
        isSyncing: syncing,
      );
  @override
  Future<void> syncPendingChanges({bool retryBlocked = false}) async {
    syncCalls++;
    if (failSync) throw StateError('offline');
    await syncGate;
    counts();
  }

  @override
  Future<List<PendingBangumiMutation>> blockedSyncMutations() async {
    issueLoads++;
    return const [];
  }
}

UserCollection _collection(int id, SubjectType type, CollectionType status) =>
    UserCollection(
      subjectId: id,
      type: status,
      rate: 0,
      episodeStatus: 0,
      updatedAt: null,
      subject: Subject(
        id: id,
        name: '作品$id',
        nameCn: '',
        imageUrl: '',
        summary: '',
        type: type,
        episodeCount: type.hasEpisodes ? 12 : 0,
        score: 8,
        rank: 100,
        date: '',
      ),
    );

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
