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
  });

  final List<RssSource> sources;
  final List<RssBinding> bindings;
  final Map<int, int> unreadBySubject;
  final int totalUnread;
  final bool refreshing;
  final String? message;
  final bool loaded;

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
    bool clearMessage = false,
  }) => RssState(
    sources: sources ?? this.sources,
    bindings: bindings ?? this.bindings,
    unreadBySubject: unreadBySubject ?? this.unreadBySubject,
    totalUnread: totalUnread ?? this.totalUnread,
    refreshing: refreshing ?? this.refreshing,
    message: clearMessage ? null : message ?? this.message,
    loaded: loaded ?? this.loaded,
  );
}

class RssController extends StateNotifier<RssState> {
  RssController(this._store, this._fetcher) : super(const RssState()) {
    reload();
  }

  final RssStore _store;
  final RssFetcher _fetcher;

  Future<void> reload() async {
    final sources = await _store.listSources();
    final bindings = await _store.listBindings();
    final unread = await _store.unreadCountsBySubject();
    final total = await _store.totalUnread();
    state = state.copyWith(
      sources: sources,
      bindings: bindings,
      unreadBySubject: unread,
      totalUnread: total,
      loaded: true,
      clearMessage: true,
    );
  }

  Future<void> addSource({required String name, required String url}) async {
    final trimmedUrl = url.trim();
    final trimmedName = name.trim().isEmpty ? _guessName(trimmedUrl) : name.trim();
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
      await reload();
      state = state.copyWith(message: '已添加更新源：$trimmedName');
    } catch (error) {
      state = state.copyWith(
        message: '添加失败：${error.toString().replaceFirst('Exception: ', '')}',
      );
    }
  }

  Future<void> deleteSource(int sourceId) async {
    await _store.deleteSource(sourceId);
    await reload();
    state = state.copyWith(message: '已删除更新源');
  }

  Future<void> bindSubject({
    required int sourceId,
    required ScheduleItem item,
    required SeasonKey season,
    String? matchKeywords,
    String? excludeKeywords,
  }) async {
    final binding = RssBinding(
      id: 0,
      sourceId: sourceId,
      subjectId: item.subjectId,
      subjectName: item.displayName,
      seasonKey: season.id,
      matchKeywords: matchKeywords?.trim().isNotEmpty == true
          ? matchKeywords!.trim()
          : _defaultKeywords(item),
      excludeKeywords: excludeKeywords ??
          '合集,NC-OP,NC-ED,NCOP,NCED,SP,特典',
    );
    try {
      await _store.upsertBinding(binding);
      await reload();
      state = state.copyWith(message: '已绑定更新源 → ${item.displayName}');
    } catch (error) {
      // UNIQUE conflict: update existing
      final existing = (await _store.listBindings(
        subjectId: item.subjectId,
        sourceId: sourceId,
      )).firstOrNull;
      if (existing != null) {
        await _store.upsertBinding(
          existing.copyWith(
            subjectName: item.displayName,
            seasonKey: season.id,
            matchKeywords: binding.matchKeywords,
            excludeKeywords: binding.excludeKeywords,
            enabled: true,
          ),
        );
        await reload();
        state = state.copyWith(message: '已更新绑定：${item.displayName}');
        return;
      }
      state = state.copyWith(
        message: '绑定失败：${error.toString().replaceFirst('Exception: ', '')}',
      );
    }
  }

  Future<void> unbind(int bindingId) async {
    await _store.deleteBinding(bindingId);
    await reload();
    state = state.copyWith(message: '已解除绑定');
  }

  Future<void> unbindSubject(int subjectId) async {
    await _store.deleteBindingsForSubject(subjectId);
    await reload();
    state = state.copyWith(message: '已解除该番的更新源');
  }

  /// Refresh all enabled sources. Only keeps items matching schedule bindings.
  Future<void> refreshAll({bool force = false}) async {
    if (state.refreshing) return;
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
      for (final source in sources) {
        try {
          newCount += await _refreshSource(source, force: force);
        } catch (_) {
          errors++;
        }
      }
      await reload();
      final msg = errors == 0
          ? (newCount > 0 ? '检查完成，新增 $newCount 条可看提醒' : '检查完成，暂无新更新')
          : '检查完成：+$newCount 条，另有 $errors 个源失败';
      state = state.copyWith(refreshing: false, message: msg);
    } catch (error) {
      state = state.copyWith(
        refreshing: false,
        message: '刷新失败：${error.toString().replaceFirst('Exception: ', '')}',
      );
    }
  }

  Future<int> _refreshSource(RssSource source, {bool force = false}) async {
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

      if (result.notModified) {
        await _store.upsertSource(
          source.copyWith(lastFetchAt: DateTime.now(), clearError: true),
        );
        return 0;
      }

      final now = DateTime.now();
      final matched = <RssItem>[];
      for (final entry in result.entries) {
        // v1: only keep entries that match a bound subject.
        for (final binding in bindings) {
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

      final added = await _store.insertItemsIgnoreDup(matched);
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
      await _store.upsertSource(
        source.copyWith(
          lastFetchAt: DateTime.now(),
          lastError: error.toString().replaceFirst('Exception: ', ''),
        ),
      );
      rethrow;
    }
  }

  Future<List<RssItem>> itemsForSubject(int subjectId, {bool unreadOnly = false}) =>
      _store.listItems(subjectId: subjectId, unreadOnly: unreadOnly, limit: 50);

  Future<List<RssItem>> recentItems({int limit = 40}) =>
      _store.listItems(limit: limit);

  Future<void> markItemRead(int itemId) async {
    await _store.markRead(itemId);
    await reload();
  }

  Future<void> markSubjectRead(int subjectId) async {
    await _store.markSubjectRead(subjectId);
    await reload();
  }

  void clearMessage() => state = state.copyWith(clearMessage: true);

  String _defaultKeywords(ScheduleItem item) {
    // Prefer shorter Chinese name as single token; also keep original name if different.
    final parts = <String>[];
    if (item.nameCn.trim().isNotEmpty) parts.add(item.nameCn.trim());
    if (item.name.trim().isNotEmpty &&
        item.name.trim() != item.nameCn.trim()) {
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
