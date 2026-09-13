import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/network/bangumi_api.dart';
import 'package:mubangumi/core/theme/app_theme.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/widgets/friend_subject_collection_card.dart';
import 'support/ux_visuals.dart';

const _friend = BangumiUser(
  id: 1,
  username: 'friend-one',
  nickname: '小春',
  avatarUrl: '',
);
const _second = BangumiUser(
  id: 2,
  username: 'friend-two',
  nickname: '小夏',
  avatarUrl: '',
);
const _status = FriendSubjectStatus(
  user: _friend,
  type: CollectionType.done,
  rate: 9,
  comment: '喜欢细腻的人物刻画，结尾很有余韵。',
);

void main() {
  test(
    'friend comments travel with their own collection without extra reads',
    () async {
      final api = _FriendApi();
      var refreshes = 0;
      api.ensureFreshToken = () async {
        refreshes++;
      };
      final statuses = await api.getFriendsSubjectStatus(
        7,
        friends: [_friend, _second],
      );
      final first = statuses.singleWhere((s) => s.user.id == 1);
      final second = statuses.singleWhere((s) => s.user.id == 2);
      expect(first.comment, _status.comment);
      expect(first.type, CollectionType.done);
      expect(first.rate, 9);
      expect(second.comment, isEmpty);
      expect(second.type, CollectionType.wish);
      expect(api.reads, unorderedEquals(['friend-one', 'friend-two']));
      expect(refreshes, 1);
    },
  );

  testWidgets('one entry groups identity, status, rating and comment', (
    tester,
  ) async {
    var opened = 0;
    await _show(tester, _status, onOpen: () => opened++);
    expect(find.text('小春'), findsOneWidget);
    expect(find.text('看过'), findsOneWidget);
    expect(find.text('9 / 10 分'), findsOneWidget);
    expect(find.text(_status.comment), findsOneWidget);
    expect(find.text('展开评论'), findsNothing);
    await tester.tap(find.text('小春'));
    expect(opened, 1);
  });

  testWidgets('unrated friends without comments retain their collection', (
    tester,
  ) async {
    await _show(
      tester,
      const FriendSubjectStatus(
        user: _second,
        type: CollectionType.wish,
        comment: ' \n ',
      ),
    );
    expect(find.text('小夏'), findsOneWidget);
    expect(find.text('想看'), findsOneWidget);
    expect(find.text('暂未写评论'), findsOneWidget);
    expect(find.textContaining('/ 10'), findsNothing);
    expect(find.text('展开评论'), findsNothing);
  });

  testWidgets(
    'long comments expand separately from profile navigation at large text size',
    (tester) async {
      final comment = List.filled(8, '这是一段需要展开才能完整阅读的好友评论。').join('\n');
      var opened = 0;
      await _show(
        tester,
        FriendSubjectStatus(
          user: _friend,
          type: CollectionType.doing,
          comment: comment,
        ),
        width: 320,
        scale: 2,
        onOpen: () => opened++,
      );
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('展开评论'));
      await tester.tap(find.text('展开评论'));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.text(comment)).maxLines, isNull);
      expect(opened, 0);
      await tester.ensureVisible(find.text('收起评论'));
      await tester.tap(find.text('收起评论'));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.text(comment)).maxLines, 4);
      expect(tester.takeException(), isNull);
    },
  );

  if (uxScreenshots) {
    testWidgets('capture friend collection and comment preview', (
      tester,
    ) async {
      final theme = await uxTheme(tester, dark: false);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(
                key: boundary,
                child: Container(
                  width: 520,
                  color: theme.colorScheme.surface,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('好友收藏与评论', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 12),
                      FriendSubjectCollectionCard(
                        status: _status,
                        subjectType: SubjectType.anime,
                        onOpenUser: () {},
                      ),
                      const SizedBox(height: 10),
                      FriendSubjectCollectionCard(
                        status: const FriendSubjectStatus(
                          user: _second,
                          type: CollectionType.wish,
                        ),
                        subjectType: SubjectType.anime,
                        onOpenUser: () {},
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await captureUx(tester, boundary, 'friend-collection-preview');
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _show(
  WidgetTester tester,
  FriendSubjectStatus status, {
  double width = 520,
  double scale = 1,
  VoidCallback? onOpen,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light.copyWith(platform: TargetPlatform.windows),
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: SingleChildScrollView(
            child: Center(
              child: SizedBox(
                width: width,
                child: FriendSubjectCollectionCard(
                  status: status,
                  subjectType: SubjectType.anime,
                  onOpenUser: onOpen ?? () {},
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _FriendApi extends BangumiApi {
  final reads = <String>[];
  @override
  Future<UserCollection?> getUserSubjectCollection(
    String username,
    int subjectId, {
    bool checkToken = true,
  }) async {
    expect(subjectId, 7);
    expect(checkToken, isFalse);
    reads.add(username);
    return UserCollection.fromJson({
      'subject_id': subjectId,
      'type': username == _friend.username ? 2 : 1,
      'rate': username == _friend.username ? 9 : 0,
      if (username == _friend.username) 'comment': _status.comment,
    });
  }
}
