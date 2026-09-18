import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/network/pm_service.dart';
import 'package:mubangumi/core/storage/pm_draft_store.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/models/pm_contact.dart';
import 'package:mubangumi/models/pm_models.dart';
import 'package:mubangumi/screens/pm_page.dart';
import 'package:mubangumi/state/pm_contacts_controller.dart';
import 'package:mubangumi/state/pm_mailbox_controller.dart';
import 'package:mubangumi/state/session_controller.dart';
import 'package:mubangumi/state/website_session_controller.dart';
import 'support/pm_fixtures.dart';
import 'support/memory_pm_draft_repository.dart';

const alice = BangumiUser(
  id: 42,
  username: 'alice',
  nickname: '好友甲',
  avatarUrl: '',
);
const quiet = BangumiUser(
  id: 43,
  username: 'quiet_friend',
  nickname: '未聊过好友',
  avatarUrl: '',
);
PmConversation row(
  String id,
  String peer, {
  bool unread = false,
  String date = '2026-9-17',
}) => PmConversation(
  id: id,
  title: '会话$id',
  preview: '会话$id',
  peerName: '历史名字',
  peerUserId: peer,
  timeText: date,
  isUnread: unread,
);

void main() {
  test(
    'all friends remain visible, and UID and username histories share one contact',
    () {
      final people = mergePmContacts(
        [alice, quiet],
        [
          row('a', '42', unread: true),
          row('b', 'alice', date: '2026-9-18'),
          row('b', '42'),
        ],
      );
      expect(people, hasLength(2));
      expect(people.first.name, '好友甲');
      expect(people.first.conversations.map((r) => r.id), ['b', 'a']);
      expect(people.first.isUnread, isTrue);
      expect(people.last.latest, isNull);
      expect(people.last.matches('QUIET_FRIEND'), isTrue);
      expect(people.last.matches('未聊过'), isTrue);
    },
  );

  test(
    'equal nicknames and unidentified conversations never merge identities',
    () {
      const namesake = BangumiUser(
        id: 99,
        username: 'namesake',
        nickname: '好友甲',
        avatarUrl: '',
      );
      final people = mergePmContacts(
        [alice, namesake],
        [row('unknown', ''), row('stranger', '100')],
      );
      expect(people, hasLength(4));
      expect(people.where((r) => r.isFriend), hasLength(2));
      expect(people.where((r) => !r.isFriend), hasLength(2));
    },
  );

  test(
    'duplicate inbound and outbound rows keep unread and the newest preview',
    () {
      final people = mergePmContacts(
        [alice],
        [row('same', '42', unread: true), row('same', '42', date: '2026-9-18')],
      );
      expect(people.single.conversations, hasLength(1));
      expect(people.single.isUnread, isTrue);
      expect(people.single.latest!.timeText, '2026-9-18');
    },
  );

  test(
    'both mailboxes automatically page while the friend list is independent',
    () async {
      final incoming = <int>[], outgoing = <int>[];
      final inbox = PmMailboxController(({page = 1}) async {
        incoming.add(page);
        return page < 3 ? [row('in$page', '42')] : [];
      });
      final outbox = PmMailboxController(({page = 1}) async {
        outgoing.add(page);
        return page == 1 ? [row('out', '42')] : [];
      });
      final contacts = PmContactsController(
        inbox: inbox,
        outbox: outbox,
        loadFriends: () async => [alice, quiet],
      );
      await contacts.refresh();
      expect(incoming, [1, 2, 3]);
      expect(outgoing, [1, 2]);
      expect(contacts.items, hasLength(2));
      expect(contacts.items.first.conversations, hasLength(3));
      expect(contacts.historyIncomplete, isFalse);
      contacts.dispose();
      inbox.dispose();
      outbox.dispose();
    },
  );

  test(
    'late friends and private records cannot restore a signed-out account',
    () async {
      final friends = Completer<List<BangumiUser>>();
      final messages = Completer<List<PmConversation>>();
      final inbox = PmMailboxController(({page = 1}) => messages.future);
      final outbox = PmMailboxController(({page = 1}) async => []);
      final contacts = PmContactsController(
        inbox: inbox,
        outbox: outbox,
        loadFriends: () => friends.future,
      );
      final pending = contacts.refresh();
      contacts.reset(clearFriends: true, requireAuth: true);
      friends.complete([alice]);
      messages.complete([row('old', '42')]);
      await pending;
      expect(contacts.items, isEmpty);
      expect(contacts.needAuth, isTrue);
      contacts.dispose();
      inbox.dispose();
      outbox.dispose();
    },
  );

  test(
    'one mailbox failure does not discard friends or the other direction',
    () async {
      final inbox = PmMailboxController(
        ({page = 1}) async => page == 1 ? [row('in', '42')] : [],
      );
      final outbox = PmMailboxController(
        ({page = 1}) async => throw Exception('offline'),
      );
      final contacts = PmContactsController(
        inbox: inbox,
        outbox: outbox,
        loadFriends: () async => [alice, quiet],
      );
      await contacts.refresh();
      expect(contacts.items, hasLength(2));
      expect(contacts.items.first.latest!.id, 'in');
      expect(contacts.historyError, isNotNull);
      contacts.dispose();
      inbox.dispose();
      outbox.dispose();
    },
  );

  testWidgets(
    'search finds unmessaged friends and opening preselects the recipient',
    (tester) async {
      final store = PmTestWebsiteStore();
      final service = _Service(store);
      final container = ProviderContainer(
        overrides: [
          sessionProvider.overrideWith((ref) => PmTestSession()),
          websiteSessionStoreProvider.overrideWithValue(store),
          pmDraftRepositoryProvider.overrideWithValue(
            MemoryPmDraftRepository(),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(websiteSessionProvider.notifier).reload();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: PmPage(
              service: service,
              friendsLoader: (_) async => [alice, quiet],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('好友甲'), findsOneWidget);
      expect(find.text('未聊过好友'), findsOneWidget);
      expect(find.text('收到'), findsNothing);
      expect(find.text('发出'), findsNothing);
      await tester.enterText(find.byType(TextField), 'quiet_friend');
      await tester.pumpAndSettle();
      expect(find.text('好友甲'), findsNothing);
      expect(find.text('未聊过好友'), findsOneWidget);
      await tester.tap(find.text('未聊过好友'));
      await tester.pumpAndSettle();
      expect(find.byType(PmComposeScreen), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'quiet_friend',
      );
      expect(service.recipients, contains('quiet_friend'));
      expect(service.sent, 0);
    },
  );
}

class _Service extends PmService {
  _Service(PmTestWebsiteStore store) : super(sessionStore: store);
  final recipients = <String>[];
  int sent = 0;
  @override
  Future<List<PmConversation>> loadInbox({int page = 1}) async =>
      page == 1 ? [row('same', '42')] : [];
  @override
  Future<List<PmConversation>> loadOutbox({int page = 1}) async =>
      page == 1 ? [row('same', '42')] : [];
  @override
  Future<PmComposeParams> loadComposeParams(String user) async {
    recipients.add(user);
    return PmComposeParams(formhash: 'test', msgReceivers: user);
  }

  @override
  Future<void> compose({
    required PmComposeParams params,
    required String title,
    required String body,
  }) async {
    sent++;
  }
}
