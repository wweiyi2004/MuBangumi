import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/features/anime_appreciation/room_comment_preview.dart';

Map<String, dynamic> round({bool open = true}) => {
  'id': 'r1',
  'publicComments': false,
  'commentsOpen': open,
  'comments': [
    {'id': 'a', 'text': '最早的一条', 'hidden': false},
    {'id': 'b', 'text': '被隐藏的别人', 'hidden': true},
    {'id': 'c', 'text': '我的被隐藏', 'hidden': true, 'mine': true},
    {'id': 'd', 'text': '最新的一条', 'hidden': false},
  ],
};

void main() {
  Future<void> show(
    WidgetTester tester,
    Map<String, dynamic> r, {
    double height = 600,
    VoidCallback? onOpen,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: height,
          child: FillBelow(
            top: const SizedBox(height: 300, child: Text('controls')),
            below: RoomCommentPreview(round: r, onOpenWall: onOpen ?? () {}),
          ),
        ),
      ),
    ),
  );

  testWidgets('newest visible comments come first, others hidden stay out', (
    tester,
  ) async {
    var opened = 0;
    await show(tester, round(), onOpen: () => opened++);
    expect(find.text('大家的短评'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('最新的一条')).dy,
      lessThan(tester.getTopLeft(find.text('最早的一条')).dy),
    );
    expect(find.text('被隐藏的别人'), findsNothing);
    expect(find.text('我的被隐藏'), findsOneWidget);
    expect(find.text('我 · 已被隐藏'), findsOneWidget);
    await tester.tap(find.text('查看全部'));
    expect(opened, 1);
  });

  testWidgets('before scoring the wall explains how to open it', (
    tester,
  ) async {
    await show(tester, round(open: false));
    expect(find.text('我的短评'), findsOneWidget);
    expect(find.text('评分后即可看到大家的短评'), findsOneWidget);
  });

  testWidgets('preview hides instead of squeezing the controls', (
    tester,
  ) async {
    await show(tester, round(), height: 360);
    expect(find.text('controls'), findsOneWidget);
    expect(find.byType(RoomCommentPreview).hitTestable(), findsNothing);
    expect(tester.getSize(find.byType(RoomCommentPreview)).height, 0);
    expect(tester.takeException(), isNull);
  });
}
