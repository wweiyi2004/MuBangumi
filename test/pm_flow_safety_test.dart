import 'package:mubangumi/navigation/app_destination.dart';
import 'package:mubangumi/navigation/app_router.dart';
import 'support/memory_pm_draft_repository.dart';
import 'support/pm_fixtures.dart';
import 'package:mubangumi/core/storage/pm_draft_store.dart';
import 'package:mubangumi/state/session_controller.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/auth/website_session.dart';
import 'package:mubangumi/core/network/pm_service.dart';
import 'package:mubangumi/models/pm_models.dart';
import 'package:mubangumi/screens/pm_page.dart';
import 'package:mubangumi/state/website_session_controller.dart';

void main() {
  testWidgets(
    'clearing a confirmed recipient never sends to the old recipient',
    (tester) async {
      final service = _Service();
      await _show(tester, PmComposeScreen(toUser: 'alice', service: service));
      await tester.enterText(find.byType(TextField).at(0), '   ');
      await _fillAndSend(tester);
      expect(service.sentTo, isEmpty);
      expect(find.text('请填写对方用户名或 UID'), findsOneWidget);
    },
  );

  testWidgets('rapid send taps share validation and send only one message', (
    tester,
  ) async {
    final pending = Completer<PmComposeParams>();
    final service = _Service()..pendingAlice = pending.future;
    await _show(tester, PmComposeScreen(service: service));
    await tester.enterText(find.byType(TextField).at(0), 'alice');
    await tester.enterText(find.byType(TextField).at(1), 'title');
    await tester.enterText(find.byType(TextField).at(2), 'body');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('发送短信'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('发送短信'));
    await tester.tap(find.text('发送短信'));
    await tester.pump();
    expect(service.validatedRecipients, ['alice']);
    expect(service.sentTo, isEmpty);
    pending.complete(
      const PmComposeParams(formhash: 'hash', msgReceivers: 'alice'),
    );
    await tester.pumpAndSettle();
    expect(service.sentTo, ['alice']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editing a confirmed recipient sends to the new recipient', (
    tester,
  ) async {
    final service = _Service();
    await _show(tester, PmComposeScreen(toUser: 'alice', service: service));
    await tester.enterText(find.byType(TextField).at(0), 'bob');
    await _fillAndSend(tester);
    expect(service.sentTo, ['bob']);
  });

  testWidgets(
    'late recipient validation cannot confirm a different recipient',
    (tester) async {
      final pending = Completer<PmComposeParams>();
      final service = _Service()..pendingAlice = pending.future;
      await _show(
        tester,
        PmComposeScreen(toUser: 'alice', service: service),
        settle: false,
      );
      await tester.enterText(find.byType(TextField).at(0), 'bob');
      pending.complete(
        const PmComposeParams(formhash: 'hash', msgReceivers: 'alice'),
      );
      await tester.pumpAndSettle();
      await _fillAndSend(tester);
      expect(service.sentTo, ['bob']);
    },
  );

  testWidgets(
    'reply completion after leaving the page does not access disposed state',
    (tester) async {
      final pending = Completer<void>();
      final service = _Service()..pendingReply = pending.future;
      await _show(
        tester,
        PmConversationScreen(
          conversationId: '1',
          title: 'chat',
          service: service,
        ),
      );
      await tester.enterText(find.byType(TextField), 'reply');
      await tester.pump();
      await tester.tap(find.text('发送'));
      await tester.pump();
      expect(service.replyCalls, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      pending.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(service.conversationLoads, 1);
    },
  );

  testWidgets(
    'a failed thread change cannot send using the previous thread form',
    (tester) async {
      final service = _Service();
      await _show(
        tester,
        PmConversationScreen(
          conversationId: '1',
          title: 'chat',
          service: service,
        ),
      );
      await tester.enterText(find.byType(TextField), 'reply');
      await tester.tap(find.text('Thread B'));
      await tester.pumpAndSettle();
      final send = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '发送'),
      );
      expect(send.onPressed, isNull);
      expect(find.textContaining('thread failed'), findsOneWidget);
    },
  );

  testWidgets('website account change clears an open conversation', (
    tester,
  ) async {
    final store = _Store();
    final service = _Service();
    final container = await _show(
      tester,
      PmConversationScreen(
        conversationId: '1',
        title: 'chat',
        service: service,
      ),
      store: store,
    );
    expect(find.text('private message A'), findsOneWidget);
    store.account = 'account-b';
    store.verifiedUserId = 2;
    await container.read(websiteSessionProvider.notifier).reload();
    await tester.pumpAndSettle();
    expect(find.text('private message A'), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets(
    'account change invalidates an in-flight compose validation and draft',
    (tester) async {
      final pending = Completer<PmComposeParams>();
      final store = _Store();
      final service = _Service()..pendingAlice = pending.future;
      final container = await _show(
        tester,
        PmComposeScreen(toUser: 'alice', service: service),
        store: store,
        settle: false,
      );
      await tester.enterText(find.byType(TextField).at(1), 'private draft');
      store.account = 'account-b';
      store.verifiedUserId = 2;
      await container.read(websiteSessionProvider.notifier).reload();
      pending.complete(
        const PmComposeParams(formhash: 'old', msgReceivers: 'alice'),
      );
      await tester.pumpAndSettle();
      for (final field in tester.widgetList<TextField>(
        find.byType(TextField),
      )) {
        expect(field.controller!.text, isEmpty);
        expect(field.enabled, isFalse);
      }
      expect(find.text('收件人已确认，可以发送'), findsNothing);
      expect(service.sentTo, isEmpty);
    },
  );

  testWidgets(
    'renewing a challenge cookie keeps a same-session private draft',
    (tester) async {
      final store = _Store();
      final container = await _show(
        tester,
        PmConversationScreen(
          conversationId: '1',
          title: 'chat',
          service: _Service(),
        ),
        store: store,
      );
      await tester.enterText(find.byType(TextField), 'keep draft');
      store.challenge = 'refreshed';
      await container.read(websiteSessionProvider.notifier).reload();
      await tester.pumpAndSettle();
      expect(find.text('private message A'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'keep draft',
      );
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
    },
  );

  testWidgets(
    'confirmed recipient status fits a narrow screen with large fonts',
    (tester) async {
      tester.view.physicalSize = const Size(320, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _show(
        tester,
        PmComposeScreen(toUser: 'alice', service: _Service()),
        scale: 1.8,
      );
      await tester.ensureVisible(find.text('收件人已确认，可以发送'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _fillAndSend(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).at(1), 'title');
  await tester.enterText(find.byType(TextField).at(2), 'body');
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('发送短信'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('发送短信'));
  await tester.pumpAndSettle();
}

Future<ProviderContainer> _show(
  WidgetTester tester,
  Widget page, {
  _Store? store,
  bool settle = true,
  double scale = 1,
}) async {
  final websiteStore = store ?? _Store();
  if (page is PmComposeScreen) {
    (page.service as _Service).websiteStore = websiteStore;
  }
  if (page is PmConversationScreen) {
    (page.service as _Service).websiteStore = websiteStore;
  }
  final container = ProviderContainer(
    overrides: [
      sessionProvider.overrideWith((ref) => PmTestSession()),
      pmDraftRepositoryProvider.overrideWithValue(MemoryPmDraftRepository()),
      websiteSessionStoreProvider.overrideWithValue(websiteStore),
    ],
  );
  addTearDown(container.dispose);
  await container.read(websiteSessionProvider.notifier).reload();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: AppRouteScope(
        resolve: AppRouter.resolve,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute<void>(builder: (_) => page)),
                child: const Text('open test route'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open test route'));
  await tester.pump();
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
  return container;
}

class _Store extends PmTestWebsiteStore {}

class _Service extends PmService {
  late WebsiteSessionStore websiteStore;
  @override
  Future<({int userId, String authenticationKey})> verifyDraftOwner(user) =>
      PmService(sessionStore: websiteStore).verifyDraftOwner(user);
  Future<PmComposeParams>? pendingAlice;
  Future<void>? pendingReply;
  final sentTo = <String>[];
  final validatedRecipients = <String>[];
  int replyCalls = 0;
  int conversationLoads = 0;
  @override
  Future<PmComposeParams> loadComposeParams(String user) async {
    validatedRecipients.add(user);
    if (user == 'alice' && pendingAlice != null) return pendingAlice!;
    return PmComposeParams(formhash: 'hash', msgReceivers: user);
  }

  @override
  Future<void> compose({
    required PmComposeParams params,
    required String title,
    required String body,
  }) async {
    sentTo.add(params.msgReceivers);
  }

  @override
  Future<void> reply({
    required PmReplyForm form,
    required String body,
    String? title,
  }) async {
    replyCalls++;
    await pendingReply;
  }

  @override
  Future<PmConversationDetail> loadConversation(
    String id, {
    String? threadId,
  }) async {
    conversationLoads++;
    if (threadId == 'b') throw const PmException('thread failed');
    return const PmConversationDetail(
      messages: [
        PmMessage(
          name: 'Alice',
          userId: 'alice',
          contentHtml: 'private message A',
          timeText: '',
        ),
      ],
      form: PmReplyForm(formhash: 'hash', msgReceivers: 'alice', related: 'a'),
      threads: [
        PmThreadFilter(id: 'a', title: 'Thread A', current: true),
        PmThreadFilter(id: 'b', title: 'Thread B'),
      ],
    );
  }
}
