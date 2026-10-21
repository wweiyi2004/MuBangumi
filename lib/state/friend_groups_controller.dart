import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../core/social/friend_groups.dart';

class FriendGroupsState {
  FriendGroupsState({FriendGroups? groups, this.loading = false, this.error})
    : groups = groups ?? FriendGroups();
  final FriendGroups groups;
  final bool loading;
  final String? error;
}

class FriendGroupsController extends StateNotifier<FriendGroupsState> {
  FriendGroupsController(this.ownerId, this.storage)
    : super(FriendGroupsState(loading: true)) {
    ready = _restore();
  }
  final int ownerId;
  final FlutterSecureStorage storage;
  String get key => 'friend_groups_v1:$ownerId';
  late Future<void> ready;
  Future<void> _tail = Future.value();
  bool _loaded = false;
  Future<void> _restore() async {
    _loaded = false;
    if (mounted) state = FriendGroupsState(groups: state.groups, loading: true);
    try {
      final raw = await storage.read(key: key);
      final groups = raw == null
          ? FriendGroups()
          : FriendGroups.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      _loaded = true;
      if (mounted) state = FriendGroupsState(groups: groups);
    } catch (_) {
      _loaded = false;
      if (mounted) {
        state = FriendGroupsState(groups: state.groups, error: '分组读取失败，请重试');
      }
    }
  }

  Future<void> retry() {
    if (state.loading) return ready;
    ready = _restore();
    return ready;
  }

  Future<void> edit(FriendGroups Function(FriendGroups) change) {
    final next = _tail.then((_) async {
      await ready;
      if (!_loaded || !mounted || ownerId <= 0) {
        throw StateError('无法读取当前账号的好友分组');
      }
      final groups = change(state.groups);
      await storage.write(key: key, value: jsonEncode(groups.toJson()));
      if (mounted) state = FriendGroupsState(groups: groups);
    });
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }
}

final friendGroupsProvider =
    StateNotifierProvider.family<
      FriendGroupsController,
      FriendGroupsState,
      int
    >((ref, id) => FriendGroupsController(id, const FlutterSecureStorage()));
