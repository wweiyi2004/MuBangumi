import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/storage/browsing_store.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:path/path.dart' as path;

void main() {
  late Directory directory;
  late BrowsingStore store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'mubangumi-browsing-test-',
    );
    store = BrowsingStore(
      databasePath: path.join(directory.path, 'browsing.sqlite'),
    );
  });
  tearDown(() async {
    await store.close();
    if (directory.parent.resolveSymbolicLinksSync() !=
            Directory.systemTemp.resolveSymbolicLinksSync() ||
        !path.basename(directory.path).startsWith('mubangumi-browsing-test-')) {
      throw StateError('Unexpected test directory');
    }
    await directory.delete(recursive: true);
  });

  test(
    'library settings and typed searches survive reopen and isolate accounts',
    () async {
      await store.saveLibrary('Alice', {
        'subject_type': null,
        'collection_type': 2,
        'sort': 'title',
      });
      await store.saveLibrary('bob', {'subject_type': 1, 'sort': 'rating'});
      await store.rememberSearch(
        'alice',
        const RecentSearch(keyword: '银河', subjectType: SubjectType.book),
      );
      await store.rememberSearch(
        'bob',
        const RecentSearch(keyword: '人物', target: 'person'),
      );
      await store.close();
      expect(await store.readLibrary(' ALICE '), {
        'subject_type': null,
        'collection_type': 2,
        'sort': 'title',
      });
      expect(
        (await store.readSearches('alice')).single.subjectType,
        SubjectType.book,
      );
      expect((await store.readSearches('bob')).single.target, 'person');
      await store.clearSearches('alice');
      expect(await store.readSearches('alice'), isEmpty);
      expect(await store.readSearches('bob'), hasLength(1));
      expect((await store.readLibrary('alice'))!['sort'], 'title');
    },
  );

  test(
    'history is bounded, deduplicated and promoted when searched again',
    () async {
      for (var i = 0; i < 20; i++) {
        await store.rememberSearch('alice', RecentSearch(keyword: 'query $i'));
      }
      await store.rememberSearch(
        'alice',
        const RecentSearch(keyword: ' QUERY 10 '),
      );
      final recent = await store.readSearches('alice');
      expect(recent, hasLength(BrowsingStore.historyLimit));
      expect(recent.first.keyword, 'QUERY 10');
      expect(
        recent.where((item) => item.keyword.toLowerCase() == 'query 10'),
        hasLength(1),
      );
      await store.rememberSearch(
        'alice',
        const RecentSearch(keyword: 'QUERY 10', subjectType: SubjectType.book),
      );
      expect(
        (await store.readSearches(
          'alice',
        )).take(2).map((item) => item.subjectType),
        [SubjectType.book, SubjectType.anime],
      );
    },
  );

  test(
    'clear respects queued writes and rejects empty or unsupported searches',
    () async {
      final first = store.rememberSearch(
        'alice',
        const RecentSearch(keyword: 'old'),
      );
      final clear = store.clearSearches('alice');
      final last = store.rememberSearch(
        'alice',
        const RecentSearch(keyword: 'new'),
      );
      await Future.wait([first, clear, last]);
      await store.rememberSearch('', const RecentSearch(keyword: 'ignored'));
      await store.rememberSearch('alice', const RecentSearch(keyword: '   '));
      await store.rememberSearch(
        'alice',
        const RecentSearch(keyword: 'ignored', target: 'invalid'),
      );
      expect((await store.readSearches('alice')).map((item) => item.keyword), [
        'new',
      ]);
      expect(await store.readSearches(''), isEmpty);
    },
  );
}
