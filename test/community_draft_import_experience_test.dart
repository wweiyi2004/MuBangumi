import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/storage/community_draft_store.dart';
import 'package:mubangumi/widgets/community_composer.dart';

import 'support/ux_visuals.dart';

void main() {
  for (final width in [320.0, 390.0, 1200.0]) {
    for (final scale in [1.0, 1.8]) {
      for (final dark in [false, true]) {
        testWidgets(
          'draft conflict remains readable $width scale $scale dark $dark',
          (tester) async {
            tester.view.physicalSize = Size(width, width < 500 ? 720 : 1000);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            final theme = await uxTheme(tester, dark: dark);
            final boundary = GlobalKey();
            await tester.pumpWidget(
              MaterialApp(
                theme: theme,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: RepaintBoundary(key: boundary, child: child!),
                ),
                home: Builder(
                  builder: (context) => Scaffold(
                    body: TextButton(
                      onPressed: () => showCommunityComposer(
                        context,
                        heading: '写回复',
                        requireTitle: true,
                        draftKey: 'draft',
                        draftStore: _ConflictingDraft(),
                        tokenProvider: (_) async => null,
                        onSubmit: (_, _, _) async {},
                      ),
                      child: const Text('打开'),
                    ),
                  ),
                ),
              ),
            );
            await tester.tap(find.text('打开'));
            await tester.pumpAndSettle();
            final field = find.widgetWithText(TextField, '内容');
            await tester.ensureVisible(field);
            await tester.pump();
            await tester.enterText(field, '这段文字还需要保留，稍后继续编辑。');
            await tester.pump(const Duration(milliseconds: 400));
            final warning = find.textContaining('草稿已在其他操作中更新');
            await tester.ensureVisible(warning);
            await tester.pumpAndSettle();
            await captureUx(
              tester,
              boundary,
              'm6_draft_conflict_${width.toInt()}_${scale}_$dark',
            );
            expect(tester.takeException(), isNull);
            final close = find.text('不保存并关闭');
            expect(
              tester.getSize(find.widgetWithText(TextButton, '不保存并关闭')).height,
              greaterThanOrEqualTo(48),
            );
            await tester.tap(close);
            await tester.pumpAndSettle();
            expect(find.byType(AlertDialog), findsNothing);
          },
        );
      }
    }
  }
}

class _ConflictingDraft extends CommunityDraftRepository {
  @override
  Future<CommunityDraftData?> load(String key) async =>
      (title: '草稿标题', content: '原文');
  @override
  Future<void> save(String key, CommunityDraftData draft) async =>
      throw const CommunityDraftConflict();
}
