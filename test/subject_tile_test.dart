import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/widgets/subject_widgets.dart';

void main() {
  testWidgets('poster cover decodes at constrained physical pixel size', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetDevicePixelRatio);
    const subject = Subject(
      id: 99,
      name: 'cover',
      nameCn: '',
      imageUrl: 'https://example.test/cover.jpg',
      summary: '',
      episodeCount: 0,
      score: 0,
      rank: 0,
      date: '',
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox(
            width: 140,
            height: 200,
            child: SubjectCover(subject: subject),
          ),
        ),
      ),
    );
    final cover = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );
    expect(cover.memCacheWidth, 280);
    expect(cover.memCacheHeight, 400);
    await tester.pumpWidget(const SizedBox.shrink());
  });

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

  testWidgets('poster grid keeps quick progress actions on a phone width', (
    tester,
  ) async {
    const subject = Subject(
      id: 2,
      name: 'Poster Anime',
      nameCn: '海报动画',
      imageUrl: '',
      summary: '',
      episodeCount: 12,
      score: 8.2,
      rank: 200,
      date: '2026-07-01',
    );
    const collection = UserCollection(
      subjectId: 2,
      type: CollectionType.doing,
      rate: 0,
      episodeStatus: 4,
      updatedAt: null,
      subject: subject,
    );
    var nextCount = 0;

    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 332,
              child: SubjectPosterGrid(
                itemCount: 2,
                itemBuilder: (_, _) => SubjectPosterCard(
                  subject: subject,
                  collection: collection,
                  onTap: () {},
                  onNextEpisode: () => nextCount++,
                  onEpisodeGrid: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(SubjectPosterCard), findsNWidgets(2));
    expect(find.text('看到 4 / 12'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byIcon(Icons.add_rounded).first);
    expect(nextCount, 1);
  });
}
