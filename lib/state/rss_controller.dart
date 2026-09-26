import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/rss_fetcher.dart';
import '../core/storage/rss_store.dart';
import '../models/rss_models.dart';
import '../models/schedule_models.dart';

class RssState {
  const RssState({
    this.sources = const [],
    this.bindings = const [],
    this.unreadBySubject = const {},
    this.totalUnread = 0,
    this.refreshing = false,
    this.message,
    this.loaded = false,
    this.autoRefreshPaused = false,
  });

  final List<RssSource> sources;
  final List<RssBinding> bindings;
  final Map<int, int> unreadBySubject;
  final int totalUnread;
  final bool refreshing;
  final String? message;
  final bool loaded;
  final bool autoRefreshPaused;

  int unreadFor(int subjectId) => unreadBySubject[subjectId] ?? 0;

  bool isBound(int subjectId) =>
      bindings.any((b) => b.subjectId == subjectId && b.enabled);

  RssState copyWith({
    List<RssSource>? sources,
    List<RssBinding>? bindings,
    Map<int, int>? unreadBySubject,
    int? totalUnread,
    bool? refreshing,
    String? message,
    bool? loaded,
    bool? autoRefreshPaused,
    bool clearMessage = false,
  }) => RssState(
    sources: sources ?? this.sources,
    bindings: bindings ?? this.bindings,
    unreadBySubject: unreadBySubject ?? this.unreadBySubject,
    totalUnread: totalUnread ?? this.totalUnread,
    refreshing: refreshing ?? this.refreshing,
    message: clearMessage ? null : message ?? this.message,
    loaded: loaded ?? this.loaded,
    autoRefreshPaused: autoRefreshPaused ?? this.autoRefreshPaused,
  );
}

class RssController extends StateNotifier<RssState> {
  RssController(this._store, this._fetcher, {DateTime Function()? now})
    : _now = now ?? DateTime.now,
      super(const RssState()) {
    reload();
  }

  final DateTime Function() _now;
  final RssStore _store;
  final RssFetcher _fetcher;
  static const autoRefreshInterval = Duration(minutes: 30);
  Timer? _refreshTimer;
  bool _foreground = false;
  bool _checking = false;
  DateTime? _lastAttempt;

  void setForeground(bool value) {
    if (!mounted || _foreground == value) return;
    _foreground = value;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    if (value) {
      unawaited(checkForUpdates());
      _refreshTimer = Timer.periodic(autoRefreshInterval, (_) {
        unawaited(checkForUpdates());
      });
    }
  }

