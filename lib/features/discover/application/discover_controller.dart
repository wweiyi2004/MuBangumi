import 'dart:async';
import '../../../core/network/bangumi_api.dart';
import '../../../core/network/bangumi_support.dart';
import '../../../core/storage/snapshot_cache.dart';
import '../../../models/bangumi_models.dart';
import '../domain/discover_query.dart';

/// Owns pagination, stale-result guards and cache hydration without widgets or
/// Riverpod. The page owns input/debounce/navigation and observes these results.
class DiscoverController {
  DiscoverController({
    required this._api,
    required this._cache,
    required this._query,
    required this.onChanged,
  });
  final BangumiApi _api;
  final SnapshotCache _cache;
  final void Function() onChanged;
  DiscoverQuery _query;
  bool _disposed = false;
  bool get mounted => !_disposed;
  void _update(void Function() change) {
    change();
    if (mounted) onChanged();
  }

  void dispose() {
    _disposed = true;
    _requestId++;
  }

  List<Subject> get subjects => _subjects;
  List<CharacterDetail> get characters => _characters;
  List<PersonDetail> get persons => _persons;
  bool get loading => _loading;
  bool get refreshing => _refreshing;
  bool get loadingMore => _loadingMore;
  bool get hasMore => _hasMore;
  String? get error => _error;
  String? get pageError => _pageError;
  void clearError() {
    _error = null;
  }

  void clearSubjects() {
    _subjects = const [];
    _loading = false;
  }

  Future<void> start(DiscoverQuery query) {
    if (!mounted) return Future.value();
    _query = query;
    final result = _runCurrentQuery();
    if (_query.mode == DiscoverQueryMode.browse) {
      unawaited(_hydrateBrowseCacheIfNeeded(_requestId));
    }
    return result;
  }

  /// Invalidate immediately while a page waits for its input debounce.
  void prepareSearch(DiscoverQuery query) {
    if (!mounted) return;
    _query = query;
    _requestId++;
    _error = null;
    _offset = 0;
    _hasMore = false;
    _loadingMore = false;
    final empty = switch (query.target) {
      DiscoverSearchTarget.subject => _subjects.isEmpty,
      DiscoverSearchTarget.character => _characters.isEmpty,
      DiscoverSearchTarget.person => _persons.isEmpty,
    };
    final prompt =
        query.mode == DiscoverQueryMode.characterPrompt ||
        query.mode == DiscoverQueryMode.personPrompt;
    _loading = !prompt && empty;
    _refreshing = !prompt && !empty;
    onChanged();
  }

  List<Subject> _subjects = const [];
  bool _loading = false;

  /// Background refresh while keeping previous list visible (stale-while-revalidate).
  bool _refreshing = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;
  String? _pageError;
  int _requestId = 0;
  int _offset = 0;
  static const _pageSize = 24;

  List<CharacterDetail> _characters = const [];
  List<PersonDetail> _persons = const [];
  String get _browseCacheKey => SnapshotCache.discoverBrowseKey(
    type: _query.subjectType,
    year: _query.browseYear,
    quarter: _query.browseQuarter,
    sort: _query.browseSort,
    supportsSeason: _query.supportsSeason,
  );

  int _lastSuccessfulBrowseRequest = -1;

  Future<void> _hydrateBrowseCacheIfNeeded(int requestId) async {
    if (_query.mode != DiscoverQueryMode.browse) return;
    final key = _browseCacheKey;
    try {
      final cached = await _cache.readDiscoverBrowse(key);
      if (!mounted || cached == null || cached.isEmpty) return;
      if (_browseCacheKey != key) return;
      if (_query.mode != DiscoverQueryMode.browse ||
          requestId != _requestId ||
          _lastSuccessfulBrowseRequest == requestId) {
        return;
      }
      final refreshing = _loading || _refreshing;
      _update(() {
        _subjects = cached;
        _offset = cached.length;
        _hasMore = cached.length >= _pageSize;
        _loading = false;
        _refreshing = refreshing;
        _error = null;
      });
    } catch (_) {
      // Disk cache is best-effort.
    }
  }

