import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/models/community_models.dart';
import 'package:mubangumi/widgets/community_widgets.dart';

void main() {
  testWidgets('post reactions can be removed or changed from the picker', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    int? changedValue = -1;
    const post = CommunityPost(
      id: 'post_456',
      author: '爱丽丝',
      body: '测试正文',
      reactions: [
        CommunityReaction(
          value: 54,
          users: [CommunityUser(id: 7, username: 'alice', nickname: '爱丽丝')],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CommunityPostCard(
            post: post,
            currentUsername: 'alice',
            onReactionChanged: (value) async => changedValue = value,
          ),
        ),
      ),
    );

    expect(find.text('贴贴'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('post-reaction-54')));
    await tester.pump();
    expect(changedValue, isNull);

    await tester.tap(find.byKey(const ValueKey('post-reaction-picker')));
    await tester.pumpAndSettle();
    expect(find.text('选择贴贴'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('reaction-option-79')));
    await tester.pumpAndSettle();
    expect(changedValue, 79);
  });
}
