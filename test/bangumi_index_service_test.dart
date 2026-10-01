import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/network/community_service.dart';
import 'package:mubangumi/models/bangumi_index.dart';
import 'package:mubangumi/models/community_topic_submission.dart';
import 'package:mubangumi/core/shortcuts/shared_bangumi_link.dart';

void main() {
  const index = BangumiIndex(
    id: 7,
    ownerId: 1,
    title: '合成番剧单',
    isPrivate: true,
  );
  const entry = BangumiIndexEntry(id: 11, subjectId: 42, order: 3);
  test(
    'native index parsing and pagination preserve inaccessible subjects without inventing data',
    () async {
      final dio = Dio();
      final requests = <RequestOptions>[];
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) {
            requests.add(request);
            handler.resolve(
              Response(
                requestOptions: request,
                statusCode: 200,
                data: request.path.endsWith('/related')
                    ? {
                        'total': 2,
                        'data': [
                          {
                            'id': 11,
                            'sid': 42,
                            'order': 0,
                            'comment': '推荐语',
                            'subject': {
                              'id': 42,
                              'type': 2,
                              'nameCN': '中文作品',
                              'name': 'Original',
                              'rating': {'score': 8.4},
                            },
                          },
                          {'id': 12, 'sid': 43, 'order': 1},
                        ],
                      }
                    : {
                        'total': 1,
                        'data': [
                          {
                            'id': 7,
                            'uid': 1,
                            'title': '合成番剧单',
                            'private': true,
                          },
                        ],
                      },
              ),
            );
          },
        ),
      );
      final service = CommunityService(p1Dio: dio)
        ..setAccessToken('synthetic')
        ..setCurrentUsername('alice');
      addTearDown(service.dispose);
      expect(
        (await service.loadIndexes(
          mode: BangumiIndexMode.created,
        )).data.single.isPrivate,
        isTrue,
      );
      expect(requests.first.path, '/p1/users/alice/indexes');
      final page = await service.loadIndexEntries(7);
      expect(page.rawCount, 2);
      expect(page.data.first.subject?.displayName, '中文作品');
      expect(page.data.last.subject, isNull);
      expect(requests.last.queryParameters['type'], 2);
      final link = SharedBangumiLink.parse('https://bgm.tv/index/7')!;
      expect(link.kind, SharedBangumiKind.directory);
      expect(link.id, 7);
    },
  );
  for (final action in [
    'create',
    'edit',
    'collect',
    'uncollect',
    'add',
    'note',
    'remove',
    'delete',
  ]) {
    test('old account $action response is discarded without replay', () async {
      final gate = Completer<void>(), started = Completer<void>();
      var writes = 0;
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) async {
            if (request.method == 'GET') {
              handler.resolve(
                Response(
                  requestOptions: request,
                  statusCode: 200,
                  data: const {'total': 0, 'data': []},
                ),
              );
              return;
            }
            writes++;
            started.complete();
            await gate.future;
            handler.resolve(
              Response(
                requestOptions: request,
                statusCode: 200,
                data: const {'id': 8},
              ),
            );
          },
        ),
      );
      final service = CommunityService(p1Dio: dio)
        ..setAccessToken('synthetic')
        ..setCurrentUsername('alice');
      addTearDown(service.dispose);
      final Future<Object?> pending = switch (action) {
        'create' => service.saveIndex(
          title: '目录',
          description: '',
          isPrivate: false,
        ),
        'edit' => service.saveIndex(
          original: index,
          title: '目录',
          description: '',
          isPrivate: true,
        ),
        'collect' => service.collectIndex(7, true),
        'uncollect' => service.collectIndex(7, false),
        'add' => service.addIndexSubject(7, 42),
        'note' => service.updateIndexEntry(7, entry, order: 2, comment: '备注'),
        'remove' => service.removeIndexEntry(7, 11),
        _ => service.deleteIndex(7),
      };
      final expectation = expectLater(pending, throwsA(isA<FormatException>()));
      await started.future;
      service.setCurrentUsername('bob');
      gate.complete();
      await expectation;
      expect(writes, 1);
    });
  }
  test('uncertain directory creation is not automatically retried', () async {
    var writes = 0;
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          writes++;
          handler.reject(
            DioException(
              requestOptions: request,
              type: DioExceptionType.receiveTimeout,
            ),
          );
        },
      ),
    );
    final service = CommunityService(p1Dio: dio)
      ..setAccessToken('synthetic')
      ..setCurrentUsername('alice');
    addTearDown(service.dispose);
    await expectLater(
      service.saveIndex(title: '目录', description: '', isPrivate: false),
      throwsA(isA<CommunitySubmissionUncertain>()),
    );
    expect(writes, 1);
  });
}
