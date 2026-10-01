import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/theme/anime_icon.dart';
import 'package:mubangumi/core/theme/anime_icon_assets.dart';
import 'package:flutter/services.dart';
import 'support/ux_visuals.dart';

void main() {
  testWidgets('SVG icons keep original identity, size and accessible labels', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: IconTheme(
            data: IconThemeData(size: 32, color: Colors.pink),
            child: AnimeIcon(Icons.search_rounded, semanticLabel: '搜索作品'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.search_rounded), findsOneWidget);
    expect(tester.getSize(find.byType(AnimeIcon)), const Size(32, 32));
    expect(find.bySemanticsLabel('搜索作品'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  test(
    'every declared SVG asset is bundled and has a scalable view box',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      for (final asset in animeIconAssets.values.toSet()) {
        final svg = await rootBundle.loadString(asset);
        expect(svg, contains('viewBox="0 0 24 24"'), reason: asset);
      }
    },
  );
  testWidgets('anime icon gallery visual review', (tester) async {
    final key = GlobalKey();
    final theme = await uxTheme(tester, dark: false);
    const icons = [
      Icons.play_circle_outline_rounded,
      Icons.video_library_outlined,
      Icons.explore_outlined,
      Icons.chat_bubble_outline_rounded,
      Icons.person_outline_rounded,
      Icons.calendar_month_outlined,
      Icons.notifications_outlined,
      Icons.search_rounded,
      Icons.favorite_border_rounded,
      Icons.edit_rounded,
      Icons.send_rounded,
      Icons.ios_share_rounded,
      Icons.qr_code_scanner_rounded,
      Icons.settings_outlined,
      Icons.download_rounded,
      Icons.multiline_chart_rounded,
      Icons.badge_outlined,
      Icons.menu_book_rounded,
      Icons.group_outlined,
      Icons.text_fields_rounded,
    ];
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: key,
              child: Container(
                width: 520,
                padding: const EdgeInsets.all(24),
                color: theme.colorScheme.surface,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('MuBangumi · 星光图标', style: theme.textTheme.titleLarge),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 24,
                      runSpacing: 24,
                      children: [
                        for (final icon in icons)
                          SizedBox(
                            width: 68,
                            height: 54,
                            child: AnimeIcon(
                              icon,
                              size: 32,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await captureUx(tester, key, 'anime-icon-gallery');
  });
}
