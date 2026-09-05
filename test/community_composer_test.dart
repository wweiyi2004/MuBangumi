import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/widgets/community_composer.dart';

void main() {
  testWidgets(
    'draft survives closing and a failed send, then clears on success',
    (tester) async {
      final draft = CommunityDraft();
      var fail = true;
      var tokens = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showCommunityComposer(
                  context,
                  heading: '写回复',
                  draft: draft,
                  requireTitle: true,
                  tokenProvider: (_) async => 'token-${++tokens}',
                  onSubmit: (_, _, _) async {
                    if (fail) throw StateError('发送失败');
                  },
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, '标题'), '草稿标题');
      await tester.enterText(find.widgetWithText(TextField, '内容'), '未写完的回复');
      await tester.pump();
      await tester.tap(find.text('稍后再写'));
      await tester.pumpAndSettle();
      expect(draft.title, '草稿标题');
      expect(draft.content, '未写完的回复');
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      expect(find.text('未写完的回复'), findsOneWidget);
      await tester.tap(find.text('发送'));
      await tester.pumpAndSettle();
      expect(find.text('未写完的回复'), findsOneWidget);
      fail = false;
      await tester.tap(find.text('发送'));
      await tester.pumpAndSettle();
      expect(tokens, 2);
      expect(draft.title, isEmpty);
      expect(draft.content, isEmpty);
      expect(find.text('写回复'), findsNothing);
    },
  );
  testWidgets('submits an authenticated community reply with a fresh token', (
    tester,
  ) async {
    String? submittedContent;
    String? submittedToken;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showCommunityComposer(
                  context,
                  heading: '回复话题',
                  tokenProvider: (_) async => 'verified-turnstile-token',
                  onSubmit: (_, content, token) async {
                    submittedContent = content;
                    submittedToken = token;
                  },
                ),
                child: const Text('回复'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('回复'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '测试回复');
    await tester.pump();
    final sendButton = find.widgetWithText(FilledButton, '发送');
    expect(tester.widget<FilledButton>(sendButton).onPressed, isNotNull);
    await tester.tap(sendButton);
    await tester.pumpAndSettle();

    expect(submittedContent, '测试回复');
    expect(submittedToken, 'verified-turnstile-token');
    expect(find.text('请完成验证'), findsNothing);
    expect(find.text('回复话题'), findsNothing);
  });

  testWidgets('submits a group topic with title and content', (tester) async {
    String? submittedTitle;
    String? submittedContent;
    String? submittedToken;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showCommunityComposer(
                  context,
                  heading: '在「测试小组」发帖',
                  requireTitle: true,
                  tokenProvider: (_) async => 'verified-turnstile-token',
                  onSubmit: (title, content, token) async {
                    submittedTitle = title;
                    submittedContent = content;
                    submittedToken = token;
                  },
                ),
                child: const Text('发帖'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('发帖'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '标题'), '测试标题');
    await tester.enterText(find.widgetWithText(TextField, '内容'), '测试正文');
    await tester.pump();
    final sendButton = find.widgetWithText(FilledButton, '发送');
    expect(tester.widget<FilledButton>(sendButton).onPressed, isNotNull);
    await tester.tap(sendButton);
    await tester.pumpAndSettle();

    expect(submittedTitle, '测试标题');
    expect(submittedContent, '测试正文');
    expect(submittedToken, 'verified-turnstile-token');
    expect(find.text('在「测试小组」发帖'), findsNothing);
  });

  test('BBCode wraps selected text and keeps selection', () {
    final controller = TextEditingController(text: 'hello world')
      ..selection = const TextSelection(baseOffset: 6, extentOffset: 11);
    addTearDown(controller.dispose);

    applyBbCode(controller, tag: 'b');

    expect(controller.text, 'hello [b]world[/b]');
    expect(controller.selection.textInside(controller.text), 'world');
  });

  test('BBCode without selection leaves cursor inside tags', () {
    final controller = TextEditingController(text: 'hello')
      ..selection = const TextSelection.collapsed(offset: 5);
    addTearDown(controller.dispose);

    applyBbCode(controller, tag: 'url');

    expect(controller.text, 'hello[url][/url]');
    expect(controller.selection.baseOffset, 10);
  });
}
