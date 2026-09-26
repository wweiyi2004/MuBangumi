import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/network/bangumi_api.dart';
import 'package:mubangumi/core/storage/snapshot_cache.dart';
import 'package:mubangumi/features/discover/application/discover_controller.dart';
import 'package:mubangumi/features/discover/domain/discover_query.dart';
import 'package:mubangumi/models/bangumi_models.dart';

DiscoverQuery query([String keyword = '']) =>
    DiscoverQuery(keyword: keyword, browseYear: 2026, browseQuarter: 2);

Subject subject(int id) => Subject(
  id: id,
  name: 'fixture $id',
  nameCn: '',
  imageUrl: '',
  summary: '',
  episodeCount: 12,
  score: 0,
  rank: 0,
  date: '',
);

class PendingApi extends BangumiApi {
  final requests =
      <({String keyword, int offset, Completer<List<Subject>> result})>[];
  Future<List<Subject>> request(String keyword, int offset) {
    final result = Completer<List<Subject>>();
    requests.add((keyword: keyword, offset: offset, result: result));
    return result.future;
  }

  @override
  Future<List<Subject>> searchSubjects(
    String keyword, {
    int limit = 24,
    int offset = 0,
    String sort = 'match',
    num minimumRating = 0,
    bool ratingExclusive = false,
    int startYear = 0,
    int endYear = 0,
    List<String> tags = const [],
    List<String> metaTags = const [],
    SubjectType subjectType = SubjectType.anime,
  }) => request(keyword, offset);

  @override
  Future<List<Subject>> browseSubjects({
    required SubjectType type,
    int? year,
    int? month,
    String sort = 'rank',
    int limit = 24,
    int offset = 0,
  }) => request('browse', offset);
}

class MemoryCache extends SnapshotCache {
  final read = Completer<List<Subject>?>();
  final saved = <List<Subject>>[];
  @override
  Future<List<Subject>?> readDiscoverBrowse(String key) => read.future;
  @override
  Future<void> writeDiscoverBrowse(String key, List<Subject> subjects) async {
    saved.add(subjects);
  }
}

void main() {
  late PendingApi api;
  late MemoryCache cache;
  late DiscoverController controller;
  var notifications = 0;
  setUp(() {
    api = PendingApi();
    cache = MemoryCache();
    notifications = 0;
    controller = DiscoverController(
      api: api,
      cache: cache,
      query: query(),
      onChanged: () => notifications++,
    );
  });
  tearDown(() => controller.dispose());

  test(
    'typing invalidates a pending response before the debounce runs',
    () async {
      final old = controller.start(query('old'));
      controller.prepareSearch(query('new'));
      api.requests.single.result.complete([subject(1)]);
      await old;
      expect(controller.subjects, isEmpty);
      expect(controller.loading, isTrue);
      final next = controller.start(query('new'));
      api.requests.last.result.complete([subject(2)]);
      await next;
      expect(controller.subjects.single.id, 2);
      expect(controller.loading, isFalse);
    },
  );

  test(
    'pagination has one request and cannot append into a newer query',
    () async {
      final first = controller.start(query('old'));
      api.requests.single.result.complete(List.generate(24, subject));
      await first;
      final more = controller.loadMore();
      await controller.loadMore();
      expect(api.requests.length, 2);
      expect(api.requests.last.offset, 24);
      final next = controller.start(query('new'));
      api.requests.last.result.complete([subject(100)]);
      await next;
      api.requests[1].result.complete([subject(24)]);
      await more;
      expect(controller.subjects.map((s) => s.id), [100]);
      expect(controller.hasMore, isFalse);
    },
  );

  test('an empty network result supersedes a hydrated browse cache', () async {
    final load = controller.start(query());
    cache.read.complete([subject(1)]);
    await Future<void>.delayed(Duration.zero);
    expect(controller.subjects.single.id, 1);
    expect(controller.refreshing, isTrue);
    api.requests.single.result.complete([]);
    await load;
    expect(controller.subjects, isEmpty);
    expect(controller.refreshing, isFalse);
    expect(cache.saved.single, isEmpty);
  });

  test('late cache cannot overwrite a completed network response', () async {
    final load = controller.start(query());
    api.requests.single.result.complete([subject(2)]);
    await load;
    cache.read.complete([subject(1)]);
    await Future<void>.delayed(Duration.zero);
    expect(controller.subjects.single.id, 2);
  });

  test(
    'disposed controller ignores completion and cannot load another page',
    () async {
      final load = controller.start(query('old'));
      final before = notifications;
      controller.dispose();
      api.requests.single.result.complete(List.generate(24, subject));
      await load;
      await controller.loadMore();
      await controller.start(query('new'));
      expect(notifications, before);
      expect(api.requests.length, 1);
      expect(controller.subjects, isEmpty);
    },
  );
}
