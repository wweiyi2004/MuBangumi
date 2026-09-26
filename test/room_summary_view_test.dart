import 'package:banjian_server/banjian_server.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/features/anime_appreciation/room_summary_view.dart';

Json played(String title, double mean, int count, {int? mine}) => {
  'id': title,
  'subject': {'title': title, 'cover': ''},
  'myScore': mine,
  'stats': {'count': count, 'mean': mean},
};

void main() {
  Future<void> show(WidgetTester tester, Json event, {bool host = false}) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [RoomSummaryList(event: event, host: host)],
            ),
          ),
        ),
      );

  testWidgets('ended activity lists every title by mean with my score', (
    tester,
  ) async {
    await show(tester, {
      'ended': true,
      'rounds': [played('孤独摇滚！', 8.26, 4, mine: 9), played('葬送的芙莉莲', 9.5, 2)],
    });
    expect(find.text('按均分排名 · 共 2 部 · 6 次评分'), findsOneWidget);
    final first = tester.getTopLeft(find.text('葬送的芙莉莲'));
    final second = tester.getTopLeft(find.text('孤独摇滚！'));
    expect(first.dy, lessThan(second.dy));
    expect(find.text('9.5'), findsOneWidget);
    expect(find.text('8.3'), findsOneWidget);
    expect(find.text('4 人评分 · 我打了 9 分'), findsOneWidget);
    expect(find.text('2 人评分'), findsOneWidget);
  });

  testWidgets('before the end the page explains who will see it', (
    tester,
  ) async {
    await show(tester, {'ended': false, 'rounds': []});
    expect(find.text('还没有可以汇总的评分'), findsOneWidget);
    expect(find.textContaining('活动结束后公布全部'), findsOneWidget);
    await show(tester, {'ended': false, 'rounds': []}, host: true);
    expect(find.text('活动结束后，参与者会看到这份汇总'), findsOneWidget);
  });
}
