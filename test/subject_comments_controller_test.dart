import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/network/bangumi_api.dart';
import 'package:mubangumi/core/network/bangumi_support.dart';
import 'package:mubangumi/features/subject_detail/application/subject_comments_controller.dart';

void main() {
  late _Api api;
  late SubjectCommentsController controller;
  setUp(() {
    api = _Api();
    controller = SubjectCommentsController(subjectId: 7, api: () => api);
  });
  tearDown(() => controller.dispose());

  Future<void> seed() async {
    final loading = controller.load();
    api.calls.last.result.complete([
      for (var id = 1; id <= 10; id++) _comment(id),
    ]);
    await loading;
  }

  test(
    'refresh supersedes a pending next page without mixing comments',
    () async {
      await seed();
      final nextPage = controller.load(append: true);
      final refresh = controller.load();
      expect(controller.loadingMore, isFalse);
      api.calls.last.result.complete([_comment(99)]);
      await refresh;
      api.calls[1].result.complete([_comment(11)]);
      await nextPage;
      expect(controller.items.map((c) => c.id), [99]);
      expect(controller.hasMore, isFalse);
      expect(controller.loading, isFalse);
    },
  );

  test(
    'pagination rejects duplicate taps and deduplicates known IDs',
    () async {
      await seed();
      final next = controller.load(append: true);
      await controller.load(append: true);
      expect(api.calls.map((c) => c.page), [1, 2]);
      api.calls.last.result.complete([
        _comment(10),
        _comment(11),
        _comment(0),
        _comment(0),
      ]);
      await next;
      expect(controller.items.map((c) => c.id), [
        ...List.generate(11, (i) => i + 1),
        0,
        0,
      ]);
      await controller.load(append: true);
      expect(api.calls.length, 2);
    },
  );

  test('failed next page retains items and retries the same page', () async {
    await seed();
    final next = controller.load(append: true);
    api.calls.last.result.completeError(Exception('offline'));
    await next;
    expect(controller.items.length, 10);
    expect(controller.loadingMore, isFalse);
    final retry = controller.load(append: true);
    expect(api.calls.last.page, 2);
    api.calls.last.result.complete([_comment(11)]);
    await retry;
    expect(controller.items.length, 11);
  });

  test(
    'refresh error can be retried and pagination waits for refresh',
    () async {
      final load = controller.load();
      await controller.load(append: true);
      expect(api.calls.length, 1);
      api.calls.last.result.completeError(Exception('offline'));
      await load;
      expect(controller.error, '吐槽加载失败');
      final retry = controller.load();
      expect(controller.error, isNull);
      api.calls.last.result.complete([]);
      await retry;
      expect(controller.hasMore, isFalse);
    },
  );

  test(
    'closing prevents pending comment success or error publication',
    () async {
      final closing = SubjectCommentsController(subjectId: 7, api: () => api);
      var notifications = 0;
      closing.addListener(() => notifications++);
      final first = closing.load();
      final second = closing.load();
      closing.dispose();
      final before = notifications;
      api.calls.first.result.complete([_comment(1)]);
      api.calls.last.result.completeError(Exception('late'));
      await Future.wait([first, second]);
      expect(notifications, before);
    },
  );
}

SubjectComment _comment(int id) => SubjectComment(
  id: id,
  userName: 'user$id',
  avatarUrl: '',
  rate: 8,
  comment: 'comment$id',
);

class _Api extends BangumiApi {
  final calls = <({int page, Completer<List<SubjectComment>> result})>[];
  @override
  Future<List<SubjectComment>> getSubjectComments(
    int subjectId, {
    int page = 1,
  }) {
    final result = Completer<List<SubjectComment>>();
    calls.add((page: page, result: result));
    return result.future;
  }
}
