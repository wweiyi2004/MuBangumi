import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/widgets/community_composer.dart';

void main() {
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
