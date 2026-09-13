import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:mubangumi/core/network/community_service.dart';
import 'package:mubangumi/core/storage/browsing_store.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/models/community_models.dart';
import 'package:mubangumi/models/topic_reading_position.dart';
import 'package:mubangumi/screens/community_topic_screen.dart';
import 'package:mubangumi/state/session_controller.dart';
import 'package:mubangumi/widgets/community_widgets.dart';
import 'support/progress_fixtures.dart';
import 'support/ux_visuals.dart';

final boundary = GlobalKey();
const topic = CommunityTopic(
  id: 7,
  kind: CommunityTopicKind.group,
  title: '长话题',
  url: 'https://bgm.tv/group/topic/7',
  webUrl: 'https://bgm.tv/group/topic/7',
);

void main() {
  testWidgets(
    'reopening starts at the top without overwriting the saved floor; resume finds its ID',
    (tester) async {
      final env = _Env();
      env.store.values['account1/group:7'] = const TopicReadingPosition(
        postId: 'p80',
        index: 79,
      );
      await _show(tester, env);
      expect(env.store.writes, 0);
      expect(find.text('继续上次阅读'), findsOneWidget);
      await tester.tap(find.text('继续上次阅读'));
      await tester.pumpAndSettle();
      final cards = tester.widgetList<CommunityPostCard>(
        find.byType(CommunityPostCard),
      );
      expect(cards.any((card) => card.post.id == 'p80'), isTrue);
      await tester.drag(
        find.byType(ScrollablePositionedList),
        const Offset(0, -650),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        env.store.values['account1/group:7']!.index,
        greaterThanOrEqualTo(79),
      );
      expect(env.store.writes, greaterThan(0));
    },
  );

  testWidgets(
    'removed saved floor falls back nearby; filters do not overwrite it',
    (tester) async {
      final env = _Env();
      env.store.values['account1/group:7'] = const TopicReadingPosition(
        postId: 'deleted',
        index: 50,
      );
      await _show(tester, env);
      await tester.tap(find.text('只看楼主'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<CommunityPostCard>(find.byType(CommunityPostCard))
            .every((card) => card.post.author == '楼主'),
        isTrue,
      );
      await tester.tap(find.text('只看好友'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<CommunityPostCard>(find.byType(CommunityPostCard))
            .every((card) => card.post.author == '好友'),
        isTrue,
      );
      expect(env.store.writes, 0);
      await tester.tap(find.text('继续上次阅读'));
      await tester.pumpAndSettle();
      expect(find.text('原楼层已移除，已定位到附近内容'), findsOneWidget);
    },
  );

  testWidgets(
    'changing accounts cannot restore or save another accounts reading position',
    (tester) async {
      final env = _Env();
      env.store.values['account1/group:7'] = const TopicReadingPosition(
        postId: 'p80',
        index: 79,
      );
      await _show(tester, env);
      env.service.account = 'account2';
      env.session.switchUser(2);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.text('继续上次阅读'), findsNothing);
      expect(env.store.values['account1/group:7']!.postId, 'p80');
      expect(env.store.values['account2/group:7'], isNull);
    },
  );

  testWidgets('large phone text keeps filters and resume accessible', (
    tester,
  ) async {
    final env = _Env();
    env.store.values['account1/group:7'] = const TopicReadingPosition(
      postId: 'p80',
      index: 79,
    );
    await _show(tester, env, width: 320, scale: 1.8);
    await tester.tap(find.text('继续上次阅读'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await captureUx(tester, boundary, 'mobile24_topic_320_1.8');
  });
}

class _Env {
  final store = _ReadingStore();
  final service = _TopicService();
  final session = ProgressSession(ProgressApi(), ProgressCache());
}

Future<void> _show(
  WidgetTester tester,
  _Env env, {
  double width = 390,
  double scale = 1,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final theme = await uxTheme(tester, dark: false);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionProvider.overrideWith((ref) => env.session),
        topicReadingRepositoryProvider.overrideWithValue(env.store),
      ],
      child: MaterialApp(
        theme: theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: RepaintBoundary(key: boundary, child: child!),
        ),
        home: CommunityTopicScreen(topic: topic, service: env.service),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pumpAndSettle();
}

class _ReadingStore implements TopicReadingRepository {
  final values = <String, TopicReadingPosition>{};
  int writes = 0;
  @override
  Future<TopicReadingPosition?> readTopicPosition(
    String account,
    String topic,
  ) async => values['$account/$topic'];
  @override
  Future<void> saveTopicPosition(
    String account,
    String topic,
    TopicReadingPosition position,
  ) async {
    writes++;
    values['$account/$topic'] = position;
  }
}

class _TopicService extends CommunityService {
  _TopicService() : super.test();
  String account = 'account1';
  @override
  String? get currentUsername => account;
  @override
  bool get isAuthenticated => false;
  @override
  Future<List<BangumiUser>> loadAllFriends(
    String username, {
    bool refresh = false,
    int pageSize = 30,
  }) async => [
    const BangumiUser(id: 9, username: 'friend', nickname: '好友', avatarUrl: ''),
  ];
  @override
  Future<CommunityTopicDetail> loadTopic(
    CommunityTopic topic, {
    bool refresh = false,
  }) async => CommunityTopicDetail(
    title: '值得慢慢读的长话题',
    posts: [
      for (var i = 1; i <= 100; i++)
        CommunityPost(
          id: 'p$i',
          author: i % 5 == 0 ? '好友' : '楼主',
          isOriginal: i == 1,
          userUrl: 'https://bgm.tv/user/${i % 5 == 0 ? 'friend' : 'author'}',
          body: '第 $i 条讨论。${'这是一段用来验证阅读位置与大字体布局的文字。' * 5}',
          meta: '#$i',
        ),
    ],
  );
}
