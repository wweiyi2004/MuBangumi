import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/network/bangumi_api.dart';
import 'package:mubangumi/features/subject_detail/application/subject_friends_controller.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/models/library_batch.dart';

void main() {
  late _Api api;
  late SubjectFriendsController controller;
  late List<Completer<List<BangumiUser>>> friendCalls;
  LibraryBatchAccount? account;
  setUp(() {
    api = _Api();
    account = _account(1);
    friendCalls = [];
    controller = SubjectFriendsController(
      subjectId: 7,
      api: () => api,
      readAccount: () => account,
      loadFriends: (_) {
        final result = Completer<List<BangumiUser>>();
        friendCalls.add(result);
        return result.future;
      },
    );
  });
  tearDown(() => controller.dispose());

  test('same user relogin blocks old friends before status lookup', () async {
    final old = controller.load();
    await controller.load();
    expect(friendCalls.length, 1);
    account = _account(2);
    controller.reset();
    friendCalls.single.complete([_user]);
    await old;
    expect(api.statusCalls, isEmpty);
    expect(controller.items, isEmpty);
    expect(controller.loaded, isFalse);
    expect(controller.loading, isFalse);
  });

  test(
    'old account status response cannot overwrite the new account',
    () async {
      final old = controller.load();
      friendCalls.last.complete([_user]);
      await Future<void>.delayed(Duration.zero);
      account = _account(2);
      controller.reset();
      final current = controller.load();
      friendCalls.last.complete([_user]);
      await Future<void>.delayed(Duration.zero);
      api.statusCalls.last.complete([_status('current')]);
      await current;
      api.statusCalls.first.complete([_status('old')]);
      await old;
      expect(controller.items.single.comment, 'current');
      expect(controller.error, isNull);
      expect(controller.loaded, isTrue);
    },
  );

  test('failed friend lookup retries and signing out clears results', () async {
    final first = controller.load();
    friendCalls.single.completeError(Exception('offline'));
    await first;
    expect(controller.error, '好友动态加载失败');
    final retry = controller.load();
    expect(controller.error, isNull);
    friendCalls.last.complete([_user]);
    await Future<void>.delayed(Duration.zero);
    api.statusCalls.single.complete([_status('recovered')]);
    await retry;
    expect(controller.items.single.comment, 'recovered');
    account = null;
    controller.reset();
    await controller.load();
    expect(controller.items, isEmpty);
    expect(friendCalls.length, 2);
  });

  test('dispose suppresses a late status error', () async {
    final closing = SubjectFriendsController(
      subjectId: 7,
      api: () => api,
      readAccount: () => account,
      loadFriends: (_) async => [_user],
    );
    var notifications = 0;
    closing.addListener(() => notifications++);
    final load = closing.load();
    await Future<void>.delayed(Duration.zero);
    closing.dispose();
    final before = notifications;
    api.statusCalls.single.completeError(Exception('late'));
    await load;
    expect(notifications, before);
  });
}

LibraryBatchAccount _account(int generation) => LibraryBatchAccount(
  userId: 1,
  username: 'same-user',
  generation: generation,
);
const _user = BangumiUser(
  id: 2,
  username: 'friend',
  nickname: 'Friend',
  avatarUrl: '',
);
FriendSubjectStatus _status(String comment) => FriendSubjectStatus(
  user: _user,
  type: CollectionType.doing,
  comment: comment,
);

class _Api extends BangumiApi {
  final statusCalls = <Completer<List<FriendSubjectStatus>>>[];
  @override
  Future<List<FriendSubjectStatus>> getFriendsSubjectStatus(
    int subjectId, {
    required List<BangumiUser> friends,
    int limit = 12,
    int concurrency = 3,
  }) {
    final result = Completer<List<FriendSubjectStatus>>();
    statusCalls.add(result);
    return result.future;
  }
}
