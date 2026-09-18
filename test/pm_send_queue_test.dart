import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/storage/pm_draft_store.dart';
import 'package:mubangumi/core/network/pm_service.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/models/pm_models.dart';
import 'package:mubangumi/models/pm_send_command.dart';
import 'package:mubangumi/state/pm_draft_controller.dart';
import 'package:mubangumi/state/pm_send_queue_controller.dart';
import 'package:mubangumi/state/session_controller.dart';
import 'package:mubangumi/state/website_session_controller.dart';
import 'package:mubangumi/screens/pm_page.dart';
import 'support/memory_pm_outbox_repository.dart';
import 'support/pm_fixtures.dart';

const alice = BangumiUser(
  id: 1,
  username: 'alice',
  nickname: '我',
  avatarUrl: '',
);
const bob = BangumiUser(
  id: 2,
  username: 'bob',
  nickname: '另一个账号',
  avatarUrl: '',
);
Future<PmDraftController> draft(
  MemoryPmOutboxRepository repo,
  String body, {
  String id = 'draft',
}) async {
  final controller = PmDraftController(
    repo,
    PmDraft(
      id: id,
      ownerId: 1,
      kind: PmDraftKind.reply,
      recipient: '42',
      body: body,
      conversationId: 'chat',
      threadId: 'topic',
    ),
  );
  await controller.restore();
  return controller;
}

