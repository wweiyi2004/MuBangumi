import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/features/anime_appreciation/room_pages.dart';
import 'package:mubangumi/features/tier_print/tier_print_catalog.dart';
import 'package:mubangumi/features/tier_print/tier_print_models.dart';
import 'package:mubangumi/features/tier_print/tier_print_page.dart';

class Catalog extends TierPrintCatalog {
  Completer<TierCatalogResult>? pending;
  bool fail = false;
  int count = 2;
  int calls = 0;
  @override
  Future<TierCatalogResult> load(
    TierPrintPeriod period, {
    CancelToken? cancel,
    void Function(String)? progress,
  }) async {
    calls++;
    if (fail) throw const FormatException('目录不完整');
    return pending?.future ??
        TierCatalogResult(
          entries: [
            for (var i = 0; i < count; i++)
              TierPrintEntry(
                id: i + 1,
                title: '条目 ${i + 1}',
                date: '${period.year}-01-01',
                coverUrl: '',
                platform: i.isEven ? 'TV' : '剧场版',
              ),
          ],
          sourceCount: count,
          fetchedAt: DateTime.now(),
        );
  }
}

void main() {
  testWidgets(
    'board stays one sheet for many covers and custom slots survive reloading',
    (tester) async {
      final catalog = Catalog()..count = 100;
      addTearDown(catalog.close);
      await tester.pumpWidget(
        MaterialApp(home: TierPrintPage(catalog: catalog)),
      );
      await tester.tap(find.text('读取全部条目'));
      await tester.pumpAndSettle();
      expect(find.textContaining('选中 100 部 · 封面 4 页 · 底板 1 页'), findsOneWidget);
      final slots = find.widgetWithText(TextField, '每档预留格数');
      expect(tester.widget<TextField>(slots).decoration!.hintText, '自动：7');
      await tester.ensureVisible(slots);
      await tester.enterText(slots, '2');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('读取全部条目'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('读取全部条目'));
      await tester.pumpAndSettle();
      expect(catalog.calls, 2);
      expect(tester.widget<TextField>(slots).controller!.text, '2');
      expect(find.textContaining('选中 100 部 · 封面 4 页 · 底板 1 页'), findsOneWidget);
      final part = find.byWidgetPredicate(
        (widget) => widget is DropdownButtonFormField<TierPrintPart>,
      );
      await tester.ensureVisible(part);
      await tester.pumpAndSettle();
      await tester.tap(part);
      await tester.pumpAndSettle();
      await tester.tap(find.text('排行榜底板').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('清空选择'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('清空选择'));
      await tester.pumpAndSettle();
      expect(find.textContaining('选中 0 部 · 封面 0 页 · 底板 1 页'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '导出打印 PDF'))
            .onPressed,
        isNotNull,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'experimental menu opens the print workshop without network side effects',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: ExperimentalFeaturesPage()),
      );
      await tester.tap(find.text('从夯到拉 · 打印工坊'));
      await tester.pumpAndSettle();
      expect(find.byType(TierPrintPage), findsOneWidget);
      expect(find.text('读取全部条目'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final width in [360.0, 1200.0]) {
    testWidgets(
      'workshop selects all, filters and prevents stale-period export at width $width',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final catalog = Catalog();
        addTearDown(catalog.close);
        await tester.pumpWidget(
          MaterialApp(home: TierPrintPage(catalog: catalog)),
        );
        await tester.tap(find.text('读取全部条目'));
        await tester.pumpAndSettle();
        expect(find.textContaining('选中 2 部'), findsOneWidget);
        await tester.ensureVisible(find.text('仅 TV 动画'));
        await tester.tap(find.text('仅 TV 动画'));
        await tester.pumpAndSettle();
        expect(find.textContaining('选中 1 部'), findsOneWidget);
        expect(find.textContaining('封面每张 A4 可排 25 张'), findsOneWidget);
        await tester.ensureVisible(
          find.byKey(const ValueKey('tier-board-paper')),
        );
        await tester.tap(find.byKey(const ValueKey('tier-board-paper')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('A1').last);
        await tester.pumpAndSettle();
        expect(find.textContaining('排行榜使用 A1'), findsOneWidget);
        expect(find.textContaining('封面每张 A4 可排 25 张'), findsOneWidget);
        expect(
          tester
              .widget<DropdownButtonFormField<TierPrintPaper>>(
                find.byKey(const ValueKey('tier-cover-paper')),
              )
              .initialValue,
          TierPrintPaper.a4,
        );
        final export = find.widgetWithText(FilledButton, '导出打印 PDF');
        expect(tester.widget<FilledButton>(export).onPressed, isNotNull);
        await tester.ensureVisible(find.widgetWithText(TextField, '年份'));
        await tester.enterText(find.widgetWithText(TextField, '年份'), '2001');
        await tester.pump();
        expect(tester.widget<FilledButton>(export).onPressed, isNull);
        expect(find.text('时间范围已修改，请重新读取目录后导出。'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('a failed catalogue never exposes an export action', (
    tester,
  ) async {
    final catalog = Catalog()..fail = true;
    addTearDown(catalog.close);
    await tester.pumpWidget(MaterialApp(home: TierPrintPage(catalog: catalog)));
    await tester.tap(find.text('读取全部条目'));
    await tester.pumpAndSettle();
    expect(find.text('目录不完整'), findsOneWidget);
    expect(find.text('导出打印 PDF'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
