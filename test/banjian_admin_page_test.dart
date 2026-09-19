import 'package:mubangumi/navigation/app_destination.dart';
import 'package:mubangumi/navigation/app_router.dart';
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:banjian_server/banjian_server.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/theme/app_theme.dart';
import 'package:mubangumi/features/anime_appreciation/room_admin_page.dart';
import 'package:mubangumi/features/anime_appreciation/room_host.dart';
import 'banjian_layout_test.dart' show PreviewHost;

class AdminFixture extends PreviewHost {
  AdminFixture() {
    liveConnected = true;
    event!['members'] = [
      {'name': '到场成员', 'submitted': true},
    ];
    for (final r in event!['rounds']) {
      r['published'] = false;
      r['publicComments'] = false;
      r['stats'] = {
        'mean': 8.2,
        'distribution': [0, 0, 0, 0, 0, 1, 1, 3, 3, 1],
      };
      r['comments'] = [
        {'id': 'comment', 'text': '匿名感受', 'hidden': false},
      ];
    }
  }
  final commands = <Json>[];
  Completer<void>? gate;
  @override
  Future<void> refresh({String? eventId, bool wait = true}) async {
    await gate?.future;
  }

  @override
  Future<void> command(String action, [Json extra = const {}]) async {
    commands.add({'action': action, ...extra});
    final copy = clone(event!);
    final r = (copy['rounds'] as List).firstWhere(
      (r) => r['id'] == extra['round'],
      orElse: () => copy['rounds'][0],
    );
    switch (action) {
      case 'pause':
        r['status'] = 'paused';
      case 'resume':
        r['status'] = 'open';
      case 'publish':
        r['published'] = extra['value'];
      case 'comments':
        r['publicComments'] = extra['value'];
      case 'hide':
        r['comments'][0]['hidden'] = extra['value'];
    }
    copy['version'] = (copy['version'] as int) + 1;
    event = copy;
    notifyListeners();
  }
}

const capture = bool.fromEnvironment('LAYOUT_SCREENSHOTS');
void main() {
  for (final variant in [
    'desktop',
    'compact',
    'phone',
    'small',
    'large',
    'dark',
    'loading',
  ]) {
    testWidgets('native admin $variant', (tester) async {
      final phone = ['phone', 'small', 'large'].contains(variant);
      final size = Size(
        phone
            ? (variant == 'small' ? 360 : 390)
            : (variant == 'compact' ? 1024 : 1280),
        variant == 'small' || variant == 'compact' ? 640 : 800,
      );
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final host = AdminFixture();
      if (variant == 'loading') host.gate = Completer<void>();
      final container = ProviderContainer(
        overrides: [roomHostProvider.overrideWith((_) => host)],
      );
      addTearDown(container.dispose);
      if (capture) {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        await tester.runAsync(() async {
          final font = FontLoader('Microsoft YaHei UI');
          for (final name in ['msyh-ui.ttf', 'msyhbd-ui.ttf']) {
            font.addFont(
              Future.value(
                ByteData.sublistView(
                  await File('.dart_tool/pm-chat-fonts/$name').readAsBytes(),
                ),
              ),
            );
          }
          await font.load();
          await (FontLoader('Consolas')..addFont(
                Future.value(
                  ByteData.sublistView(
                    await File('C:/Windows/Fonts/consola.ttf').readAsBytes(),
                  ),
                ),
              ))
              .load();
          await (FontLoader('MaterialIcons')
                ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
              .load();
        });
      }
      final boundary = GlobalKey();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: AppRouteScope(
            resolve: AppRouter.resolve,
            child: MaterialApp(
              theme: variant == 'dark' ? AppTheme.dark : AppTheme.light,
              home: MediaQuery(
                data: MediaQueryData(
                  size: size,
                  textScaler: TextScaler.linear(variant == 'large' ? 1.6 : 1),
                ),
                child: RepaintBoundary(
                  key: boundary,
                  child: RoomAdminPage(
                    subjectPicker: (_) => const Scaffold(body: Text('选番')),
                    onInvite: () async {},
                    onOpenWeb: () async {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      if (variant == 'loading') {
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          tester.getSize(find.byType(SizeTransition)).height,
          greaterThan(40),
        );
      } else {
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
      expect(find.text('暂停评分'), findsOneWidget);
      expect(
        tester.getRect(find.text('下一部')).bottom,
        lessThanOrEqualTo(size.height),
      );
      if (capture) {
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 1.5);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final path = File(
            'docs/qa/banjian-implementation/native-admin-$variant.png',
          );
          await path.parent.create(recursive: true);
          await path.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      if (variant == 'desktop') {
        await tester.tap(find.text('暂停评分'));
        await tester.pumpAndSettle();
        expect(host.commands.last['action'], 'pause');
        await tester.tap(find.text('继续评分'));
        await tester.pumpAndSettle();
        expect(host.commands.last['action'], 'resume');
        await tester.tap(find.text('公布结果'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, '确定'));
        await tester.pumpAndSettle();
        expect(host.commands.last['action'], 'publish');
        await tester.tap(find.text('隐藏'));
        await tester.pumpAndSettle();
        expect(host.commands.last['action'], 'hide');
        final accepted = host.commands.length;
        await tester.tap(find.byTooltip('管理操作'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('结束活动'));
        await tester.pumpAndSettle();
        host.event = {
          ...host.event!,
          'version': (host.event!['version'] as int) + 1,
        };
        host.notifyListeners();
        await tester.pump();
        await tester.tap(find.widgetWithText(FilledButton, '确定'));
        await tester.pumpAndSettle();
        expect(
          host.commands.length,
          accepted,
          reason:
              'a stale confirmation must not execute against newer activity state',
        );
      }
      host.gate?.complete();
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