  Future<void> checkForUpdates() async {
    if (!_foreground ||
        !_valid(_epoch) ||
        _checking ||
        state.refreshing ||
        state.autoRefreshPaused) {
      return;
    }
    _checking = true;
    try {
      if (!state.loaded && !await reload()) return;
      if (!_foreground || !_valid(_epoch) || state.autoRefreshPaused) return;
      final now = _now();
      if (_lastAttempt != null &&
          now.difference(_lastAttempt!) < autoRefreshInterval) {
        return;
      }
      final sourceIds = {
        for (final binding in state.bindings)
          if (binding.enabled) binding.sourceId,
      };
      if (!state.sources.any(
        (source) =>
            source.enabled &&
            sourceIds.contains(source.id) &&
            (source.lastFetchAt == null ||
                now.difference(source.lastFetchAt!) >= autoRefreshInterval),
      )) {
        return;
      }
      _lastAttempt = now;
      await refreshAll(automatic: true);
    } finally {
      _checking = false;
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  int _epoch = 0;
  int _loadGeneration = 0;
  bool _pausedForImport = false;
  bool _valid(int epoch) => mounted && !_pausedForImport && epoch == _epoch;

  Future<void> pauseForImport() async {
    _pausedForImport = true;
    _epoch++;
    _loadGeneration++;
    if (mounted) state = state.copyWith(refreshing: false, loaded: false);
    await _store.flushWrites();
  }

  Future<bool> resumeAfterImport({required bool imported}) async {
    _pausedForImport = false;
    if (!mounted) return false;
    state = state.copyWith(
      refreshing: false,
      autoRefreshPaused: imported || state.autoRefreshPaused,
    );
    return reload();
  }

  Future<bool> reload() async {
    if (!_valid(_epoch)) return false;
    final epoch = _epoch;
    final generation = ++_loadGeneration;
    try {
      final sources = await _store.listSources();
      final bindings = await _store.listBindings();
      final unread = await _store.unreadCountsBySubject();
      final total = await _store.totalUnread();
      if (!_valid(epoch) || generation != _loadGeneration) return false;
      state = state.copyWith(
        sources: sources,
        bindings: bindings,
        unreadBySubject: unread,
        totalUnread: total,
        loaded: true,
        clearMessage: true,
      );
      return true;
    } catch (error) {
      if (!_valid(epoch) || generation != _loadGeneration) return false;
      state = state.copyWith(
        loaded: false,
        message: '读取更新源失败：${_errorText(error)}',
      );
      return false;
    }
  }

  Future<void> addSource({required String name, required String url}) async {
    if (!_valid(_epoch)) return;
    final epoch = _epoch;
    final trimmedUrl = url.trim();
    final trimmedName = name.trim().isEmpty
        ? _guessName(trimmedUrl)
        : name.trim();
    if (trimmedUrl.isEmpty) {
      state = state.copyWith(message: '请填写 RSS 链接');
      return;
    }
    final uri = Uri.tryParse(trimmedUrl);
    if (uri == null ||
        !(uri.isScheme('http') || uri.isScheme('https')) ||
        uri.host.isEmpty) {
      state = state.copyWith(message: 'RSS 链接无效');
      return;
    }
    try {
      await _store.upsertSource(
        RssSource(id: 0, name: trimmedName, url: trimmedUrl),
      );
      if (_valid(epoch) && await reload() && _valid(epoch)) {
        state = state.copyWith(message: '已添加更新源：$trimmedName');
      }
    } catch (error) {
      if (!_valid(epoch)) return;
      state = state.copyWith(
        message: '添加失败：${error.toString().replaceFirst('Exception: ', '')}',
      );
    }
  }

  Future<void> deleteSource(int sourceId) async {
    if (!_valid(_epoch)) return;
    final epoch = _epoch;
    try {
      await _store.deleteSource(sourceId);
      if (_valid(epoch) && await reload() && _valid(epoch)) {
        state = state.copyWith(message: '已删除更新源');
      }
    } catch (error) {
      if (!_valid(epoch)) return;
      state = state.copyWith(message: '删除失败：${_errorText(error)}');
    }
  }

  Future<void> bindSubject({
    required int sourceId,
    required ScheduleItem item,
    required SeasonKey season,
    String? matchKeywords,
    String? excludeKeywords,
  }) async {
    if (!_valid(_epoch)) return;
    final epoch = _epoch;
    final binding = RssBinding(
      id: 0,
      sourceId: sourceId,
      subjectId: item.subjectId,
      subjectName: item.displayName,
      seasonKey: season.id,
      matchKeywords: matchKeywords?.trim().isNotEmpty == true
          ? matchKeywords!.trim()
          : _defaultKeywords(item),
      excludeKeywords: excludeKeywords ?? '合集,NC-OP,NC-ED,NCOP,NCED,SP,特典',
    );
    try {
      // Decide insert vs update up-front instead of guessing from a caught
      // error, so genuine storage failures are surfaced, not masked.
      final existing = (await _store.listBindings(
        subjectId: item.subjectId,
        sourceId: sourceId,
      )).firstOrNull;
      if (!_valid(epoch)) return;
      if (existing == null) {
        await _store.upsertBinding(binding);
        if (_valid(epoch) && await reload() && _valid(epoch)) {
          state = state.copyWith(message: '已绑定更新源 → ${item.displayName}');
        }
      } else {
        await _store.upsertBinding(
          existing.copyWith(
            subjectName: item.displayName,
            seasonKey: season.id,
            matchKeywords: binding.matchKeywords,
            excludeKeywords: binding.excludeKeywords,
            enabled: true,
          ),
        );
        if (_valid(epoch) && await reload() && _valid(epoch)) {
          state = state.copyWith(message: '已更新绑定：${item.displayName}');
        }
      }
    } catch (error) {
      if (!_valid(epoch)) return;
      state = state.copyWith(message: '绑定失败：${_errorText(error)}');
    }
  }

  Future<void> unbind(int bindingId) async {
    if (!_valid(_epoch)) return;
    final epoch = _epoch;
    try {
      await _store.deleteBinding(bindingId);
      if (_valid(epoch) && await reload() && _valid(epoch)) {
        state = state.copyWith(message: '已解除绑定');
      }
    } catch (error) {
      if (!_valid(epoch)) return;
      state = state.copyWith(message: '解除失败：${_errorText(error)}');
    }
  }

  Future<void> unbindSubject(int subjectId) async {
    if (!_valid(_epoch)) return;
    final epoch = _epoch;
    try {
      await _store.deleteBindingsForSubject(subjectId);
      if (_valid(epoch) && await reload() && _valid(epoch)) {
        state = state.copyWith(message: '已解除该番的更新源');
      }
    } catch (error) {
      if (!_valid(epoch)) return;
      state = state.copyWith(message: '解除失败：${_errorText(error)}');
    }
  }

  /// Refresh all enabled sources. Only keeps items matching schedule bindings.
  Future<void> refreshAll({bool force = false, bool automatic = false}) async {
    if (!_valid(_epoch) ||
        state.refreshing ||
        (automatic && state.autoRefreshPaused)) {
      return;
    }
    final epoch = _epoch;
    if (!state.loaded && !await reload()) return;
    if (!_valid(epoch)) return;
    if (!automatic) state = state.copyWith(autoRefreshPaused: false);
    final sources = state.sources.where((s) => s.enabled).toList();
    if (sources.isEmpty) {
      state = state.copyWith(message: '还没有更新源，先添加种子站 RSS');
      return;
    }
    if (state.bindings.where((b) => b.enabled).isEmpty) {
      state = state.copyWith(message: '请先在新番表里把番绑定到更新源');
      return;
    }

    state = state.copyWith(refreshing: true, clearMessage: true);
    var newCount = 0;
    var errors = 0;
    try {
      var nextSource = 0;
      var publish = Future<void>.value();
      Future<void> worker() async {
        while (_valid(epoch) && nextSource < sources.length) {
          final source = sources[nextSource++];
          try {
            // Await before incrementing: += across await can lose another worker's count.
            final added = await _refreshSource(
              source,
              epoch: epoch,
              force: force,
            );
            newCount += added;
          } catch (_) {
            errors++;
          }
          // Serialize snapshots so an older disk read cannot replace a newer one.
          publish = publish.then((_) async {
            if (_valid(epoch)) await reload();
          });
          await publish;
        }
      }

      await Future.wait([
        for (var i = 0; i < 3 && i < sources.length; i++) worker(),
      ]);
      if (!_valid(epoch)) return;
      final loaded = await reload();
      if (!_valid(epoch)) return;
      if (!loaded) {
        state = state.copyWith(refreshing: false);
        return;
      }
      final msg = errors == 0
          ? (newCount > 0 ? '检查完成，新增 $newCount 条可看提醒' : '检查完成，暂无新更新')
          : '检查完成：+$newCount 条，另有 $errors 个源失败';
      state = state.copyWith(refreshing: false, message: msg);
    } catch (error) {
      if (!_valid(epoch)) return;
      state = state.copyWith(
        refreshing: false,
        message: '刷新失败：${error.toString().replaceFirst('Exception: ', '')}',
      );
    }
  }

  Future<int> _refreshSource(
    RssSource source, {
    required int epoch,
    bool force = false,
  }) async {
    if (!_valid(epoch)) return 0;
    final bindings = state.bindings
        .where((b) => b.enabled && b.sourceId == source.id)
        .toList();
    if (bindings.isEmpty) {
      // Still touch last_fetch so UI shows activity; no items without bindings.
      await _store.upsertSource(
        source.copyWith(lastFetchAt: DateTime.now(), clearError: true),
      );
      return 0;
    }

    try {
      final result = await _fetcher.fetch(
        source.url,
        etag: force ? '' : source.etag,
        lastModified: force ? '' : source.lastModified,
      );

      if (!_valid(epoch)) return 0;
      if (result.notModified) {
        await _store.upsertSource(
          source.copyWith(lastFetchAt: DateTime.now(), clearError: true),
        );
        return 0;
      }

      final now = _now();
      // Bindings may have been edited or removed while the feed was in flight.
      final currentBindings = await _store.listBindings(sourceId: source.id);
      if (!_valid(epoch)) return 0;
      final matched = <RssItem>[];
      for (final entry in result.entries) {
        // v1: only keep entries that match a bound subject.
        for (final binding in currentBindings.where(
          (b) => b.enabled && b.sourceId == source.id,
        )) {
          if (!binding.matchesTitle(entry.title)) continue;
          matched.add(
            RssItem(
              id: 0,
              sourceId: source.id,
              subjectId: binding.subjectId,
              guid: entry.guid,
              title: entry.title,
              link: entry.link,
              publishedAt: entry.publishedAt,
              firstSeenAt: now,
            ),
          );
          break; // first matching binding wins
        }
      }

      final added = await _store.insertItemsIgnoreDup(
        matched,
        validateBindings: true,
      );
      if (!_valid(epoch)) return 0;
      await _store.upsertSource(
        source.copyWith(
          etag: result.etag,
          lastModified: result.lastModified,
          lastFetchAt: now,
          clearError: true,
        ),
      );
      return added;
    } catch (error) {
      if (!_valid(epoch)) return 0;
      await _store.upsertSource(
        source.copyWith(
          lastFetchAt: DateTime.now(),
          lastError: error.toString().replaceFirst('Exception: ', ''),
        ),
      );
      rethrow;
    }
  }

  Future<List<RssItem>> itemsForSubject(
    int subjectId, {
    bool unreadOnly = false,
  }) =>
      _store.listItems(subjectId: subjectId, unreadOnly: unreadOnly, limit: 50);

  Future<List<RssItem>> recentItems({int limit = 40}) =>
      _store.listItems(limit: limit);

  Future<void> markItemRead(int itemId) async {
    if (!_valid(_epoch)) return;
    final epoch = _epoch;
    try {
      await _store.markRead(itemId);
      if (_valid(epoch)) await reload();
    } catch (error) {
      if (!_valid(epoch)) return;
      state = state.copyWith(message: '标记已读失败：${_errorText(error)}');
    }
  }

  Future<void> markSubjectRead(int subjectId) async {
    if (!_valid(_epoch)) return;
    final epoch = _epoch;
    try {
      await _store.markSubjectRead(subjectId);
      if (_valid(epoch)) await reload();
    } catch (error) {
      if (!_valid(epoch)) return;
      state = state.copyWith(message: '标记已读失败：${_errorText(error)}');
    }
  }

  void clearMessage() => state = state.copyWith(clearMessage: true);

  String _errorText(Object error) => error
      .toString()
      .replaceFirst('Exception: ', '')
      .replaceFirst('FormatException: ', '');

  String _defaultKeywords(ScheduleItem item) {
    // Prefer shorter Chinese name as single token; also keep original name if different.
    final parts = <String>[];
    if (item.nameCn.trim().isNotEmpty) parts.add(item.nameCn.trim());
    if (item.name.trim().isNotEmpty && item.name.trim() != item.nameCn.trim()) {
      parts.add(item.name.trim());
    }
    // Use first token only for match (OR would need different semantics).
    // Our matcher is AND across tokens — so only use the primary display name.
    return item.displayName.trim();
  }

  String _guessName(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return 'RSS 源';
    final host = uri.host;
    if (host.contains('mikan')) return 'Mikan';
    if (host.contains('dmhy')) return '动漫花园';
    if (host.contains('nyaa')) return 'Nyaa';
    if (host.contains('acg.rip')) return 'acg.rip';
    return host.isEmpty ? 'RSS 源' : host;
  }
}

final rssStoreProvider = Provider<RssStore>((ref) => RssStore.shared);

final rssFetcherProvider = Provider<RssFetcher>((ref) => RssFetcher());

final rssProvider = StateNotifierProvider<RssController, RssState>((ref) {
  return RssController(
    ref.watch(rssStoreProvider),
    ref.watch(rssFetcherProvider),
  );
});