  Future<void> _runCurrentQuery() async {
    _offset = 0;
    _loadingMore = false;
    _hasMore = true;
    _pageError = null;
    final keyword = _query.keyword.trim();
    switch (_query.mode) {
      case DiscoverQueryMode.subjectSearch:
        await _search(keyword);
      case DiscoverQueryMode.characterSearch:
        await _searchCharacters(keyword);
      case DiscoverQueryMode.personSearch:
        await _searchPersons(keyword);
      case DiscoverQueryMode.browse:
        _update(() {
          _characters = const [];
          _persons = const [];
        });
        await _loadBrowse();
      case DiscoverQueryMode.characterPrompt:
        _showSearchPrompt(DiscoverSearchTarget.character);
      case DiscoverQueryMode.personPrompt:
        _showSearchPrompt(DiscoverSearchTarget.person);
    }
  }

  void _showSearchPrompt(DiscoverSearchTarget target) {
    _requestId++;
    _update(() {
      _loading = false;
      _refreshing = false;
      _loadingMore = false;
      _hasMore = false;
      _offset = 0;
      _error = null;
      _subjects = const [];
      _characters = const [];
      _persons = const [];
    });
  }

  Future<void> _searchCharacters(String keyword, {bool append = false}) async {
    final requestId = append ? _requestId : ++_requestId;
    final offset = append ? _offset : 0;
    _update(() {
      if (append) {
        _loadingMore = true;
      } else {
        final empty = _characters.isEmpty;
        _loading = empty;
        _refreshing = !empty;
        _error = null;
        if (empty) {
          _offset = 0;
          _hasMore = true;
        }
      }
    });
    try {
      final items = await _api.searchCharacters(
        keyword,
        limit: _pageSize,
        offset: offset,
      );
      if (!mounted || requestId != _requestId) return;
      _update(() {
        _characters = append ? [..._characters, ...items] : items;
        _offset = offset + items.length;
        _hasMore = items.length >= _pageSize;
        _loading = false;
        _refreshing = false;
        _loadingMore = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted || requestId != _requestId) return;
      _update(() {
        _loading = false;
        _refreshing = false;
        _loadingMore = false;
        if (!append && _characters.isEmpty) {
          _error = error.toString().replaceFirst('Exception: ', '');
        }
      });
    }
  }

  Future<void> _searchPersons(String keyword, {bool append = false}) async {
    final requestId = append ? _requestId : ++_requestId;
    final offset = append ? _offset : 0;
    _update(() {
      if (append) {
        _loadingMore = true;
      } else {
        final empty = _persons.isEmpty;
        _loading = empty;
        _refreshing = !empty;
        _error = null;
        if (empty) {
          _offset = 0;
          _hasMore = true;
        }
      }
    });
    try {
      final items = await _api.searchPersons(
        keyword,
        limit: _pageSize,
        offset: offset,
      );
      if (!mounted || requestId != _requestId) return;
      _update(() {
        _persons = append ? [..._persons, ...items] : items;
        _offset = offset + items.length;
        _hasMore = items.length >= _pageSize;
        _loading = false;
        _refreshing = false;
        _loadingMore = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted || requestId != _requestId) return;
      _update(() {
        _loading = false;
        _refreshing = false;
        _loadingMore = false;
        if (!append && _persons.isEmpty) {
          _error = error.toString().replaceFirst('Exception: ', '');
        }
      });
    }
  }

  Future<void> _loadBrowse({bool append = false}) async {
    final requestId = append ? _requestId : ++_requestId;
    final offset = append ? _offset : 0;
    _update(() {
      if (append) {
        _loadingMore = true;
      } else {
        final empty = _subjects.isEmpty;
        _loading = empty;
        _refreshing = !empty;
        _error = null;
        if (empty) {
          _offset = 0;
          _hasMore = true;
        }
      }
    });
    try {
      final api = _api;
      final subjects = _query.supportsSeason
          ? await api.browseSubjects(
              type: _query.subjectType,
              year: _query.browseYear,
              month: _query.browseQuarter * 3 + 1,
              sort: 'rank',
              limit: _pageSize,
              offset: offset,
            )
          : await api.browseSubjects(
              type: _query.subjectType,
              year: _query.browseYear,
              sort: _query.browseSort,
              limit: _pageSize,
              offset: offset,
            );
      if (!mounted || requestId != _requestId) return;
      _update(() {
        _subjects = append ? [..._subjects, ...subjects] : subjects;
        _offset = offset + subjects.length;
        _hasMore = subjects.length >= _pageSize;
        _loading = false;
        _refreshing = false;
        _loadingMore = false;
        _error = null;
      });
      _lastSuccessfulBrowseRequest = requestId;
      if (!append) {
        unawaited(
          _cache
              .writeDiscoverBrowse(_browseCacheKey, subjects)
              .catchError((Object _) {}),
        );
      }
    } catch (error) {
      if (!mounted || requestId != _requestId) return;
      _update(() {
        _loading = false;
        _refreshing = false;
        _loadingMore = false;
        // Keep stale list; only surface error when there is nothing to show.
        if (!append && _subjects.isEmpty) {
          _error = error.toString().replaceFirst('Exception: ', '');
        }
      });
    }
  }

  Future<void> _search(String keyword, {bool append = false}) async {
    final requestId = append ? _requestId : ++_requestId;
    final offset = append ? _offset : 0;
    _update(() {
      if (append) {
        _loadingMore = true;
      } else {
        final empty = _subjects.isEmpty;
        _loading = empty;
        _refreshing = !empty;
        _error = null;
        if (empty) {
          _offset = 0;
          _hasMore = true;
        }
        _characters = const [];
        _persons = const [];
      }
    });
    try {
      final tags = _query.tag
          .split(RegExp(r'[,，\s]+'))
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();
      final subjects = await _api.searchSubjects(
        keyword,
        sort: _query.searchSort,
        minimumRating: _query.minimumRating,
        ratingExclusive: _query.ratingExclusive,
        startYear: _query.startYear,
        endYear: _query.endYear,
        tags: tags,
        metaTags: _query.metaTags,
        subjectType: _query.subjectType,
        limit: _pageSize,
        offset: offset,
      );
      if (!mounted || requestId != _requestId) return;
      _update(() {
        _subjects = append ? [..._subjects, ...subjects] : subjects;
        _offset = offset + subjects.length;
        _hasMore = subjects.length >= _pageSize;
        _loading = false;
        _refreshing = false;
        _loadingMore = false;
        _error = null;
        _pageError = null;
      });
    } catch (error) {
      if (!mounted || requestId != _requestId) return;
      _update(() {
        _loading = false;
        _refreshing = false;
        _loadingMore = false;
        if (!append && _subjects.isEmpty) {
          _error = error.toString().replaceFirst('Exception: ', '');
        }
        if (append) _pageError = '后续结果加载失败，请重试';
      });
    }
  }

  Future<void> loadMore() async {
    if (!mounted || !_hasMore || _loadingMore || _loading || _refreshing) {
      return;
    }
    final keyword = _query.keyword.trim();
    switch (_query.mode) {
      case DiscoverQueryMode.subjectSearch:
        await _search(keyword, append: true);
      case DiscoverQueryMode.characterSearch:
        await _searchCharacters(keyword, append: true);
      case DiscoverQueryMode.personSearch:
        await _searchPersons(keyword, append: true);
      case DiscoverQueryMode.browse:
        await _loadBrowse(append: true);
      case DiscoverQueryMode.characterPrompt:
      case DiscoverQueryMode.personPrompt:
        return;
    }
  }
}
