import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/widgets/community_composer.dart';
import 'package:mubangumi/widgets/community_rich_content.dart';
import 'package:mubangumi/widgets/community_widgets.dart';
import 'package:mubangumi/models/community_models.dart';

Iterable<TextSpan> spans(InlineSpan span) sync* {
  if (span is TextSpan) {
    yield span;
    for (final child in span.children ?? <InlineSpan>[]) {
      yield* spans(child);
    }
  }
}

Future<void> show(
  WidgetTester tester,
  String source, {
  ValueChanged<Uri>? onOpenLink,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: CommunityRichContent(source, onOpenLink: onOpenLink),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('color and alignment keep nested formatting and spoilers', (
    tester,
  ) async {
    await show(
      tester,
      '[align=center][color=#f00][b]红字[/b][/color][mask]隐藏内容[/mask][/align]',
    );
    final centered = tester
        .widgetList<SelectableText>(find.byType(SelectableText))
        .singleWhere((text) => text.textAlign == TextAlign.center);
    final all = spans(centered.textSpan!).toList();
    expect(
      all.any(
        (span) =>
            span.style?.color == const Color(0xffff0000) &&
            span.style?.fontWeight == FontWeight.bold,
      ),
      isTrue,
    );
    expect(find.textContaining('隐藏内容', findRichText: true), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('spoiler inside a link stays hidden', (tester) async {
    await show(tester, '[url=https://bgm.tv][mask]不应提前显示的结局[/mask][/url]');
    expect(find.textContaining('不应提前显示的结局', findRichText: true), findsNothing);
    await tester.tap(find.text('显示剧透'));
    await tester.pump();
    expect(find.textContaining('不应提前显示的结局', findRichText: true), findsWidgets);
  });

  testWidgets('quote supports very narrow remaining width', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 16,
            child: CommunityRichContent('[quote]内容[/quote]'),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('own-content menu fits narrow screens with large text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var edited = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
            child: CommunityPostCard(
              post: const CommunityPost(
                id: '1',
                author: '很长的用户昵称',
                body: '回复内容',
                meta: '#123 · 2026-09-16 12:30',
              ),
              onEdit: () => edited = true,
              onDelete: () {},
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('管理我的内容'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑回复'));
    await tester.pumpAndSettle();
    expect(edited, isTrue);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'nested formatting preserves text styles and safe link destinations',
    (tester) async {
      Uri? opened;
      await show(
        tester,
        '[b]粗体[i]斜体[/i][/b] [url=https://bgm.tv/subject/42]链接[/url] [url=javascript:bad]不可打开[/url]',
        onOpenLink: (uri) => opened = uri,
      );
      final tree = tester
          .widget<SelectableText>(find.byType(SelectableText).first)
          .textSpan!;
      final all = spans(tree).toList();
      expect(
        all.any((span) => span.style?.fontWeight == FontWeight.bold),
        isTrue,
      );
      expect(
        all.any(
          (span) =>
              span.style?.fontWeight == FontWeight.bold &&
              span.style?.fontStyle == FontStyle.italic,
        ),
        isTrue,
      );
      final link = all.singleWhere((span) => span.text == '链接');
      (link.recognizer as TapGestureRecognizer).onTap!();
      expect(opened.toString(), 'https://bgm.tv/subject/42');
      expect(all.singleWhere((span) => span.text == '不可打开').recognizer, isNull);
    },
  );

  for (final width in [320.0, 1200.0]) {
    testWidgets(
      'quote code and spoiler are visible only as intended at width $width',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await show(
          tester,
          '前文\n[quote]引用内容[/quote]\n[code][b]保留代码[/b][/code]\n[mask]隐藏的结局[/mask]\n后文',
        );
        expect(find.text('引用内容', findRichText: true), findsWidgets);
        expect(find.text('[b]保留代码[/b]'), findsOneWidget);
        expect(find.text('隐藏的结局', findRichText: true), findsNothing);
        await tester.tap(find.text('显示剧透'));
        await tester.pump();
        expect(find.text('隐藏的结局', findRichText: true), findsWidgets);
        await tester.tap(find.text('隐藏剧透'));
        await tester.pump();
        expect(find.text('隐藏的结局', findRichText: true), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('inline image placeholders stay between their surrounding text', (
    tester,
  ) async {
    await show(tester, '前文[img]javascript:bad[/img]后文');
    final tree = tester
        .widget<SelectableText>(find.byType(SelectableText).first)
        .textSpan!;
    expect(tree.children, hasLength(3));
    expect(tree.children![0].toPlainText(), '前文');
    expect(tree.children![1], isA<WidgetSpan>());
    expect(tree.children![2].toPlainText(), '后文');
    expect(find.text('（无效图片链接）'), findsOneWidget);
  });

  testWidgets(
    'edit composer restores original BBCode and saves without a challenge',
    (tester) async {
      var challenged = false;
      String? sent;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showCommunityComposer(
                  context,
                  heading: '编辑回复',
                  initialContent: '[b]原文[/b]',
                  requireVerification: false,
                  submitLabel: '保存',
                  tokenProvider: (_) async {
                    challenged = true;
                    return 'token';
                  },
                  onSubmit: (_, content, _) async {
                    sent = content;
                  },
                ),
                child: const Text('编辑'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('编辑'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '[b]原文[/b]',
      );
      await tester.tap(find.text('预览正文'));
      await tester.pumpAndSettle();
      expect(find.byType(CommunityRichContent), findsOneWidget);
      await tester.tap(find.text('继续编辑'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '[i]修改后的回复[/i]');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(sent, '[i]修改后的回复[/i]');
      expect(challenged, isFalse);
    },
  );
}
