import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/theme/app_theme.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/widgets/profile_collection_summary.dart';
import 'package:mubangumi/widgets/readable_subject_title.dart';
import 'package:mubangumi/widgets/subject_widgets.dart';

const _screenshots = bool.fromEnvironment('READABILITY_SCREENSHOTS');
const _longName = '身为魔王的我娶了奴隶精灵为妻，该如何表白我的爱？特别篇：从今天开始的异世界生活与漫长旅途';
const _subject = Subject(
  id: 7,
  name: _longName,
  nameCn: '',
  imageUrl: '',
  summary: '',
  episodeCount: 12,
  score: 8.4,
  rank: 128,
  date: '2026-07-01',
);
const _collection = UserCollection(
  subjectId: 7,
  type: CollectionType.doing,
  rate: 8,
  episodeStatus: 6,
  updatedAt: null,
  subject: _subject,
);

void main() {
  for (final width in [320.0, 390.0, 1200.0]) {
    for (final scale in [1.0, 1.8]) {
      for (final dark in [false, true]) {
        testWidgets('readability at $width / $scale / dark=$dark', (
          tester,
        ) async {
          final boundary = GlobalKey();
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 1100);
          addTearDown(tester.view.reset);
          var theme = dark ? AppTheme.dark : AppTheme.light;
          if (_screenshots) {
            await tester.runAsync(() async {
              final bytes = await File(
                'C:/Windows/Fonts/msyh.ttc',
              ).readAsBytes();
              await (FontLoader(
                'ReadabilityFont',
              )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
              await (FontLoader('MaterialIcons')..addFont(
                    rootBundle.load('fonts/MaterialIcons-Regular.otf'),
                  ))
                  .load();
            });
            theme = theme.copyWith(
              textTheme: theme.textTheme.apply(fontFamily: 'ReadabilityFont'),
            );
          }
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: RepaintBoundary(key: boundary, child: child!),
              ),
              home: Scaffold(
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const ProfileCollectionSummary(
                        doing: 28,
                        done: 136,
                        total: 248,
                      ),
                      const SizedBox(height: 24),
                      SubjectGrid(
                        itemCount: 1,
                        itemBuilder: (_, _) => SubjectTile(
                          subject: _subject,
                          collection: _collection,
                          onTap: () {},
                          onEpisodeGrid: () {},
                          onNextEpisode: () {},
                        ),
                      ),
                      const SizedBox(height: 24),
                      SubjectPosterGrid(
                        itemCount: 2,
                        itemBuilder: (_, _) => SubjectPosterCard(
                          subject: _subject,
                          collection: _collection,
                          onTap: () {},
                          onEpisodeGrid: () {},
                          onNextEpisode: () {},
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text('248'), findsOneWidget);
          expect(
            tester.widget<Text>(find.text('248')).style!.fontSize,
            greaterThanOrEqualTo(48),
          );
          if (scale == 1 && width < 600) {
            expect(
              tester.getTopLeft(find.text('28')).dy,
              tester.getTopLeft(find.text('136')).dy,
            );
          }
          if (_screenshots && scale == 1 && width == 390) {
            await tester.runAsync(() async {
              final image =
                  await (boundary.currentContext!.findRenderObject()
                          as RenderRepaintBoundary)
                      .toImage();
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File(
                '.dart_tool/readability_${dark ? 'dark' : 'light'}.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
        });
      }
    }
  }

  testWidgets('a clipped name opens a scrollable selectable full title', (
    tester,
  ) async {
    var cardTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 160,
              child: GestureDetector(
                onTap: () => cardTaps++,
                child: const ReadableSubjectTitle(_longName, maxLines: 2),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text(_longName));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(SelectableText, _longName), findsOneWidget);
    expect(cardTaps, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('large collection counts keep every digit on a small screen', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 900);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
              child: const ProfileCollectionSummary(
                doing: 12345,
                done: 98765,
                total: 111110,
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('111110'), findsOneWidget);
  });
}
