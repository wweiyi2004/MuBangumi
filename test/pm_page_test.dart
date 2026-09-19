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
    'mailboxes paginate independently and send completion refreshes outbox',
    (tester) async {
      final service = _Service();
      await _show(tester, service);
      expect(find.text('收件1'), findsOneWidget);
      expect(find.text('收件2'), findsOneWidget);
      expect(service.inboxPages, [1, 2, 3]);
      expect(find.text('旧发件'), findsOneWidget);
      expect(service.outboxPages, [1, 2]);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), 'alice');
      await tester.enterText(find.byType(TextField).at(1), 'title');
      await tester.enterText(find.byType(TextField).at(2), 'message');
      await tester.ensureVisible(find.text('发送短信'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('发送短信'));
      await tester.pumpAndSettle();
      expect(find.text('新发件'), findsOneWidget);
      expect(find.text('旧发件'), findsNothing);
      expect(service.outboxPages, [1, 2, 1, 2]);
      expect(service.inboxPages, [1, 2, 3, 1, 2, 3]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'outbox errors do not replace inbox and refresh retains visible items',
    (tester) async {
      final service = _Service()..outboxFails = true;
      await _show(tester, service);
      expect(find.text('私信记录加载失败，已保留当前列表'), findsOneWidget);
      expect(find.text('收件1'), findsOneWidget);
      expect(find.text('加载失败'), findsNothing);
      service.inboxFails = true;
      await tester.tap(find.byTooltip('刷新'));
      await tester.pumpAndSettle();
      expect(find.text('收件1'), findsOneWidget);
      expect(find.text('私信记录加载失败，已保留当前列表'), findsOneWidget);
    },
  );

  testWidgets(
    'website session replacement clears mailboxes and rejects old responses',
    (tester) async {
      final pending = Completer<List<PmConversation>>();
      final service = _Service()..pendingInbox = pending.future;
      final store = _SessionStore();
      final container = await _show(
        tester,
        service,
        store: store,
        settle: false,
      );
      await tester.pump();
      service.pendingInbox = null;
      service.sent = true;
      store.cookie = 'new-account';
      await container.read(websiteSessionProvider.notifier).reload();
      await tester.pumpAndSettle();
      pending.complete([_item('old-account-private')]);
      await tester.pumpAndSettle();
      expect(find.text('old-account-private'), findsNothing);
      // A replacement Cookie is not usable until its owner is verified.
      expect(find.text('收件1'), findsNothing);
      expect(find.textContaining('需要补充账号验证'), findsOneWidget);
    },
  );
}

Future<ProviderContainer> _show(
  WidgetTester tester,
  _Service service, {
  _SessionStore? store,
  bool settle = true,
}) async {
  final websiteStore = store ?? _SessionStore();
  service.websiteStore = websiteStore;
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
          home: PmPage(service: service, friendsLoader: (_) async => []),
        ),
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
  return container;
}

class _SessionStore extends PmTestWebsiteStore {
  set cookie(String value) => account = value;
}

class _Service extends PmService {
  late WebsiteSessionStore websiteStore;
  @override
  Future<({int userId, String authenticationKey})> verifyDraftOwner(user) =>
      PmService(sessionStore: websiteStore).verifyDraftOwner(user);
  @override
  Future<PmComposeParams> loadComposeParams(String user) async =>
      PmComposeParams(formhash: 'hash', msgReceivers: user);
  @override
  Future<void> compose({
    required PmComposeParams params,
    required String title,
    required String body,
  }) async {
    sent = true;
  }

  final inboxPages = <int>[];
  final outboxPages = <int>[];
  bool sent = false;
  bool inboxFails = false;
  bool outboxFails = false;
  Future<List<PmConversation>>? pendingInbox;

  @override
  Future<List<PmConversation>> loadInbox({int page = 1}) async {
    inboxPages.add(page);
    if (pendingInbox != null) return pendingInbox!;
    if (inboxFails) throw StateError('offline');
    return page <= 2 ? [_item('收件$page')] : [];
  }

  @override
  Future<List<PmConversation>> loadOutbox({int page = 1}) async {
    outboxPages.add(page);
    if (outboxFails) throw StateError('offline');
    return [_item(sent ? '新发件' : '旧发件')];
  }
}

PmConversation _item(String title) => PmConversation(
  id: title,
  title: title,
  preview: '',
  peerName: '测试用户',
  peerUserId: '',
);
