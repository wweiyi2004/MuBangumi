import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/storage/community_draft_store.dart';
import 'package:mubangumi/models/community_topic_submission.dart';
import 'package:mubangumi/state/community_submission_controller.dart';
import 'package:mubangumi/widgets/community_composer.dart';

class Drafts extends CommunityDraftRepository {
  CommunityDraftData? data;
  bool fail = false;
  @override
  Future<CommunityDraftData?> load(String key) async => data;
  @override
  Future<void> save(String key, CommunityDraftData value) async {
    if (fail) throw StateError('disk');
    data = value.content.isEmpty ? null : value;
  }
}

void main() {
  for (final kind in ['reply', 'group-topic', 'blog']) {
    for (final result in ['success', 'rejected', 'uncertain']) {
      testWidgets(
        '$kind leaves editor after durable handoff, preserving $result state',
        (tester) async {
          final store = Drafts();
          final gate = Completer<void>();
          CommunityPendingSubmission? entry;
          var sends = 0, tokens = 0;
          Future<void> open(BuildContext context) => showCommunityComposer(
            context,
            heading: '编辑',
            initialTitle: '标题',
            initialContent: '[b]正文[/b]',
            topicDraft: CommunityTopicDraft(kind: kind),
            blogDraft: kind == 'blog' ? CommunityBlogDraft(tags: ['标签']) : null,
            draftKey: 'alice/$kind',
            draftStore: store,
            isAccountCurrent: () => true,
            tokenProvider: (_) async {
              tokens++;
              return 'one-use-synthetic';
            },
            onAccepted: (value) => entry = value,
            onSubmit: (_, _, _) async {
              sends++;
              await gate.future;
            },
            confirmSubmission: (_, _, _) async => false,
          ).then((_) {});
          await tester.pumpWidget(
            MaterialApp(
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => open(context),
                    child: const Text('打开'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('打开'));
          await tester.pumpAndSettle();
          await tester.tap(find.text(kind == 'blog' ? '发送' : '发送').last);
          await tester.pumpAndSettle();
          expect(entry, isNotNull);
          expect(sends, 1);
          expect(tokens, 1);
          expect(find.text('编辑'), findsNothing);
          expect(entry!.status, CommunitySubmissionStatus.publishing);
          final restored = CommunityTopicDraft(kind: kind);
          final encodedBody = restored.restore(store.data!.content);
          expect(restored.pending, isTrue);
          expect(
            kind == 'blog'
                ? CommunityBlogDraft().restore(encodedBody)
                : encodedBody,
            '[b]正文[/b]',
          );
          if (result == 'success') {
            gate.complete();
          } else if (result == 'rejected') {
            gate.completeError(const CommunitySubmissionRejected('未被接受'));
          } else {
            gate.completeError(const CommunitySubmissionUncertain());
          }
          await tester.pumpAndSettle();
          expect(entry!.status, switch (result) {
            'success' => CommunitySubmissionStatus.sent,
            'rejected' => CommunitySubmissionStatus.failed,
            _ => CommunitySubmissionStatus.uncertain,
          });
          if (result == 'success') {
            expect(store.data, isNull);
          } else {
            restored.restore(store.data!.content);
            expect(restored.pending, result == 'uncertain');
            if (result == 'uncertain') {
              await tester.tap(find.text('打开'));
              await tester.pumpAndSettle();
              expect(find.text('核对发布结果'), findsWidgets);
              expect(sends, 1);
              expect(tokens, 1);
              await tester.pumpWidget(const SizedBox());
            }
          }
        },
      );
    }
  }
  test(
    'changed accounts never dispatch a queued verified attempt or expose its card',
    () async {
      var current = true, sends = 0;
      final registry = CommunitySubmissions();
      addTearDown(registry.dispose);
      final entry = CommunityPendingSubmission(
        title: '',
        content: '原账号正文',
        isAccountCurrent: () => current,
        send: () async {
          sends++;
        },
        finishDraft: (_) async {},
      );
      registry.add('target', entry);
      current = false;
      await entry.completion;
      expect(sends, 0);
      expect(registry.forScope('target'), isEmpty);
    },
  );
  testWidgets('failed local save cannot dispatch or close the editor', (
    tester,
  ) async {
    var sends = 0;
    final store = Drafts()..fail = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showCommunityComposer(
                context,
                heading: '编辑',
                initialContent: '正文',
                topicDraft: CommunityTopicDraft(kind: 'reply'),
                draftKey: 'alice/reply',
                draftStore: store,
                tokenProvider: (_) async => 'token',
                onAccepted: (_) {},
                onSubmit: (_, _, _) async {
                  sends++;
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
    expect(sends, 0);
    expect(find.text('编辑'), findsOneWidget);
    expect(find.text('草稿保存失败，请重试'), findsOneWidget);
  });
}
