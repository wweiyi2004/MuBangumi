import 'package:mubangumi/navigation/app_destination.dart';
import 'package:mubangumi/navigation/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/widgets/continue_watching_tile.dart';
import 'support/ux_visuals.dart';

void main() {
  for (final scale in [1.0, 1.8]) {
    testWidgets('compact progress actions work at 320px and scale $scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final boundary = GlobalKey();
      var opens = 0, next = 0, episodes = 0, pins = 0;
      await tester.pumpWidget(
        AppRouteScope(
          resolve: AppRouter.resolve,
          child: MaterialApp(
            theme: await uxTheme(tester, dark: false),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: RepaintBoundary(key: boundary, child: child!),
            ),
            home: Scaffold(
              body: SafeArea(
                child: ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    const Text('继续追'),
                    ContinueWatchingTile(
                      collection: _collection,
                      onOpen: () => opens++,
                      onNext: () => next++,
                      onEpisodes: () => episodes++,
                      onPin: () => pins++,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('已记录 3 / 12 集'), findsOneWidget);
      await tester.tap(find.text('看完下一集'));
      await tester.tap(find.byTooltip('选择集数'));
      await tester.tap(find.byTooltip('置顶到首页'));
      expect([next, episodes, pins, opens], [1, 1, 1, 0]);
      await tester.tap(find.text(_collection.subject.displayName));
      expect(opens, 1);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await captureUx(tester, boundary, 'feature26_continue_320_$scale');
    });
  }
}

const _collection = UserCollection(
  subjectId: 26,
  type: CollectionType.doing,
  rate: 8,
  episodeStatus: 3,
  updatedAt: null,
  subject: Subject(
    id: 26,
    name: '关于继续追番与记录生活的十二个故事',
    nameCn: '',
    imageUrl: '',
    summary: '',
    episodeCount: 12,
    score: 8,
    rank: 100,
    date: '',
  ),
);
