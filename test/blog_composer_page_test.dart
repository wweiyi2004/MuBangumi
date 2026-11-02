import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/storage/community_draft_store.dart';
import 'package:mubangumi/widgets/community_composer.dart';
import 'package:mubangumi/models/community_topic_submission.dart';

import 'support/ux_visuals.dart';

class _Drafts extends CommunityDraftRepository {
  CommunityDraftData? data;
  @override
  Future<CommunityDraftData?> load(String key) async => data;
  @override
  Future<void> save(String key, CommunityDraftData value) async {
    data = value.title.isEmpty && value.content.isEmpty ? null : value;
  }
}

Future<GlobalKey> _open(
  WidgetTester tester, {
  bool dark = false,
  double scale = 1,
  _Drafts? store,
  CommunityBlogDraft? metadata,
  CommunitySubmit? submit,
  CommunityTokenProvider? tokenProvider,
  bool Function()? isAccountCurrent,
  String initialTitle = '',
  String initialContent = '',
}) async {
  final boundary = GlobalKey();
  final theme = await uxTheme(tester, dark: dark);
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
              heading: '发布日志',
              submitLabel: '发布',
              requireTitle: true,
              initialTitle: initialTitle,
              initialContent: initialContent,
              maxLength: 100000,
              blogDraft: metadata ?? CommunityBlogDraft(),
              draftKey: 'alice/blog-v1/new',
              draftStore: store ?? _Drafts(),
              isAccountCurrent: isAccountCurrent,
              tokenProvider: tokenProvider ?? (_) async => 'synthetic-token',
              onSubmit: submit ?? (_, _, _) async {},
            ),
            child: const Text('写日志'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('写日志'));
  await tester.pumpAndSettle();
  return boundary;
}

void main() {
  testWidgets(
    'blog picture tool inserts at the cursor and system back saves the draft',
    (tester) async {
      final store = _Drafts();
      await _open(tester, store: store);
      await tester.enterText(find.byKey(const Key('blog-title')), '图片日志');
      await tester.enterText(find.byKey(const Key('blog-body')), '之前之后');
      final body = tester
          .widget<TextField>(find.byKey(const Key('blog-body')))
          .controller!;
      body.selection = const TextSelection.collapsed(offset: 2);
      await tester.ensureVisible(find.text('图片'));
      await tester.tap(find.text('图片'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, '图片链接'),
        'file:///local.png',
      );
      await tester.tap(find.text('插入'));
      await tester.pumpAndSettle();
      expect(find.textContaining('请输入有效的'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, '图片链接'),
        'https://example.invalid/image.png',
      );
      await tester.tap(find.text('插入'));
      await tester.pumpAndSettle();
      expect(body.text, '之前[img]https://example.invalid/image.png[/img]之后');
      await tester
          .state<NavigatorState>(find.byType(Navigator).first)
          .maybePop();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('blog-composer-page')), findsNothing);
      expect(store.data!.title, '图片日志');
      final metadata = CommunityBlogDraft();
      expect(
        metadata.restore(
          CommunityTopicDraft(
            kind: 'community-write',
          ).restore(store.data!.content),
        ),
        contains('[img]https://example.invalid/image.png[/img]'),
      );
    },
  );

  for (final variant in [
    (width: 390.0, dark: false, scale: 1.0, name: 'phone'),
    (width: 390.0, dark: true, scale: 1.0, name: 'dark'),
    (width: 320.0, dark: false, scale: 1.8, name: 'large-text'),
    (width: 1100.0, dark: false, scale: 1.0, name: 'desktop'),
  ]) {
    testWidgets(
      'blog writing page ${variant.name} fits and keeps actions reachable',
      (tester) async {
        tester.view.physicalSize = Size(variant.width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final boundary = await _open(
          tester,
          dark: variant.dark,
          scale: variant.scale,
        );
        expect(find.byKey(const Key('blog-composer-page')), findsOneWidget);
        expect(find.byType(AlertDialog), findsNothing);
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('blog-publish')))
              .onPressed,
          isNull,
        );
        expect(tester.takeException(), isNull);
        await captureUx(tester, boundary, 'blog-composer-${variant.name}');
        await tester.ensureVisible(find.text('权限设置'));
        await tester.pumpAndSettle();
        expect(find.text('权限设置').hitTestable(), findsOneWidget);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('blog-composer-page')), findsNothing);
      },
    );
  }

  testWidgets(
    'blog preview and keyboard retain the body and publish exactly once',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final submitted = Completer<void>();
      var calls = 0;
      final store = _Drafts();
      final boundary = await _open(
        tester,
        store: store,
        submit: (title, body, token) async {
          calls++;
          expect(title, '在故事结束之后');
          expect(body, '[b]今天又发现了一部喜欢的作品。[/b]');
          expect(token, 'synthetic-token');
          await submitted.future;
        },
      );
      await tester.enterText(find.byKey(const Key('blog-title')), '在故事结束之后');
      await tester.enterText(
        find.byKey(const Key('blog-body')),
        '[b]今天又发现了一部喜欢的作品。[/b]',
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('预览正文'));
      await tester.tap(find.text('预览正文'));
      await tester.pumpAndSettle();
      expect(find.text('今天又发现了一部喜欢的作品。'), findsOneWidget);
      await tester.tap(find.text('继续编辑'));
      await tester.pumpAndSettle();
      await captureUx(tester, boundary, 'blog-composer-filled');
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const Key('blog-publish')).hitTestable(),
        findsOneWidget,
      );
      await captureUx(tester, boundary, 'blog-composer-keyboard');
      await tester.tap(find.byKey(const Key('blog-publish')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('blog-publish')));
      await tester.pump();
      expect(calls, 1);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '取消'))
            .onPressed,
        isNull,
      );
      submitted.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('blog-composer-page')), findsNothing);
      expect(store.data, isNull);
    },
  );

  testWidgets(
    'blog send error preserves text and account changes prevent submission',
    (tester) async {
      var calls = 0, current = true;
      final store = _Drafts();
      await _open(
        tester,
        store: store,
        isAccountCurrent: () => current,
        initialTitle: '草稿标题',
        initialContent: '保留正文',
        submit: (_, _, _) async {
          calls++;
          throw const CommunitySubmissionRejected('暂时无法发布');
        },
      );
      await tester.tap(find.byKey(const Key('blog-publish')));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.text('保留正文'), findsOneWidget);
      await tester.ensureVisible(find.text('暂时无法发布'));
      expect(find.text('暂时无法发布'), findsOneWidget);
      current = false;
      await tester.tap(find.byKey(const Key('blog-publish')));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.textContaining('登录账号已变化'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
    },
  );
}
