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
      await tester.tap(find.text('加载更多'));
      await tester.pumpAndSettle();
      expect(find.text('收件2'), findsOneWidget);
      expect(service.inboxPages, [1, 2]);
      await tester.tap(find.text('已发送'));
      await tester.pumpAndSettle();
      expect(find.text('旧发件'), findsOneWidget);
      expect(service.outboxPages, [1]);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      service.sent = true;
      Navigator.of(tester.element(find.byType(PmComposeScreen))).pop(true);
      await tester.pumpAndSettle();
      expect(find.text('新发件'), findsOneWidget);
      expect(find.text('旧发件'), findsNothing);
      expect(service.outboxPages, [1, 1]);
      expect(service.inboxPages, [1, 2, 1]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'outbox errors do not replace inbox and refresh retains visible items',
    (tester) async {
      final service = _Service()..outboxFails = true;
      await _show(tester, service);
      await tester.tap(find.text('已发送'));
      await tester.pumpAndSettle();
      expect(find.text('加载失败'), findsOneWidget);
      await tester.tap(find.text('收件箱'));
      await tester.pumpAndSettle();
      expect(find.text('收件1'), findsOneWidget);
      expect(find.text('加载失败'), findsNothing);
      service.inboxFails = true;
      await tester.tap(find.byTooltip('刷新'));
      await tester.pumpAndSettle();
      expect(find.text('收件1'), findsOneWidget);
      expect(find.text('刷新失败，已保留当前内容'), findsOneWidget);
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
      expect(find.text('收件1'), findsOneWidget);
    },
  );
}

Future<ProviderContainer> _show(
  WidgetTester tester,
  _Service service, {
  _SessionStore? store,
  bool settle = true,
}) async {
  final container = ProviderContainer(
    overrides: [
      websiteSessionStoreProvider.overrideWithValue(store ?? _SessionStore()),
    ],
  );
  addTearDown(container.dispose);
  await container.read(websiteSessionProvider.notifier).reload();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: PmPage(service: service)),
    ),
  );
  if (settle) await tester.pumpAndSettle();
  return container;
}

class _SessionStore extends WebsiteSessionStore {
  String cookie = 'account';
  @override
  Future<WebsiteSessionSnapshot?> read() async => WebsiteSessionSnapshot(
    cookies: [WebsiteCookie(name: 'chii_auth', value: cookie)],
    syncedAt: DateTime(2026),
  );
}

class _Service extends PmService {
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
