import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/models/pm_models.dart';
import 'package:mubangumi/state/pm_mailbox_controller.dart';

void main() {
  test(
    'pagination deduplicates overlap, retries the same page, and stops',
    () async {
      final pages = <int>[];
      var fail = true;
      final controller = PmMailboxController(({page = 1}) async {
        pages.add(page);
        if (page == 2 && fail) throw StateError('offline');
        return switch (page) {
          1 => [_item('1'), _item('2')],
          2 => [_item('2'), _item('3')],
          _ => <PmConversation>[],
        };
      });
      addTearDown(controller.dispose);
      await controller.refresh();
      await controller.loadMore();
      expect(controller.items.map((e) => e.id), ['1', '2']);
      expect(controller.moreError, contains('offline'));
      fail = false;
      await controller.loadMore();
      expect(controller.items.map((e) => e.id), ['1', '2', '3']);
      await controller.loadMore();
      await controller.loadMore();
      expect(pages, [1, 2, 2, 3]);
      expect(controller.hasMore, isFalse);
    },
  );

  test('repeated last page cannot cause endless pagination', () async {
    final controller = PmMailboxController(({page = 1}) async => [_item('1')]);
    addTearDown(controller.dispose);
    await controller.refresh();
    await controller.loadMore();
    expect(controller.hasMore, isFalse);
    expect(controller.items, hasLength(1));
  });

  test(
    'refresh supersedes pagination and coalesces repeated refresh taps',
    () async {
      var calls = 0;
      final more = Completer<List<PmConversation>>();
      final fresh = Completer<List<PmConversation>>();
      final controller = PmMailboxController(({page = 1}) {
        calls++;
        if (page == 2) return more.future;
        return calls == 1 ? Future.value([_item('old')]) : fresh.future;
      });
      addTearDown(controller.dispose);
      await controller.refresh();
      final pagination = controller.loadMore();
      final refresh = controller.refresh();
      final duplicate = controller.refresh();
      expect(identical(refresh, duplicate), isTrue);
      more.complete([_item('obsolete-page')]);
      await pagination;
      expect(controller.items.single.id, 'old');
      expect(controller.refreshing, isTrue);
      fresh.complete([_item('new')]);
      await refresh;
      expect(controller.items.single.id, 'new');
      expect(calls, 3);
    },
  );

  test(
    'post-send refresh supersedes old first page, including its errors',
    () async {
      final old = Completer<List<PmConversation>>();
      var calls = 0;
      final controller = PmMailboxController(
        ({page = 1}) =>
            ++calls == 1 ? old.future : Future.value([_item('sent')]),
      );
      addTearDown(controller.dispose);
      final first = controller.refresh();
      await controller.refresh(supersede: true);
      old.completeError(const PmAuthException());
      await first;
      expect(controller.items.single.id, 'sent');
      expect(controller.needAuth, isFalse);
      expect(controller.error, isNull);
    },
  );

  test('account reset and disposal reject late responses', () async {
    final response = Completer<List<PmConversation>>();
    final controller = PmMailboxController(({page = 1}) => response.future);
    final request = controller.refresh();
    controller.reset(requireAuth: true);
    response.complete([_item('private-old-account')]);
    await request;
    expect(controller.items, isEmpty);
    expect(controller.needAuth, isTrue);
    controller.dispose();
    await controller.refresh();
  });

  test(
    'refresh errors retain data and synchronous errors can be retried',
    () async {
      var fail = false;
      final controller = PmMailboxController(({page = 1}) {
        if (fail) throw StateError('offline');
        return Future.value([_item('kept')]);
      });
      addTearDown(controller.dispose);
      await controller.refresh();
      fail = true;
      await controller.refresh();
      expect(controller.items.single.id, 'kept');
      expect(controller.error, contains('offline'));
      fail = false;
      await controller.refresh();
      expect(controller.error, isNull);
      expect(controller.refreshing, isFalse);
    },
  );
}

PmConversation _item(String id) => PmConversation(
  id: id,
  title: id,
  preview: '',
  peerName: '',
  peerUserId: '',
);
