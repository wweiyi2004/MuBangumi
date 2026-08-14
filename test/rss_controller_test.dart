import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/network/rss_fetcher.dart';
import 'package:mubangumi/core/storage/rss_store.dart';
import 'package:mubangumi/models/rss_models.dart';
import 'package:mubangumi/state/rss_controller.dart';

void main() {
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
    return const [];
  }

  @override
  Future<Map<int, int>> unreadCountsBySubject() async {
    _throwIfNeeded();
    return const {};
  }

  @override
  Future<int> totalUnread() async {
    _throwIfNeeded();
    return 0;
  }

  @override
  Future<RssSource> upsertSource(RssSource source) async {
    final saved = source.copyWith(id: source.id == 0 ? 1 : source.id);
    sources.add(saved);
    return saved;
  }
}

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('condition not reached');
}
