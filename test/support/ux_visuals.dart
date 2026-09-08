import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/theme/app_theme.dart';

const uxScreenshots = bool.fromEnvironment('UX_SCREENSHOTS');

Future<ThemeData> uxTheme(WidgetTester tester, {required bool dark}) async {
  final theme = dark ? AppTheme.dark : AppTheme.light;
  if (!uxScreenshots) return theme;
  await tester.runAsync(() async {
    final bytes = await File('C:/Windows/Fonts/msyh.ttc').readAsBytes();
    await (FontLoader(
      'UxFont',
    )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  return theme.copyWith(
    textTheme: theme.textTheme.apply(fontFamily: 'UxFont'),
    filledButtonTheme: FilledButtonThemeData(
      style: theme.filledButtonTheme.style?.copyWith(
        textStyle: WidgetStatePropertyAll(
          theme.filledButtonTheme.style?.textStyle
              ?.resolve({})
              ?.copyWith(fontFamily: 'UxFont'),
        ),
      ),
    ),
    chipTheme: theme.chipTheme.copyWith(
      labelStyle: theme.chipTheme.labelStyle?.copyWith(fontFamily: 'UxFont'),
      secondaryLabelStyle: theme.chipTheme.secondaryLabelStyle?.copyWith(
        fontFamily: 'UxFont',
      ),
    ),
  );
}

Future<void> captureUx(WidgetTester tester, GlobalKey key, String name) async {
  if (!uxScreenshots) return;
  final oldShadows = debugDisableShadows;
  debugDisableShadows = false;
  try {
    (key.currentContext!.findRenderObject() as RenderRepaintBoundary)
        .markNeedsPaint();
    await tester.pump();
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        '.dart_tool/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  } finally {
    debugDisableShadows = oldShadows;
  }
}
