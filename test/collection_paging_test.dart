import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/network/bangumi_api.dart';

void main() {
  test('publishes a page before requesting the rest of a collection', () async {
    final offsets = <int>[];
    final dio = _pages(offsets);
    final api = BangumiApi(dio: dio);
    final firstPage = Completer<void>();
    final release = Completer<void>();
    final snapshots = <List<int>>[];
    final load = api.getUserCollections(
      'tester',
      onPage: (items) async {
        snapshots.add(items.map((item) => item.subjectId).toList());
        expect(() => items.clear(), throwsUnsupportedError);
        if (!firstPage.isCompleted) {
          firstPage.complete();
          await release.future;
        }
        return true;
      },
    );
    await firstPage.future;
    expect(offsets, [0]);
    expect(snapshots, [
      [1],
    ]);
    release.complete();
    expect((await load).map((item) => item.subjectId), [1, 2, 3]);
    expect(offsets, [0, 1, 2]);
    expect(snapshots, [
      [1],
      [1, 2],
    ]);
  });

  test('a superseded session can stop requesting further pages', () async {
    final offsets = <int>[];
    final api = BangumiApi(dio: _pages(offsets));
    await api.getUserCollections('tester', onPage: (_) async => false);
    expect(offsets, [0]);
  });
}

Dio _pages(List<int> offsets) {
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        final offset = options.queryParameters['offset'] as int;
        offsets.add(offset);
        handler.resolve(
          Response(
            requestOptions: options,
            data: {
              'total': 3,
              'data': [
                {
                  'subject_id': offset + 1,
                  'type': 3,
                  'subject': {'id': offset + 1, 'name': '作品', 'type': 2},
                },
              ],
            },
          ),
        );
      },
    ),
  );
  return dio;
}
