import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/theme/app_theme.dart';
import 'package:mubangumi/core/theme/custom_colors.dart';
import 'package:mubangumi/core/theme/app_tokens.dart';
import 'package:mubangumi/widgets/profile_home_layout.dart';
import 'package:mubangumi/widgets/continue_watching_tile.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/core/social/friend_qr_export.dart';
import 'package:image/image.dart' as img;
import 'support/library_batch_fixtures.dart';
import 'support/ux_visuals.dart';

void main() {
  for (final width in [320.0, 1100.0]) {
    testWidgets('profile returns header and current feed to top at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final key = GlobalKey();
      var tab = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: await uxTheme(tester, dark: false),
          builder: (context, child) => RepaintBoundary(key: key, child: child!),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => ProfileHomeLayout(
                nickname: '小沐',
                username: 'fixture',
                sign: '记录喜欢的作品',
                avatarUrl: '',
                total: 80,
                doing: 12,
                friends: 8,
                selectedTab: tab,
                onSelectTab: (t) => setState(() => tab = t),
                onSettings: () {},
                onCollections: () {},
                onDoing: () {},
                onFriends: () {},
                content: ProfileFeedStack(
                  index: tab,
                  children: [
                    for (var i = 0; i < 3; i++)
                      ListView.builder(
                        key: ValueKey('feed-$i'),
                        primary: tab == i,
                        itemExtent: 80,
                        itemCount: 100,
                        itemBuilder: (_, j) => Center(child: Text('动态 $i-$j')),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('回到顶部'), findsNothing);
      final nested = tester.state<NestedScrollViewState>(
        find.byType(NestedScrollView),
      );
      final list = find.byKey(const ValueKey('feed-0'));
      await tester.drag(list, const Offset(0, -650));
      await tester.pumpAndSettle();
      expect(find.byTooltip('回到顶部').hitTestable(), findsOneWidget);
      expect(nested.outerController.position.pixels, greaterThan(0));
      expect(nested.innerController.position.pixels, greaterThan(0));
      await captureUx(tester, key, 'profile-top-button-${width.toInt()}');
      final saved = nested.innerController.position.pixels;
      await tester.tap(find.text('好友动态'));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const ValueKey('feed-1')),
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('回到顶部'));
      await tester.pumpAndSettle();
      expect(nested.outerController.position.pixels, closeTo(0, 1));
      expect(nested.innerController.position.pixels, closeTo(0, 1));
      expect(find.byTooltip('回到顶部'), findsNothing);
      expect(
        tester
            .widget<Opacity>(find.byKey(const Key('profile-header-fade')))
            .opacity,
        1,
      );
      await tester.tap(find.text('我的动态'));
      await tester.pumpAndSettle();
      expect(nested.innerController.position.pixels, closeTo(saved, 1));
      await tester.tap(find.byTooltip('回到顶部'));
      await tester.pumpAndSettle();
      expect(nested.outerController.position.pixels, closeTo(0, 1));
      expect(nested.innerController.position.pixels, closeTo(0, 1));
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'next episode and progress use official pink by default and keep custom colors',
    (tester) async {
      final original = batchFixtureCollection(1, type: SubjectType.anime);
      for (final theme in [
        AppTheme.light,
        AppTheme.dark,
        applyCustomColors(
          AppTheme.light,
          const CustomColors(primary: Color(0xFF9386C8)),
        ),
      ]) {
        final boundary = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: RepaintBoundary(
                key: boundary,
                child: ContinueWatchingTile(
                  collection: original,
                  onOpen: () {},
                  onNext: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final indicator = tester.widget<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator),
        );
        final text = tester.widget<Text>(find.text('看完下一集'));
        final inherited = DefaultTextStyle.of(
          tester.element(find.byWidget(text)),
        ).style;
        final rendered = text.style?.color ?? inherited.color;
        expect(rendered, theme.colorScheme.primary);
        expect(
          indicator.color ??
              Theme.of(
                tester.element(find.byType(LinearProgressIndicator)),
              ).colorScheme.primary,
          theme.colorScheme.primary,
        );
        if (theme.extension<BrandColors>() == null) {
          expect(rendered, AppPalette.bangumiPink);
        }
        final bounds = tester.getRect(find.byType(LinearProgressIndicator));
        final origin = tester.getTopLeft(find.byKey(boundary));
        await tester.runAsync(() async {
          final pixels = img.decodePng(
            await FriendQrExporter.captureBoundary(boundary, pixelRatio: 1),
          )!;
          final pixel = pixels.getPixel(
            (bounds.left - origin.dx + bounds.width * .1).round(),
            (bounds.center.dy - origin.dy).floor(),
          );
          final actual =
              0xFF000000 |
              (pixel.r.toInt() << 16) |
              (pixel.g.toInt() << 8) |
              pixel.b.toInt();
          expect(actual, theme.colorScheme.primary.toARGB32());
        });
      }
    },
  );
}
