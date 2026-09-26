import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/storage/snapshot_cache.dart';

import '../models/bangumi_models.dart';
import '../models/pm_contact.dart';
import '../models/pm_models.dart';
import 'pm_mailbox_controller.dart';

final pmFriendsCacheProvider = Provider<SnapshotCache>(
  (ref) => SnapshotCache.shared,
);

class PmContactsController extends ChangeNotifier {
  PmContactsController({
    required this.inbox,
    required this.outbox,
    required this.loadFriends,
    this.cache,
  }) {
    inbox.addListener(_changed);
    outbox.addListener(_changed);
  }
  final PmMailboxController inbox, outbox;
  final Future<List<BangumiUser>> Function({bool refresh}) loadFriends;
  final SnapshotCache? cache;
  int? _accountId;
  bool _cacheRead = false;
  Future<void>? _friendsRequest;

  Future<void> attachAccount(int? userId, {bool requireAuth = false}) {
    if (_accountId == userId) return _friendsRequest ?? Future.value();
    reset(
      clearFriends: true,
      requireAuth: requireAuth || _accountId != null || userId == null,
    );
    _accountId = userId;
    return userId == null ? Future.value() : refreshFriends();
  }

  List<BangumiUser> friends = const [];
  bool friendsLoading = false, syncingHistory = false;
  String? friendsError;
  int _friendsGeneration = 0, _historyGeneration = 0;
  bool _disposed = false;
  Future<void>? _history;
  List<PmContact> _cachedItems = const [];
  List<BangumiUser>? _lastFriends;
  List<PmConversation>? _lastInbox, _lastOutbox;
  List<PmContact> get items {
    if (!identical(_lastFriends, friends) ||
        !identical(_lastInbox, inbox.items) ||
        !identical(_lastOutbox, outbox.items)) {
      _lastFriends = friends;
      _lastInbox = inbox.items;
      _lastOutbox = outbox.items;
      _cachedItems = List.unmodifiable(
        mergePmContacts(friends, [...inbox.items, ...outbox.items]),
      );
    }
    return _cachedItems;
  }

  bool get needAuth => inbox.needAuth || outbox.needAuth;
  bool get busy => friendsLoading || syncingHistory;
  bool get historyIncomplete => !needAuth && (inbox.hasMore || outbox.hasMore);
  String? get historyError =>
      inbox.error ?? outbox.error ?? inbox.moreError ?? outbox.moreError;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> refresh({
    bool includeFriends = true,
    bool forceFriends = false,
    bool supersede = false,
  }) async {
    await Future.wait([
      if (includeFriends) refreshFriends(refresh: forceFriends),
      syncHistory(supersede: supersede),
    ]);
  }

  Future<void> refreshFriends({bool refresh = false}) {
    if (_disposed) return Future.value();
    if (_friendsRequest != null) return _friendsRequest!;
    late final Future<void> future;
    future = _refreshFriends(refresh: refresh).whenComplete(() {
      if (identical(_friendsRequest, future)) _friendsRequest = null;
    });
    _friendsRequest = future;
    return future;
  }

  Future<void> _refreshFriends({required bool refresh}) async {
    final generation = ++_friendsGeneration;
    friendsLoading = true;
    friendsError = null;
    _changed();
    try {
      final owner = _accountId;
      if (!_cacheRead && cache != null && owner != null) {
        _cacheRead = true;
        List<BangumiUser>? cached;
        try {
          cached = await cache!.readPmFriends(owner);
        } catch (_) {}
        if (_disposed || generation != _friendsGeneration) return;
        if (cached != null) {
          friends = cached;
          _changed();
        }
      }
      final loaded = await loadFriends(refresh: refresh);
      if (_disposed || generation != _friendsGeneration) return;
      friends = loaded;
      _changed();
      if (cache != null && owner != null) {
        try {
          await cache!.writePmFriends(owner, loaded);
        } catch (_) {}
      }
    } catch (_) {
      if (!_disposed && generation == _friendsGeneration) {
        friendsError = '好友列表加载失败，请重试';
      }
    } finally {
      if (!_disposed && generation == _friendsGeneration) {
        friendsLoading = false;
        _changed();
      }
    }
  }

  Future<void> syncHistory({bool more = false, bool supersede = false}) {
    if (_disposed) return Future.value();
    if (_history != null && !supersede) return _history!;
    final generation = ++_historyGeneration;
    syncingHistory = true;
    late final Future<void> future;
    future =
        (() async {
          for (final box in [inbox, outbox]) {
            if (_disposed || generation != _historyGeneration) return;
            await _drain(box, generation, more: more);
          }
        })().whenComplete(() {
          if (!_disposed && generation == _historyGeneration) {
            syncingHistory = false;
            if (identical(_history, future)) _history = null;
            _changed();
          }
        });
    _history = future;
    _changed();
    return future;
  }

  Future<void> _drain(
    PmMailboxController box,
    int generation, {
    required bool more,
  }) async {
    if (!more || !box.loaded || box.error != null) {
      await box.refresh(supersede: true, preserveHistory: true);
    } else {
      await box.loadMore();
    }
  }

  void reset({bool clearFriends = false, bool requireAuth = false}) {
    _historyGeneration++;
    _history = null;
    syncingHistory = false;
    if (clearFriends) {
      _friendsGeneration++;
      _friendsRequest = null;
      _cacheRead = false;
      friends = const [];
      friendsLoading = false;
      friendsError = null;
    }
    inbox.reset(requireAuth: requireAuth);
    outbox.reset(requireAuth: requireAuth);
    _changed();
  }

  @override
  void dispose() {
    _disposed = true;
    _friendsGeneration++;
    _historyGeneration++;
    inbox.removeListener(_changed);
    outbox.removeListener(_changed);
    super.dispose();
  }
}
