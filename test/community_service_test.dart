import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/network/community_service.dart';
import 'package:mubangumi/models/community_models.dart';

void main() {
  test('me timeline keeps items whose user object is omitted by the API', () async {
    final service = _service(
      (options) => Response<List<dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: [
          {
            'id': 71228734,
            'uid': 763686,
            'cat': 4,
            'type': 2,
            'createdAt': 1786588552,
            'memo': {
              'progress': {
                'single': {
                  'episode': {
                    'id': 1656013,
                    'subjectID': 590353,
                    'sort': 6,
                    'type': 0,
                    'name': 'EP',
                  },
                  'subject': {
                    'id': 590353,
                    'name': 'Example',
                    'nameCN': '示例动画',
                    'type': 2,
                  },
                },
              },
            },
          },
        ],
      ),
    );
    service.setCurrentUsername('wweiyi', nickname: '维依');

    final items = await service.loadTimeline(CommunityTimelineMode.me);

    expect(items, hasLength(1));
    expect(items.single.user.username, 'wweiyi');
    expect(items.single.user.displayName, '维依');
    expect(items.single.description, '看过 示例动画 EP.6');
  });

  test('user profile timeline keeps user-less items with the profile username',
      () async {
    final service = _service(
      (options) => Response<List<dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: [
          {
            'id': 42,
            'uid': 7,
            'cat': 5,
            'type': 1,
            'createdAt': 1786588552,
            'memo': {
              'status': {'tsukkomi': '你好'},
            },
          },
        ],
      ),
    );

    final items = await service.loadUserTimeline('alice');

    expect(items, hasLength(1));
    expect(items.single.user.id, 7);
    expect(items.single.user.username, 'alice');
    expect(items.single.user.displayName, 'alice');
    expect(items.single.description, '发表了吐槽');
  });

  test('cached me timeline keeps user-less items with the signed-in identity',
      () {
    final service = CommunityService.test();
    service.setCurrentUsername('wweiyi', nickname: '维依');

    final items = service.decodeCachedTimeline(CommunityTimelineMode.me, [
      {
        'id': 71228734,
        'uid': 763686,
        'cat': 4,
        'type': 2,
        'createdAt': 1786588552,
        'memo': {
          'progress': {
            'single': {
              'episode': {
                'id': 1656013,
                'subjectID': 590353,
                'sort': 6,
                'type': 0,
                'name': 'EP',
              },
              'subject': {
                'id': 590353,
                'name': 'Example',
                'nameCN': '示例动画',
                'type': 2,
              },
            },
          },
        },
      },
    ]);

    expect(items, hasLength(1));
    expect(items.single.user.id, 763686);
    expect(items.single.user.username, 'wweiyi');
    expect(items.single.user.displayName, '维依');
    expect(items.single.description, '看过 示例动画 EP.6');
  });
}

CommunityService _service(Response<Object?> Function(RequestOptions) respond) {
  final dio = Dio(BaseOptions(baseUrl: 'https://next.bgm.tv'));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) => handler.resolve(respond(options)),
    ),
  );
  return CommunityService.test(p1Dio: dio);
}
