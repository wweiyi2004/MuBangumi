import 'package:flutter/foundation.dart';

import '../../../core/network/bangumi_api.dart';
import '../../../core/network/bangumi_support.dart';

class SubjectCommentsController extends ChangeNotifier {
  SubjectCommentsController({required this.subjectId, required this._api});

  final int subjectId;
  final BangumiApi Function() _api;
  List<SubjectComment> _items = const [];
  int _page = 1;
  bool _hasMore = true;
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;
  int _generation = 0;
  bool _disposed = false;

  List<SubjectComment> get items => _items;
  bool get hasMore => _hasMore;
  bool get loading => _loading;
  bool get loadingMore => _loadingMore;
  String? get error => _error;

  Future<void> load({bool append = false}) async {
    if (_disposed || (append && (_loading || _loadingMore || !_hasMore))) {
      return;
    }
    final generation = ++_generation;
    final page = append ? _page + 1 : 1;
    if (append) {
      _loadingMore = true;
    } else {
      _loading = true;
      _loadingMore = false;
      _hasMore = true;
    }
    _error = null;
    notifyListeners();
    try {
      final comments = await _api().getSubjectComments(subjectId, page: page);
      if (_disposed || generation != _generation) return;
      final seen = {for (final item in _items) item.id};
      _items = List.unmodifiable(
        append
            ? [
                ..._items,
                for (final item in comments)
                  if (item.id == 0 || seen.add(item.id)) item,
              ]
            : comments,
      );
      _page = page;
      // HTML pages vary in size; preserve the existing end-of-page heuristic.
      _hasMore = comments.length >= 10;
    } catch (_) {
      if (_disposed || generation != _generation) return;
      if (!append) _error = '吐槽加载失败';
    }
    if (_disposed || generation != _generation) return;
    _loading = _loadingMore = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
