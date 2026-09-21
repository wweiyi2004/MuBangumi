import 'package:flutter/foundation.dart';
import '../models/bangumi_models.dart';
import '../models/pm_contact.dart';
import '../models/pm_models.dart';
import 'pm_mailbox_controller.dart';

class PmContactsController extends ChangeNotifier {
  PmContactsController({
    required this.inbox,
    required this.outbox,
    required this.loadFriends,
  }) {
    inbox.addListener(_changed);
    outbox.addListener(_changed);
  }
  final PmMailboxController inbox, outbox;
  final Future<List<BangumiUser>> Function() loadFriends;
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
    bool supersede = false,
  }) async {
    await Future.wait([
      if (includeFriends) refreshFriends(),
      syncHistory(supersede: supersede),
    ]);
  }

  Future<void> refreshFriends() async {
    final generation = ++_friendsGeneration;
    friendsLoading = true;
    friendsError = null;
    _changed();
    try {
      final loaded = await loadFriends();
      if (!_disposed && generation == _friendsGeneration) friends = loaded;
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
        Future.wait([
          for (final box in [inbox, outbox])
            _drain(box, generation, more: more),
        ]).then<void>((_) {}).whenComplete(() {
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
    var fetched = 0;
    if (!more || !box.loaded || box.error != null) {
      await box.refresh(supersede: true, preserveHistory: true);
      fetched++;
    } else if (box.moreError != null) {
      await box.loadMore();
      fetched++;
    }
    // Fetch recent history first. Older pages are an explicit continuation,
    // not hundreds of background requests on each login or sent message.
    for (; fetched < 3; fetched++) {
      if (_disposed ||
          generation != _historyGeneration ||
          !box.hasMore ||
          box.needAuth ||
          box.error != null ||
          box.moreError != null) {
        return;
      }
      await box.loadMore();
    }
  }

  void reset({bool clearFriends = false, bool requireAuth = false}) {
    _historyGeneration++;
    _history = null;
    syncingHistory = false;
    if (clearFriends) {
      _friendsGeneration++;
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
