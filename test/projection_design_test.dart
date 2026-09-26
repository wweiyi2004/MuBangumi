import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/recommend/fan_recommend_engine.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/widgets/projection_art.dart';
import 'package:mubangumi/widgets/recommendation_ticket.dart';
import 'support/ux_visuals.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets('projection artwork ${dark ? 'dark' : 'light'}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(720, 500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final theme = await uxTheme(tester, dark: dark);
      if (uxScreenshots && Platform.isWindows) {
        await tester.runAsync(() async {
          final bytes = await File(
            'C:/Windows/Fonts/consola.ttf',
          ).readAsBytes();
          for (final family in ['Consolas', 'monospace']) {
            await (FontLoader(
              family,
            )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
          }
        });
      }
      final boundary = GlobalKey();
      var wished = false;
      final subject = Subject.fromJson({
        'id': 100,
        'type': 2,
        'name': '夜航随笔',
        'name_cn': '夜航随笔',
        'date': '2026-01-01',
        'rating': {'score': 8.1, 'rank': 120},
        'images': {},
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: RepaintBoundary(
            key: boundary,
            child: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'MuBangumi · 放映与记录',
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 4),
                    const Text('视觉预览 · 以下作品信息为演示数据'),
                    const SizedBox(height: 8),
                    RecommendationTicket(
                      item: FanRecommendItem(
                        subject: subject,
                        score: 100,
                        reasons: const ['标签：日常 · 旅行', '与你的收藏标签相合'],
                        matchedTags: const ['日常'],
                      ),
                      index: 1,
                      onTap: () {},
                      onHide: () {},
                      onWish: () => wished = true,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        for (final scene in ProjectionScene.values)
                          Column(
                            children: [
                              ProjectionIllustration(scene: scene),
                              const SizedBox(height: 4),
                              Text(switch (scene) {
                                ProjectionScene.discover => '暂时没有找到作品',
                                ProjectionScene.collection => '收藏等你来填满',
                                ProjectionScene.conversation => '从一句问候开始',
                              }),
                            ],
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        for (final progress in [0.0, .3, .5, .7])
                          ProjectionGlyph(progress: progress),
                        const ProjectionGlyph(complete: true),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: Text(
                        '散点聚合 → 放映 → 完成',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('加入想看'));
      expect(wished, true);
      expect(tester.takeException(), isNull);
      await captureUx(
        tester,
        boundary,
        'projection_design_${dark ? 'dark' : 'light'}',
      );
    });
  }
}
