import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/theme/app_theme.dart';
import 'package:mubangumi/screens/settings_page.dart';
import 'package:mubangumi/state/session_controller.dart';
import 'package:mubangumi/state/website_session_controller.dart';
import 'support/pm_fixtures.dart';

const capture = bool.fromEnvironment('LAYOUT_SCREENSHOTS');

void main() {
  for (final variant in ['desktop', 'phone', 'desktop-dark']) {
    testWidgets('settings groups related entries ($variant)', (tester) async {
      final phone = variant.startsWith('phone');
      tester.view.physicalSize = Size(phone ? 390 : 1280, phone ? 844 : 880);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final container = ProviderContainer(
        overrides: [
          sessionProvider.overrideWith((ref) => PmTestSession()),
          websiteSessionStoreProvider.overrideWithValue(PmTestWebsiteStore()),
        ],
      );
      addTearDown(container.dispose);
      if (capture) {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        await tester.runAsync(() async {
          final font = FontLoader('Microsoft YaHei UI');
          for (final file in ['msyh-ui.ttf', 'msyhbd-ui.ttf']) {
            font.addFont(
              Future.value(
                ByteData.sublistView(
                  await File('.dart_tool/pm-chat-fonts/$file').readAsBytes(),
                ),
              ),
            );
          }
          await font.load();
          await (FontLoader('MaterialIcons')
                ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
              .load();
        });
      }
      final boundary = GlobalKey();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: variant.endsWith('dark') ? AppTheme.dark : AppTheme.light,
            home: RepaintBoundary(key: boundary, child: const SettingsPage()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Group titles and their entries, top to bottom.
      for (final text in [
        '同步与数据',
        '本地备份与导入',
        '外观',
        '外观主题',
        '背景与毛玻璃',
        '网络与更新',
        'Bangumi 网络线路',
        '检查更新',
        '账号',
        'Bangumi 账号',
        '打开 Bangumi 个人主页',
        '更多',
        '实验性功能',
      ]) {
        await tester.scrollUntilVisible(find.text(text), 80);
        expect(find.text(text), findsOneWidget, reason: text);
      }
      await tester.scrollUntilVisible(find.text('退出登录'), 80);
      // Signing out stays last, apart from the account group.
      expect(
        tester.getTopLeft(find.text('退出登录')).dy,
        greaterThan(tester.getTopLeft(find.text('实验性功能')).dy),
      );

      final card = tester.getRect(find.byType(Card).first);
      // The title starts where the column does, not at the window edge.
      expect(
        tester.getTopLeft(find.text('设置')).dx,
        closeTo(card.left + (phone ? 0 : 16), 17),
      );
      if (phone) {
        expect(card.left, 16);
        expect(card.right, 390 - 16);
      } else {
        // Wide windows keep a centered reading column.
        expect(card.width, 720);
        expect(card.center.dx, closeTo(640, 1));
      }

      if (capture) {
        await tester.drag(find.byType(ListView), const Offset(0, -2000));
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory('docs/qa/settings-review').create(recursive: true);
          await File(
            'docs/qa/settings-review/$variant.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
