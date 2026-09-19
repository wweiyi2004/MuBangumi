import 'package:mubangumi/navigation/app_destination.dart';
import 'package:mubangumi/navigation/app_router.dart';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/theme/app_theme.dart';
import 'package:mubangumi/screens/background_settings_sheet.dart';
import 'package:mubangumi/state/background_controller.dart';
import 'package:mubangumi/state/system_appearance_controller.dart';
import 'package:mubangumi/widgets/app_background.dart';
import 'support/background_fixtures.dart';

const capture = bool.fromEnvironment('BACKGROUND_SCREENSHOTS');
final boundaryKey = GlobalKey();

double contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return (x > y ? x + .05 : y + .05) / (x > y ? y + .05 : x + .05);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late File image;
  setUpAll(() async {
    final dir = await Directory(
      '.dart_tool/background-test-data',
    ).create(recursive: true);
    image = await backgroundTestImage(
      dir,
      name: 'pattern.png',
      width: 400,
      height: 240,
      patterned: true,
    );
  });

  test(
    'body and secondary text remain readable over extreme wallpapers at all slider limits',
    () {
      for (final base in [AppTheme.light, AppTheme.dark]) {
        for (final dim in [0.0, .32, .75]) {
          for (final glass in [.15, .42, .8]) {
            final settings = AppBackgroundSettings(
              enabled: true,
              imagePath: image.path,
              dim: dim,
              glass: glass,
            );
            final theme = applyBackgroundTheme(base, settings);
            for (final wallpaper in [
              Colors.black,
              Colors.white,
              Colors.red,
              Colors.green,
              Colors.blue,
            ]) {
              final backdrop = Color.alphaBlend(
                BackgroundWallpaper.veil(theme, settings),
                wallpaper,
              );
              for (final text in [
                theme.colorScheme.onSurface,
                theme.colorScheme.onSurfaceVariant,
              ]) {
                expect(
                  contrast(text, backdrop),
                  greaterThanOrEqualTo(4.5),
                  reason: '${base.brightness} dim=$dim glass=$glass',
                );
                expect(
                  contrast(text, theme.cardTheme.color!),
                  greaterThanOrEqualTo(4.5),
                );
                final nav = Color.alphaBlend(
                  theme.appBarTheme.backgroundColor!,
                  backdrop,
                );
                expect(contrast(text, nav), greaterThanOrEqualTo(4.5));
              }
            }
            for (final surface in [
              theme.cardTheme.color!,
              theme.canvasColor,
              theme.dialogTheme.backgroundColor!,
              theme.bottomSheetTheme.modalBackgroundColor!,
              theme.drawerTheme.backgroundColor!,
              theme.inputDecorationTheme.fillColor!,
              theme.popupMenuTheme.color!,
            ]) {
              expect(surface.a, 1);
            }
            expect(
              theme.navigationBarTheme.backgroundColor,
              theme.navigationRailTheme.backgroundColor,
            );
          }
        }
      }
    },
  );

  testWidgets(
    'preview and wallpaper share the blur and all 40 steps change the effect',
    (tester) async {
      final controller = BackgroundTestController(
        AppBackgroundSettings(enabled: true, imagePath: image.path),
      );
      await showSettings(tester, controller);
      final previewFilter = find.descendant(
        of: find.byType(BackgroundSettingsPreview),
        matching: find.byType(ImageFiltered),
      );
      expect(previewFilter, findsOneWidget);
      await controller.setBlur(33);
      await tester.pumpAndSettle();
      final first = tester.widget<ImageFiltered>(previewFilter).imageFilter;
      await controller.setBlur(40);
      await tester.pumpAndSettle();
      final last = tester.widget<ImageFiltered>(previewFilter).imageFilter;
      expect(first, isNot(last));
      for (final filter in tester.widgetList<ImageFiltered>(
        find.byType(ImageFiltered),
      )) {
        expect(filter.imageFilter, last);
      }
      await controller.flush();
      expect(tester.takeException(), isNull);
    },
  );

  for (var sliderIndex = 0; sliderIndex < 3; sliderIndex++) {
    testWidgets(
      'slider $sliderIndex previews locally without rebuilding the applied background',
      (tester) async {
        final storage = BackgroundTestStorage();
        final controller = BackgroundTestController(
          AppBackgroundSettings(enabled: true, imagePath: image.path),
          storage: storage,
        );
        var appliedBuilds = 0;
        await showSettings(
          tester,
          controller,
          onAppliedBuild: () => appliedBuilds++,
        );
        await tester.tap(find.text('高级调整'));
        await tester.pumpAndSettle();
        final slider = find.byType(Slider).at(sliderIndex);
        await tester.ensureVisible(slider);
        await tester.pumpAndSettle();
        final before = appliedBuilds;
        final oldValue = tester.widget<Slider>(slider).value;
        final start = tester.getCenter(slider);
        final gesture = await tester.startGesture(start);
        for (var i = 1; i <= 30; i++) {
          await gesture.moveTo(start + Offset(i * 3.0, 0));
          await tester.pump(const Duration(milliseconds: 16));
        }
        final during = appliedBuilds - before;
        expect(storage.writes, isEmpty);
        expect(tester.widget<Slider>(slider).value, isNot(oldValue));
        final draft = tester
            .widget<BackgroundSettingsPreview>(
              find.byType(BackgroundSettingsPreview),
            )
            .settings;
        final applied = tester
            .widgetList<BackgroundWallpaper>(find.byType(BackgroundWallpaper))
            .first
            .settings;
        expect(draft.toJson(), isNot(applied.toJson()));
        // Holding the pointer still must not trigger the old 250 ms save/apply.
        await tester.pump(const Duration(seconds: 1));
        expect(storage.writes, isEmpty);
        expect(appliedBuilds, before);
        await gesture.up();
        await tester.pumpAndSettle();
        debugPrint(
          '30 drag frames: applied background builds during drag=$during, after release=${appliedBuilds - before}',
        );
        expect(during, 0);
        expect(appliedBuilds - before, 1);
        expect(storage.writes, hasLength(1));
        expect(controller.state.appliedSettings, isNull);
      },
    );
  }

  testWidgets('dismissing settings commits an unfinished preview', (
    tester,
  ) async {
    final storage = BackgroundTestStorage();
    final controller = BackgroundTestController(
      AppBackgroundSettings(enabled: true, imagePath: image.path),
      storage: storage,
    );
    await showSettings(tester, controller);
    controller.beginAdjustments();
    await controller.setBlur(35);
    await tester.pump();
    Navigator.of(tester.element(find.byType(BackgroundSettingsPreview))).pop();
    await tester.pumpAndSettle();
    expect(controller.state.appliedSettings, isNull);
    expect(controller.state.blur, 35);
    expect(storage.writes, hasLength(1));
  });

  testWidgets(
    'no wallpaper disables adjustments and reset retains the selected image',
    (tester) async {
      final controller = BackgroundTestController(
        const AppBackgroundSettings(),
      );
      await showSettings(tester, controller);
      await tester.tap(find.text('高级调整'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<Slider>(find.byType(Slider))
            .every((slider) => slider.onChanged == null),
        isTrue,
      );
      expect(find.text('尚未选择图片'), findsOneWidget);
    },
  );

  for (final system in [
    const SystemAppearance(highContrast: true),
    const SystemAppearance(transparency: false),
    const SystemAppearance(batterySaver: true),
  ]) {
    testWidgets(
      'system fallback ${system.highContrast}/${system.transparency}/${system.batterySaver} preserves preferences',
      (tester) async {
        final controller = BackgroundTestController(
          AppBackgroundSettings(enabled: true, imagePath: image.path),
        );
        final native = AppearanceTestController();
        await showSettings(tester, controller, system: native);
        expect(find.byType(ImageFiltered), findsWidgets);
        native.update(system);
        await tester.pumpAndSettle();
        expect(find.byType(ImageFiltered), findsNothing);
        expect(controller.state.enabled, isTrue);
        expect(controller.state.imagePath, image.path);
        native.update(const SystemAppearance());
        await tester.pumpAndSettle();
        expect(find.byType(ImageFiltered), findsWidgets);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'platform high contrast removes wallpaper and uses opaque panels',
    (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(highContrast: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final controller = BackgroundTestController(
        AppBackgroundSettings(enabled: true, imagePath: image.path),
      );
      await showSettings(tester, controller);
      expect(find.byType(ImageFiltered), findsNothing);
      expect(find.text('高对比度已开启，当前使用纯色界面。'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final variant in ['light', 'dark', 'phone', 'large']) {
    testWidgets('$variant settings layout and renderer', (tester) async {
      final controller = BackgroundTestController(
        AppBackgroundSettings(enabled: true, imagePath: image.path),
      );
      if (capture) debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        await showSettings(
          tester,
          controller,
          width: variant == 'phone' ? 390 : 1200,
          dark: variant == 'dark',
          scale: variant == 'large' ? 1.6 : 1,
        );
        await tester.tap(find.text('高级调整'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (capture) {
          await tester.runAsync(() async {
            final boundary =
                boundaryKey.currentContext!.findRenderObject()
                    as RenderRepaintBoundary;
            final img = await boundary.toImage();
            final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
            await File(
              '.dart_tool/background-fixed-$variant.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            img.dispose();
          });
        }
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}

Future<void> showSettings(
  WidgetTester tester,
  BackgroundController controller, {
  AppearanceTestController? system,
  double width = 1200,
  bool dark = false,
  double scale = 1,
  VoidCallback? onAppliedBuild,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  if (controller.state.hasImage) {
    // Start file decoding outside fake async before Image creates a pending
    // cache entry. Awaiting that old entry inside runAsync would deadlock.
    await tester.pumpWidget(
      const AppRouteScope(
        resolve: AppRouter.resolve,
        child: MaterialApp(home: SizedBox.shrink()),
      ),
    );
    final context = tester.element(find.byType(MaterialApp));
    await tester.runAsync(() async {
      for (final imageWidth in [
        width.round(),
        (width < 640 ? width : 640).round() - 40,
      ]) {
        await precacheImage(
          ResizeImage(
            FileImage(File(controller.state.imagePath!)),
            width: imageWidth,
            allowUpscaling: false,
          ),
          context,
        );
      }
    });
  }
  if (capture) {
    await tester.runAsync(() async {
      final font = FontLoader('Microsoft YaHei UI');
      for (final name in ['msyh-ui.ttf', 'msyhbd-ui.ttf']) {
        final bytes = await File(
          '.dart_tool/pm-chat-fonts/$name',
        ).readAsBytes();
        font.addFont(Future.value(ByteData.sublistView(bytes)));
      }
      await font.load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    });
  }
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        backgroundSettingsProvider.overrideWith((ref) => controller),
        systemAppearanceProvider.overrideWith(
          (ref) => system ?? AppearanceTestController(),
        ),
      ],
      child: Consumer(
        builder: (context, ref, _) {
          onAppliedBuild?.call();
          final settings = ref.watch(effectiveBackgroundProvider);
          final native = ref.watch(systemAppearanceProvider);
          final base = dark ? AppTheme.dark : AppTheme.light;
          return AppRouteScope(
            resolve: AppRouter.resolve,
            child: MaterialApp(
              theme: native.highContrast
                  ? highContrastBackgroundTheme(base, native)
                  : applyBackgroundTheme(base, settings),
              highContrastTheme: highContrastBackgroundTheme(base, native),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: RepaintBoundary(
                  key: boundaryKey,
                  child: AppBackgroundHost(child: child!),
                ),
              ),
              home: Scaffold(
                appBar: AppBar(title: const Text('背景效果检查')),
                body: Center(
                  child: Builder(
                    builder: (context) => FilledButton(
                      onPressed: () =>
                          showBackgroundSettingsSheet(context, ref),
                      child: const Text('打开设置'),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('打开设置'));
  await tester.pumpAndSettle();
  final images = tester.widgetList<Image>(find.byType(Image)).toList();
  if (images.isNotEmpty) {
    expect(
      tester
          .widgetList<RawImage>(find.byType(RawImage))
          .every((image) => image.image != null),
      isTrue,
    );
  }
}
