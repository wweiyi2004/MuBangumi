import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/network/rss_fetcher.dart';
import 'package:mubangumi/core/storage/rss_store.dart';
import 'package:mubangumi/models/rss_models.dart';
import 'package:mubangumi/state/rss_controller.dart';

void main() {
  test(
    'three workers let fast feeds finish around a slow or failed feed',
    () async {
      final store = _FakeRssStore();
      for (var id = 1; id <= 5; id++) {
        store.sources.add(
          RssSource(id: id, name: '源$id', url: '$id', etag: 'tag$id'),
        );
        store.bindings.add(
          RssBinding(
            id: id,
            sourceId: id,
            subjectId: id,
            subjectName: '作品',
            seasonKey: '2026Q3',
            matchKeywords: '作品',
          ),
        );
      }
      final fetcher = _ControlledFetcher();
      final controller = RssController(store, fetcher);
      addTearDown(controller.dispose);
      await _waitFor(() => controller.state.loaded);
      final refresh = controller.refreshAll();
      await _waitFor(() => fetcher.pending.length == 3);
      expect(fetcher.pending.keys, ['1', '2', '3']);
      expect(fetcher.etags['1'], 'tag1');
      fetcher.pending['2']!.completeError(StateError('offline'));
      fetcher.pending['3']!.complete(_feed);
      await _waitFor(() => fetcher.pending.length == 5);
      expect(fetcher.pending['1']!.isCompleted, isFalse);
      expect(controller.state.totalUnread, 1);
      fetcher.pending['4']!.complete(_feed);
      fetcher.pending['5']!.complete(_feed);
      await _waitFor(() => controller.state.totalUnread == 3);
      fetcher.pending['1']!.complete(_feed);
      await refresh;
      expect(controller.state.refreshing, isFalse);
      expect(controller.state.totalUnread, 4);
      expect(controller.state.message, contains('+4 条'));
      expect(controller.state.message, contains('1 个源失败'));
    },
  );
  test('reload failure is not overwritten by an add success message', () async {
    final store = _FakeRssStore();
    final controller = RssController(store, RssFetcher());
    addTearDown(controller.dispose);
    await _waitFor(() => controller.state.loaded);

    store.readError = Exception('database unavailable');
    await controller.addSource(name: 'Feed', url: 'https://example.com/rss');

    expect(controller.state.loaded, isFalse);
    expect(controller.state.message, contains('读取更新源失败'));
    expect(controller.state.message, isNot(contains('已添加更新源')));
  });
}

class _FakeRssStore extends RssStore {
  _FakeRssStore() : super.test();

  final List<RssSource> sources = [];
  final List<RssBinding> bindings = [];
  int unread = 0;
  Object? readError;

  void _throwIfNeeded() {
    final error = readError;
    if (error != null) throw error;
  }

  @override
  Future<List<RssSource>> listSources() async {
    _throwIfNeeded();
    return List<RssSource>.from(sources);
  }

  @override
  Future<List<RssBinding>> listBindings({int? subjectId, int? sourceId}) async {
    _throwIfNeeded();
    return bindings;
  }

  @override
  Future<Map<int, int>> unreadCountsBySubject() async {
    _throwIfNeeded();
    return const {};
  }

  @override
  Future<int> totalUnread() async {
    _throwIfNeeded();
    return unread;
  }

  @override
  Future<RssSource> upsertSource(RssSource source) async {
    final saved = source.copyWith(id: source.id == 0 ? 1 : source.id);
    sources.removeWhere((item) => item.id == saved.id);
    sources.add(saved);
    return saved;
  }

  @override
  Future<int> insertItemsIgnoreDup(List<RssItem> items) async {
    unread += items.length;
    return items.length;
  }
}

const _feed = RssFetchResult(
  entries: [
    RssFeedEntry(guid: '1', title: '作品 01', link: 'https://example.com/1'),
  ],
);

class _ControlledFetcher extends RssFetcher {
  final pending = <String, Completer<RssFetchResult>>{};
  final etags = <String, String>{};
  @override
  Future<RssFetchResult> fetch(
    String url, {
    String etag = '',
    String lastModified = '',
  }) {
    etags[url] = etag;
    final response = Completer<RssFetchResult>();
    pending[url] = response;
    return response.future;
  }
}

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('condition not reached');
}
