import 'package:banjian_server/banjian_server.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/features/anime_appreciation/room_danmaku.dart';

Json room(String current, List<Json> comments) => {
  'id': 'event',
  'current': current,
  'rounds': [
    {'id': current, 'comments': comments},
  ],
};
Json comment(String id, String text, {bool hidden = false}) => {
  'id': id,
  'text': text,
  'hidden': hidden,
};

void main() {
  Future<void> show(WidgetTester tester, Json event, {bool still = false}) =>
      tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(disableAnimations: still),
          child: MaterialApp(
            home: Scaffold(
              body: RoomDanmaku(event: event, child: const SizedBox.expand()),
            ),
          ),
        ),
      );

  testWidgets('only comments that arrive later fly once, never hidden ones', (
    tester,
  ) async {
    await show(tester, room('r1', [comment('a', '已经在墙上')]));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('已经在墙上'), findsNothing);

    await show(
      tester,
      room('r1', [
        comment('a', '已经在墙上'),
        comment('b', '新来的短评'),
        comment('c', '被隐藏的', hidden: true),
      ]),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('新来的短评'), findsOneWidget);
    expect(find.text('被隐藏的'), findsNothing);
    expect(find.text('已经在墙上'), findsNothing);

    await tester.pump(const Duration(seconds: 8));
    await tester.pump();
    expect(find.text('新来的短评'), findsNothing);
  });

  testWidgets('a new round records its existing wall without flying', (
    tester,
  ) async {
    await show(tester, room('r1', []));
    await show(tester, room('r2', [comment('x', '上一轮的旧评论')]));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('上一轮的旧评论'), findsNothing);
  });

  testWidgets('long comments are shortened and bursts are capped', (
    tester,
  ) async {
    await show(tester, room('r1', []));
    await show(
      tester,
      room('r1', [
        for (var i = 0; i < 10; i++) comment('$i', '第 $i 条'),
        comment('long', '长' * 60),
      ]),
    );
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('第 0 条'), findsNothing);
    expect(find.text('${'长' * 40}…'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.textContaining('条'), findsNothing);
  });

  testWidgets('reduced motion shows no danmaku', (tester) async {
    await show(tester, room('r1', []), still: true);
    await show(tester, room('r1', [comment('b', '静止模式')]), still: true);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('静止模式'), findsNothing);
  });
}
