import 'package:flutter/foundation.dart';

import '../models/pm_models.dart';

typedef PmPageLoader = Future<List<PmConversation>> Function({int page});

/// One mailbox owns its pagination and request generation independently.
class PmMailboxController extends ChangeNotifier {
  PmMailboxController(this._load);

  final PmPageLoader _load;
  List<PmConversation> items = const [];
  bool loaded = false;
  bool refreshing = false;
  bool loadingMore = false;
  bool hasMore = true;
  bool needAuth = false;
  String? error;
  String? moreError;
  int _page = 0;
  int _generation = 0;
  bool _disposed = false;
  Future<void>? _refresh;
  List<PmConversation> _freshItems = const [];
  List<PmConversation> _retainedItems = const [];

  Future<void> refresh({bool supersede = false, bool preserveHistory = false}) {
    if (_disposed) return Future.value();
    if (!supersede && _refresh != null) return _refresh!;
    final generation = ++_generation;
    _retainedItems = preserveHistory ? items : const [];
    _freshItems = const [];
    refreshing = true;
    loadingMore = false;
    error = null;
    moreError = null;
    final future = _fetch(generation, 1, append: false);
    _refresh = future;
    notifyListeners();
    return future;
  }

  Future<void> loadMore() {
    if (_disposed ||
        refreshing ||
        loadingMore ||
        !hasMore ||
        !loaded ||
        needAuth) {
      return Future.value();
    }
    loadingMore = true;
    moreError = null;
    notifyListeners();
    return _fetch(_generation, _page + 1, append: true);
  }

  Future<void> _fetch(int generation, int page, {required bool append}) async {
    try {
      final next = await Future.sync(() => _load(page: page));
      if (!_current(generation)) return;
      final known = append
          ? _freshItems.map((item) => item.id).toSet()
          : <String>{};
      final added = next.where((item) => known.add(item.id)).toList();
      _freshItems = [if (append) ..._freshItems, ...added];
      _page = page;
      loaded = true;
      needAuth = false;
      // The HTML list has no fixed page size. Stop on empty/repeated pages.
      hasMore = added.isNotEmpty;
      // A short refresh must not discard previously loaded older contacts.
      // Once the refreshed scan reaches its end, retire missing old rows.
      if (!hasMore) _retainedItems = const [];
      items = List.unmodifiable([
        ..._freshItems,
        ..._retainedItems.where((item) => !known.contains(item.id)),
      ]);
    } catch (exception) {
      if (!_current(generation)) return;
      final message = exception.toString().replaceFirst('Exception: ', '');
      if (exception is PmAuthException) {
        needAuth = true;
        items = const [];
        _freshItems = _retainedItems = const [];
        error = exception.message;
      } else if (append) {
        moreError = message;
      } else {
        error = message;
      }
    } finally {
      if (_current(generation)) {
        if (append) {
          loadingMore = false;
        } else {
          refreshing = false;
          _refresh = null;
        }
        notifyListeners();
      }
    }
  }

  bool _current(int generation) => !_disposed && generation == _generation;

  void reset({bool requireAuth = false}) {
    _generation++;
    _refresh = null;
    items = const [];
    _freshItems = _retainedItems = const [];
    loaded = refreshing = loadingMore = false;
    hasMore = true;
    needAuth = requireAuth;
    error = moreError = null;
    _page = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
