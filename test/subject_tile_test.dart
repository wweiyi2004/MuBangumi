import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/widgets/subject_widgets.dart';

void main() {
  testWidgets('collected subject still shows public Bangumi score', (
    tester,
  ) async {
    const subject = Subject(
      id: 1,
      name: 'Test Anime',
      nameCn: '测试动画',
      imageUrl: '',
      summary: '',
      episodeCount: 12,
      score: 8.6,
      rank: 100,
      date: '2026-07-01',
    );
    const collection = UserCollection(
      subjectId: 1,
      type: CollectionType.doing,
      rate: 0,
      episodeStatus: 3,
      updatedAt: null,
      subject: subject,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 430,
            height: 128,
            child: SubjectTile(
              subject: subject,
              collection: collection,
              onTap: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('8.6'), findsOneWidget);
    expect(find.text('看到 3 / 12'), findsOneWidget);
  });
}
