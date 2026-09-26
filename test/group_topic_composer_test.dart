import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/storage/community_draft_store.dart';
import 'package:mubangumi/models/community_topic_submission.dart';
import 'package:mubangumi/widgets/community_composer.dart';

class Store extends CommunityDraftRepository {
  CommunityDraftData? value;
  bool fail = false;
  @override
  Future<CommunityDraftData?> load(String key) async => value;
  @override
  Future<void> save(String key, CommunityDraftData draft) async {
    if (fail) throw StateError('disk unavailable');
    value = draft.content.isEmpty ? null : draft;
  }
}

void main() {
  testWidgets(
    'legacy draft can find its existing post without publishing again',
    (tester) async {
      final store = Store()..value = (title: 'legacy', content: 'body');
      final result = Completer<bool>();
      var checks = 0, writes = 0;
      final draft = CommunityTopicDraft();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showCommunityComposer(
                  context,
                  heading: '历史草稿',
                  requireTitle: true,
                  topicDraft: draft,
                  draftKey: 'alice/group/demo',
                  draftStore: store,
                  onSubmit: (_, _, _) async {
                    writes++;
                  },
                  confirmSubmission: (title, content, attemptedAt) async {
                    checks++;
                    expect(attemptedAt, isNull);
                    expect(title, 'legacy');
                    expect(content, 'body');
                    final found = await result.future;
                    if (found) draft.confirmedId = 42;
                    return found;
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
      await tester.tap(find.text('核对是否已发布（最近 24 小时）'));
      await tester.pump();
      expect(find.text('正在核对…'), findsOneWidget);
      expect(writes, 0);
      result.complete(true);
      await tester.pumpAndSettle();
      expect(checks, 1);
      expect(writes, 0);
      expect(find.text('历史草稿'), findsNothing);
      expect(store.value, isNull);
    },
  );
  testWidgets(
    'unknown publication survives closing and can only be checked, not resent',
    (tester) async {
      final store = Store();
      var writes = 0, checks = 0;
      var found = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () {
                  final draft = CommunityTopicDraft();
                  showCommunityComposer(
                    context,
                    heading: '发布帖子',
                    requireTitle: true,
                    draftKey: 'alice/group/demo',
                    draftStore: store,
                    topicDraft: draft,
                    tokenProvider: (_) async => 'once',
                    onSubmit: (title, content, token) async {
                      writes++;
                      final persisted = CommunityTopicDraft()
                        ..restore(store.value!.content);
                      expect(
                        persisted.pending,
                        true,
                        reason: 'Persist intent before dispatching.',
                      );
                      throw const CommunitySubmissionUncertain();
                    },
                    confirmSubmission: (title, content, attemptedAt) async {
                      checks++;
                      expect(title, 'title');
                      expect(content, 'body');
                      if (found) draft.confirmedId = 42;
                      return found;
                    },
                  );
                },
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, '标题'), 'title');
      await tester.enterText(find.widgetWithText(TextField, '内容'), 'body');
      await tester.pump();
      await tester.tap(find.text('发送'));
      await tester.pumpAndSettle();
      expect(writes, 1);
      expect(find.text('核对发布结果'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.widgetWithText(TextField, '标题')).enabled,
        false,
      );
      await tester.tap(find.text('保留并关闭'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      expect(find.text('核对发布结果'), findsOneWidget);
      expect(find.text('发送'), findsNothing);
      await tester.tap(find.text('核对发布结果'));
      await tester.pumpAndSettle();
      expect(find.textContaining('这不代表发布失败'), findsOneWidget);
      expect(writes, 1);
      expect(checks, 1);
      expect(store.value, isNotNull);
      found = true;
      await tester.tap(find.text('核对发布结果'));
      await tester.pumpAndSettle();
      expect(find.text('发布帖子'), findsNothing);
      expect(writes, 1);
      expect(checks, 2);
      expect(store.value, isNull);
    },
  );

  testWidgets('explicit server rejection keeps draft editable for correction', (
    tester,
  ) async {
    final store = Store();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showCommunityComposer(
                context,
                heading: '发布帖子',
                requireTitle: true,
                initialTitle: 'title',
                initialContent: 'body',
                draftKey: 'alice/group/demo',
                draftStore: store,
                topicDraft: CommunityTopicDraft(),
                tokenProvider: (_) async => 'once',
                onSubmit: (_, _, _) async =>
                    throw const CommunitySubmissionRejected('标题不合法'),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();
    expect(find.text('标题不合法'), findsOneWidget);
    expect(find.text('核对发布结果'), findsNothing);
    expect(
      tester.widget<TextField>(find.widgetWithText(TextField, '标题')).enabled,
      true,
    );
    final restored = CommunityTopicDraft()..restore(store.value!.content);
    expect(restored.pending, false);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('storage failure before dispatch sends no post', (tester) async {
    var writes = 0;
    final store = Store()..fail = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showCommunityComposer(
                context,
                heading: '发布帖子',
                requireTitle: true,
                initialTitle: 'title',
                initialContent: 'body',
                draftKey: 'alice/group/demo',
                draftStore: store,
                topicDraft: CommunityTopicDraft(),
                tokenProvider: (_) async => 'once',
                onSubmit: (_, _, _) async {
                  writes++;
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
    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();
    expect(writes, 0);
    expect(find.text('草稿保存失败，请重试'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
