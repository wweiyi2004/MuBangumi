import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/network/rss_fetcher.dart';
import 'package:mubangumi/core/storage/rss_store.dart';
import 'package:mubangumi/models/rss_models.dart';
import 'package:mubangumi/models/schedule_models.dart';
import 'package:mubangumi/state/rss_controller.dart';
import 'package:path/path.dart' as path;

void main() {
  late Directory directory;
  late RssStore store;
  late RssController controller;
  late _StableFeed fetcher;
  late int sourceId;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('mubangumi-rss-rules-');
    store = RssStore.test(
      databasePath: path.join(directory.path, 'rss.sqlite'),
    );
    final source = await store.upsertSource(
      const RssSource(id: 0, name: 'Feed', url: 'https://example.invalid/feed'),
    );
    sourceId = source.id;
    await store.upsertBinding(
      RssBinding(
        id: 0,
        sourceId: sourceId,
        subjectId: 1,
        subjectName: 'Alpha',
        matchKeywords: 'Alpha',
      ),
    );
    fetcher = _StableFeed();
    controller = RssController(store, fetcher);
    await _waitFor(() => controller.state.loaded);
    await controller.refreshAll(automatic: true);
    expect((await store.listSources()).single.etag, 'v1');
    expect(await store.listItems(subjectId: 1), hasLength(1));
  });

  tearDown(() async {
    controller.dispose();
    await store.close();
    if (directory.parent.resolveSymbolicLinksSync() !=
            Directory.systemTemp.resolveSymbolicLinksSync() ||
        !path.basename(directory.path).startsWith('mubangumi-rss-rules-')) {
      throw StateError('Unexpected test directory');
    }
    await directory.delete(recursive: true);
  });

  Future<void> bindBeta({bool edit = false}) => controller.bindSubject(
    sourceId: sourceId,
    item: ScheduleItem(
      subjectId: edit ? 1 : 2,
      name: 'Beta',
      nameCn: '',
      imageUrl: '',
    ),
    season: SeasonKey.current(),
    matchKeywords: 'Beta',
  );

  for (final edit in [false, true]) {
    test(
      'rule ${edit ? 'edit' : 'addition'} rematches an unchanged feed',
      () async {
        // Unchanged rules still use conditional requests.
        await controller.refreshAll(automatic: true);
        expect(fetcher.validators.last, ('v1', 'last-v1'));
        await bindBeta(edit: edit);
        final source = (await store.listSources()).single;
        expect(source.etag, isEmpty);
        expect(source.lastModified, isEmpty);
        expect(source.lastFetchAt, isNull);
        await controller.refreshAll(automatic: true);
        expect(fetcher.validators.last, ('', ''));
        final items = await store.listItems(subjectId: edit ? 1 : 2);
        expect(items.any((item) => item.guid == 'beta'), isTrue);
        expect((await store.listSources()).single.etag, 'v1');
      },
    );
  }

  for (final response in ['304', '200', 'error']) {
    test(
      'late $response cannot restore validators cleared by a rule edit',
      () async {
        final gate = Completer<RssFetchResult>();
        fetcher.next = gate;
        final refreshing = controller.refreshAll(automatic: true);
        await _waitFor(() => fetcher.validators.length == 2);
        await bindBeta();
        if (response == 'error') {
          gate.completeError(StateError('synthetic offline'));
        } else {
          gate.complete(
            response == '304'
                ? const RssFetchResult(entries: [], notModified: true)
                : _fullFeed,
          );
        }
        await refreshing;
        final source = (await store.listSources()).single;
        expect(source.etag, isEmpty);
        expect(source.lastModified, isEmpty);
        expect(source.lastFetchAt, isNull);
        await controller.refreshAll(automatic: true);
        expect(fetcher.validators.last, ('', ''));
        expect(await store.listItems(subjectId: 2), hasLength(1));
      },
    );
  }
}

const _fullFeed = RssFetchResult(
  etag: 'v1',
  lastModified: 'last-v1',
  entries: [
    RssFeedEntry(
      guid: 'alpha',
      title: 'Alpha 01',
      link: 'https://example.invalid/a',
    ),
    RssFeedEntry(
      guid: 'beta',
      title: 'Beta 01',
      link: 'https://example.invalid/b',
    ),
  ],
);

class _StableFeed extends RssFetcher {
  final validators = <(String, String)>[];
  Completer<RssFetchResult>? next;
  @override
  Future<RssFetchResult> fetch(
    String url, {
    String etag = '',
    String lastModified = '',
  }) async {
    validators.add((etag, lastModified));
    final delayed = next;
    next = null;
    if (delayed != null) return delayed.future;
    return etag == 'v1' || lastModified == 'last-v1'
        ? const RssFetchResult(entries: [], notModified: true)
        : _fullFeed;
  }
}

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('condition not reached');
}