Future<void> until(bool Function() condition) async {
  for (var i = 0; i < 200 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  expect(condition(), isTrue);
}

void main() {
  test(
    'a changed receiver is rejected before POST and is not automatically retried',
    () async {
      final repo = MemoryPmOutboxRepository();
      final service = _Service()..receiverOverride = '99';
      final queue = PmSendQueueController(
        repository: repo,
        service: service,
        currentUser: () => alice,
      );
      final editor = await draft(repo, '只发给原收件人');
      addTearDown(queue.dispose);
      addTearDown(editor.dispose);
      final command = (await queue.enqueue(
        editor,
        receiver: '42',
        related: 'topic',
      ))!;
      await until(
        () => repo.commands[command.id]!.status == PmSendStatus.failed,
      );
      await queue.resumeWaiting();
      expect(service.calls, isEmpty);
      expect(repo.commands[command.id]!.body, '只发给原收件人');
    },
  );
  test(
    'enqueue acknowledges locally, preserves FIFO and permits the next draft while POST waits',
    () async {
      final repo = MemoryPmOutboxRepository();
      final service = _Service()..gate = Completer<void>();
      final queue = PmSendQueueController(
        repository: repo,
        service: service,
        currentUser: () => alice,
      );
      final editor = await draft(repo, '第一条');
      addTearDown(queue.dispose);
      addTearDown(editor.dispose);
      final first = await queue.enqueue(
        editor,
        receiver: '42',
        related: 'topic',
      );
      expect(first, isNotNull);
      expect(editor.data.body, isEmpty);
      await until(() => service.calls.length == 1);
      editor.edit(recipient: '42', title: '', body: '第二条');
      final second = await queue.enqueue(
        editor,
        receiver: '42',
        related: 'topic',
      );
      expect(second, isNotNull);
      expect(service.calls, ['第一条']);
      service.gate!.complete();
      await until(
        () => repo.commands.values.every((e) => e.status == PmSendStatus.sent),
      );
      expect(service.calls, ['第一条', '第二条']);
    },
  );

  test(
    'queue write failure keeps the draft and never calls the network',
    () async {
      final repo = MemoryPmOutboxRepository()..failSave = true;
      final service = _Service();
      final queue = PmSendQueueController(
        repository: repo,
        service: service,
        currentUser: () => alice,
      );
      final editor = await draft(repo, '保留输入');
      addTearDown(queue.dispose);
      addTearDown(editor.dispose);
      expect(
        await queue.enqueue(editor, receiver: '42', related: 'topic'),
        isNull,
      );
      expect(editor.data.body, '保留输入');
      expect(repo.commands, isEmpty);
      expect(service.calls, isEmpty);
    },
  );

  test('typing during a delayed local commit is not erased', () async {
    final repo = MemoryPmOutboxRepository();
    final gate = Completer<void>();
    repo.enqueueGate = gate.future;
    final editor = await draft(repo, '已点击发送的内容');
    final operation = editor.enqueue(receiver: '42', related: 'topic');
    editor.edit(recipient: '42', title: '', body: '后来输入的内容');
    gate.complete();
    await operation;
    expect(repo.commands.values.single.body, '已点击发送的内容');
    expect(editor.data.body, '后来输入的内容');
    await editor.flush();
    editor.dispose();
    expect((await repo.read(1, 'draft')).draft!.body, '后来输入的内容');
  });

  test(
    'an uncertain POST is not retried and blocks later messages to that recipient',
    () async {
      final repo = MemoryPmOutboxRepository();
      final service = _Service()..uncertain = true;
      final queue = PmSendQueueController(
        repository: repo,
        service: service,
        currentUser: () => alice,
      );
      final first = await draft(repo, '第一条', id: 'one');
      final second = await draft(repo, '第二条', id: 'two');
      addTearDown(queue.dispose);
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      final command = (await queue.enqueue(
        first,
        receiver: '42',
        related: 'topic',
      ))!;
      await queue.enqueue(second, receiver: '42', related: 'topic');
      await until(
        () => repo.commands[command.id]!.status == PmSendStatus.uncertain,
      );
      await queue.resumeWaiting();
      queue.wake();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(service.calls, ['第一条']);
      service.delivered.add('第一条');
      service.uncertain = false;
      expect(await queue.check(repo.commands[command.id]!), isTrue);
      await until(() => service.calls.length == 2);
      expect(service.calls, ['第一条', '第二条']);
    },
  );

  test(
    'switching accounts during preflight prevents POST and preserves the old owner task',
    () async {
      final repo = MemoryPmOutboxRepository();
      final service = _Service()..verifyGate = Completer<void>();
      BangumiUser? owner = alice;
      final queue = PmSendQueueController(
        repository: repo,
        service: service,
        currentUser: () => owner,
      );
      final editor = await draft(repo, '旧账号的内容');
      addTearDown(queue.dispose);
      addTearDown(editor.dispose);
      final command = (await queue.enqueue(
        editor,
        receiver: '42',
        related: 'topic',
      ))!;
      await until(() => service.verifications > 0);
      owner = bob;
      queue.accountChanged();
      service.verifyGate!.complete();
      await until(
        () => repo.commands[command.id]!.status == PmSendStatus.queued,
      );
      expect(service.calls, isEmpty);
      expect(queue.entries, isEmpty);
    },
  );

  testWidgets(
    'input clears on local enqueue and stays usable while network is pending',
    (tester) async {
      final repo = MemoryPmOutboxRepository();
      final service = _Service()..gate = Completer<void>();
      final container = ProviderContainer(
        overrides: [
          sessionProvider.overrideWith((ref) => PmTestSession()),
          websiteSessionStoreProvider.overrideWithValue(PmTestWebsiteStore()),
          pmDraftRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);
      await container.read(websiteSessionProvider.notifier).reload();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: PmConversationScreen(
              conversationId: 'chat',
              title: '私聊',
              service: service,
              peerName: '好友',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final input = find.widgetWithText(TextField, '输入回复…');
      await tester.enterText(input, '第一条');
      await tester.pump();
      await tester.tap(find.text('发送'));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(service.calls, ['第一条']);
      expect(tester.widget<TextField>(input).controller!.text, isEmpty);
      expect(tester.widget<TextField>(input).enabled, isTrue);
      await tester.enterText(input, '第二条还在编辑');
      await tester.pump();
      expect(tester.widget<TextField>(input).controller!.text, '第二条还在编辑');
      expect(find.text('发送中'), findsOneWidget);
      service.gate!.complete();
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(input).controller!.text, '第二条还在编辑');
      expect(service.calls, ['第一条']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'new private message closes after durable enqueue while POST continues in the background',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repo = MemoryPmOutboxRepository();
      final service = _Service()..gate = Completer<void>();
      final container = ProviderContainer(
        overrides: [
          sessionProvider.overrideWith((ref) => PmTestSession()),
          websiteSessionStoreProvider.overrideWithValue(PmTestWebsiteStore()),
          pmDraftRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);
      await container.read(websiteSessionProvider.notifier).reload();
      bool? accepted;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    accepted = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) =>
                            PmComposeScreen(service: service, toUser: 'friend'),
                      ),
                    );
                  },
                  child: const Text('写私信'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('写私信'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(1), '标题');
      await tester.enterText(find.byType(TextField).at(2), '新私信正文');
      await tester.ensureVisible(find.text('发送短信'));
      await tester.pump();
      await tester.tap(find.text('发送短信'));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 40));
      }
      expect(accepted, isTrue);
      await tester.pumpAndSettle();
      expect(find.byType(PmComposeScreen), findsNothing);
      expect(service.calls, ['新私信正文']);
      expect(repo.commands.values.single.status, PmSendStatus.sending);
      service.gate!.complete();
      await tester.pumpAndSettle();
      expect(repo.commands.values.single.status, PmSendStatus.sent);
      expect(service.calls, hasLength(1));
    },
  );

  testWidgets(
    'switching contacts while a queued POST waits keeps its original target',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repo = MemoryPmOutboxRepository();
      final service = _Service()..gate = Completer<void>();
      final container = ProviderContainer(
        overrides: [
          sessionProvider.overrideWith((ref) => PmTestSession()),
          websiteSessionStoreProvider.overrideWithValue(PmTestWebsiteStore()),
          pmDraftRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);
      await container.read(websiteSessionProvider.notifier).reload();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: PmPage(service: service, friendsLoader: (_) async => []),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('和好友甲聊天'));
      await tester.pumpAndSettle();
      final input = find.widgetWithText(TextField, '输入回复…');
      await tester.enterText(input, '发给甲的消息');
      await tester.pump();
      await tester.tap(find.text('发送'));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      await tester.tap(find.text('和好友乙聊天'));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(
        tester
            .widget<PmConversationScreen>(find.byType(PmConversationScreen))
            .conversationId,
        'other',
      );
      await tester.enterText(input, '给乙的草稿');
      service.gate!.complete();
      await tester.pumpAndSettle();
      expect(service.repliesTo, ['42']);
      expect(tester.widget<TextField>(input).controller!.text, '给乙的草稿');
      expect(repo.commands.values.single.status, PmSendStatus.sent);
    },
  );
}

