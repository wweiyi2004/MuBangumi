import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/network/community_service.dart';
import 'package:mubangumi/models/bangumi_index.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/models/community_models.dart';
import 'package:mubangumi/navigation/app_destination.dart';
import 'package:mubangumi/screens/bangumi_index_pages.dart';
import 'package:mubangumi/state/service_providers.dart';
import 'package:mubangumi/state/session_controller.dart';
import 'support/pm_fixtures.dart';
import 'support/ux_visuals.dart';

void main() {
  testWidgets(
    'directory opens native subjects, notes and type filters at 320px',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final service = _Indexes();
      SubjectRoute? opened;
      final key = GlobalKey();
      final theme = await uxTheme(tester, dark: false);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            communityServiceProvider.overrideWithValue(service),
            sessionProvider.overrideWith((ref) => PmTestSession()),
          ],
          child: AppRouteScope(
            resolve: (route) {
              opened = route as SubjectRoute;
              return Scaffold(
                appBar: AppBar(title: Text(opened!.subject.displayName)),
              );
            },
            child: MaterialApp(
              theme: theme,
              home: RepaintBoundary(
                key: key,
                child: const BangumiIndexDetailPage(indexId: 7),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('合成番剧单'), findsOneWidget);
      expect(find.text('中文作品'), findsOneWidget);
      expect(find.textContaining('温柔的推荐语', findRichText: true), findsOneWidget);
      await captureUx(tester, key, 'bangumi-index-detail');
      await tester.tap(find.text('全部条目'));
      await tester.pumpAndSettle();
      expect(service.animeOnly, isFalse);
      await tester.tap(find.text('中文作品'));
      await tester.pumpAndSettle();
      expect(opened?.subject.id, 42);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'directory editor cannot create under another account after it opens',
    (tester) async {
      final service = _Indexes();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            communityServiceProvider.overrideWithValue(service),
            sessionProvider.overrideWith((ref) => PmTestSession()),
          ],
          child: const MaterialApp(home: BangumiIndexListPage()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('创建番剧单'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '原账号的输入');
      service.setCurrentUsername('bob');
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(service.creates, 0);
      expect(find.text('账号已变化，请关闭后重新编辑'), findsOneWidget);
    },
  );
}

class _Indexes extends CommunityService {
  _Indexes() {
    setAccessToken('synthetic');
    setCurrentUsername('alice');
  }
  int creates = 0;
  bool animeOnly = true;
  @override
  Future<BangumiIndex> loadIndex(int id, {bool refresh = false}) async =>
      const BangumiIndex(
        id: 7,
        ownerId: 2,
        title: '合成番剧单',
        description: '为喜欢的作品留下位置',
        total: 1,
        collects: 8,
      );
  @override
  Future<CommunityPageResult<BangumiIndex>> loadIndexes({
    BangumiIndexMode mode = BangumiIndexMode.hot,
    String? username,
    int offset = 0,
    int limit = 24,
    bool refresh = false,
  }) async => CommunityPageResult(data: [await loadIndex(7)], total: 1);
  @override
  Future<CommunityPageResult<BangumiIndexEntry>> loadIndexEntries(
    int id, {
    int offset = 0,
    int limit = 24,
    bool animeOnly = true,
    bool refresh = false,
  }) async {
    this.animeOnly = animeOnly;
    return CommunityPageResult(
      data: [
        BangumiIndexEntry(
          id: 11,
          subjectId: 42,
          order: 0,
          comment: '温柔的推荐语',
          subject: Subject.fromJson({
            'id': 42,
            'type': 2,
            'name_cn': '中文作品',
            'rating': {'score': 8.4},
          }),
        ),
      ],
      total: 1,
    );
  }

  @override
  Future<int> saveIndex({
    BangumiIndex? original,
    required String title,
    required String description,
    required bool isPrivate,
  }) async {
    creates++;
    return 8;
  }
}
