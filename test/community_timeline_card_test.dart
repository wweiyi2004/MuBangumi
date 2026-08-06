import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/models/community_models.dart';
import 'package:mubangumi/widgets/community_widgets.dart';

void main() {
  const user = CommunityUser(id: 1, username: 'alice', nickname: '爱丽丝');

  testWidgets('shows the exact episode grid and opens the native subject', (
    tester,
  ) async {
    var opened = false;
    final item = CommunityTimelineItem(
      id: 10,
      user: user,
      description: '看过 碧蓝之海 第三季 EP.5',
      createdAt: DateTime(2026, 8, 6),
      progress: const CommunityTimelineProgress(
        subjectId: 569116,
        subjectName: 'ぐらんぶる Season 3',
        subjectNameCn: '碧蓝之海 第三季',
        score: 7.07,
        episode: CommunityTimelineEpisode(
          id: 1704892,
          subjectId: 569116,
          type: 0,
          sort: 5,
          nameCn: '电视采访',
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CommunityTimelineCard(
              item: item,
              onOpenSubject: () => opened = true,
            ),
          ),
        ),
      ),
    );

    expect(find.text('EP.5'), findsOneWidget);
    expect(find.text('EP.5 · 电视采访'), findsOneWidget);
    expect(find.text('评分 7.1'), findsOneWidget);
    await tester.tap(find.text('碧蓝之海 第三季'));
    expect(opened, isTrue);
  });

  testWidgets('shows complete main and nested timeline reply content', (
    tester,
  ) async {
    final nested = CommunityTimelineReply(
      id: 102,
      creatorId: 3,
      user: CommunityUser(id: 3, username: 'carol', nickname: '卡萝'),
      content: '这是楼中楼的完整内容，不能只显示回复数量。',
      rawContent: '这是楼中楼的完整内容，不能只显示回复数量。',
      createdAt: DateTime(2026, 8, 6, 12),
    );
    final reply = CommunityTimelineReply(
      id: 101,
      creatorId: 2,
      user: CommunityUser(id: 2, username: 'bob', nickname: '鲍勃'),
      content: '这是第一条回复的完整正文，哪怕很长也不应该被省略。',
      rawContent: '这是第一条回复的完整正文，哪怕很长也不应该被省略。',
      createdAt: DateTime(2026, 8, 6, 11),
      replies: [nested],
    );
    final item = CommunityTimelineItem(
      id: 11,
      user: user,
      description: '发表了吐槽',
      createdAt: DateTime(2026, 8, 6),
      replyCount: 2,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CommunityTimelineCard(
              item: item,
              repliesExpanded: true,
              replies: [reply],
            ),
          ),
        ),
      ),
    );

    expect(find.text('这是第一条回复的完整正文，哪怕很长也不应该被省略。'), findsOneWidget);
    expect(find.text('这是楼中楼的完整内容，不能只显示回复数量。'), findsOneWidget);
    expect(find.textContaining('#1 ·'), findsOneWidget);
    expect(find.textContaining('#1-1 ·'), findsOneWidget);
  });
}