class _Service extends PmService {
  String? receiverOverride;
  Completer<void>? gate, verifyGate;
  bool uncertain = false;
  int verifications = 0;
  final calls = <String>[];
  final delivered = <String>[];
  final repliesTo = <String>[];
  @override
  Future<List<PmConversation>> loadInbox({int page = 1}) async => page > 1
      ? []
      : const [
          PmConversation(
            id: 'chat',
            title: '和好友甲聊天',
            preview: '',
            peerName: '好友甲',
            peerUserId: '42',
          ),
          PmConversation(
            id: 'other',
            title: '和好友乙聊天',
            preview: '',
            peerName: '好友乙',
            peerUserId: '99',
          ),
        ];
  @override
  Future<List<PmConversation>> loadOutbox({int page = 1}) async => [];
  @override
  Future<PmComposeParams> loadComposeParams(String receiver) async =>
      const PmComposeParams(formhash: 'fresh', msgReceivers: '42');
  @override
  Future<void> compose({
    required PmComposeParams params,
    required String title,
    required String body,
  }) async {
    calls.add(body);
    await gate?.future;
    if (uncertain) throw const PmDeliveryUncertain();
    delivered.add(body);
  }

  @override
  Future<({int userId, String authenticationKey})> verifyDraftOwner(
    BangumiUser user,
  ) async {
    verifications++;
    await verifyGate?.future;
    final snapshot = await PmTestWebsiteStore().read();
    return (userId: user.id, authenticationKey: snapshot!.authenticationKey);
  }

  @override
  Future<PmConversationDetail> loadConversation(
    String id, {
    String? threadId,
  }) async => PmConversationDetail(
    peerName: '好友',
    peerUserId: id == 'other' ? '99' : '42',
    form: PmReplyForm(
      formhash: 'fresh',
      msgReceivers: receiverOverride ?? (id == 'other' ? '99' : '42'),
      related: 'topic',
    ),
    messages: [
      for (final body in delivered)
        PmMessage(
          name: '我',
          userId: '1',
          contentHtml: body,
          timeText: '',
          isSelf: true,
        ),
    ],
  );
  @override
  Future<void> reply({
    required PmReplyForm form,
    required String body,
    String? title,
  }) async {
    repliesTo.add(form.msgReceivers);
    calls.add(body);
    await gate?.future;
    if (uncertain) throw const PmDeliveryUncertain();
    delivered.add(body);
  }
}
