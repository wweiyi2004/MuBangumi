import 'package:flutter/foundation.dart';

import '../../../core/network/bangumi_api.dart';
import '../../../models/bangumi_models.dart';
import '../../../models/library_batch.dart';

class SubjectFriendsController extends ChangeNotifier {
  SubjectFriendsController({
    required this.subjectId,
    required this._api,
    required this.readAccount,
    required this.loadFriends,
  });

  final int subjectId;
  final BangumiApi Function() _api;
  final LibraryBatchAccount? Function() readAccount;
  final Future<List<BangumiUser>> Function(String username) loadFriends;
  List<FriendSubjectStatus> _items = const [];
  bool _loading = false;
  bool _loaded = false;
  String? _error;
  int _generation = 0;
  bool _disposed = false;

  List<FriendSubjectStatus> get items => _items;
  bool get loading => _loading;
  bool get loaded => _loaded;
  String? get error => _error;

  void reset() {
    if (_disposed) return;
    _generation++;
    _items = const [];
    _loading = _loaded = false;
    _error = null;
    notifyListeners();
  }

  bool _current(int generation, LibraryBatchAccount account) {
    if (_disposed || generation != _generation) return false;
    final current = readAccount();
    return current?.userId == account.userId &&
        current?.username == account.username &&
        current?.generation == account.generation;
  }

  Future<void> load() async {
    if (_disposed || _loading) return;
    final account = readAccount();
    if (account == null) return;
    final generation = ++_generation;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final friends = await loadFriends(account.username);
      if (!_current(generation, account)) return;
      final statuses = await _api().getFriendsSubjectStatus(
        subjectId,
        friends: friends,
        limit: 12,
        concurrency: 3,
      );
      if (!_current(generation, account)) return;
      _items = List.unmodifiable(statuses);
    } catch (_) {
      if (!_current(generation, account)) return;
      _error = '好友动态加载失败';
    }
    _loading = false;
    _loaded = true;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
