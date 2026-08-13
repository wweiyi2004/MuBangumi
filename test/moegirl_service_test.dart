import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/network/moegirl_service.dart';
import 'package:mubangumi/models/bangumi_models.dart';
import 'package:mubangumi/screens/moegirl_detail_screen.dart';

void main() {
  test('accepts an exact non-disambiguation entry', () async {
    final requests = <RequestOptions>[];
    final service = _service((options) {
      requests.add(options);
      return {
        'query': {
          'pages': [
            {
              'pageid': 435173,
              'title': '葬送的芙莉莲',
              'extract': '''
<p>《<b>葬送的芙莉莲</b>》（日语：葬送のフリーレン）是一部漫画及动画作品。</p>
<h2>作品介绍</h2>
<p>本作获得多项漫画奖。</p>
<h3>出版信息</h3>
<ul><li>日文版由小学馆发行。</li><li>中文版已出版。</li></ul>
''',
              'fullurl': 'https://zh.moegirl.org.cn/葬送的芙莉莲',
              'lastrevid': 123,
            },
          ],
        },
      };
    });

    final entry = await service.findForSubject(_frieren);

    expect(entry?.title, '葬送的芙莉莲');
    expect(entry?.revisionId, 123);
    expect(entry?.sections, hasLength(2));
    expect(entry?.sections.first.title, '作品介绍');
    expect(entry?.sections.last.body, contains('• 日文版由小学馆发行。'));
    expect(requests, hasLength(1));
    expect(requests.single.queryParameters['origin'], '*');
    expect(requests.single.queryParameters['exsectionformat'], 'raw');
    expect(requests.single.queryParameters.containsKey('explaintext'), isFalse);
  });

  test(
    'rejects disambiguation and selects a compatible prefix result',
    () async {
      final service = _service((options) {
        if (options.queryParameters['generator'] == 'prefixsearch') {
          return {
            'query': {
              'pages': [
                {
                  'pageid': 36981,
                  'title': '日常(漫画)',
                  'extract': '《日常》（日语：日常）是一部漫画，并有动画等衍生作品。',
                  'fullurl': 'https://zh.moegirl.org.cn/日常(漫画)',
                },
                {
                  'pageid': 242517,
                  'title': '日常番',
                  'extract': '日常番是一类动画题材。',
                  'fullurl': 'https://zh.moegirl.org.cn/日常番',
                },
              ],
            },
          };
        }
        if (options.queryParameters['titles'] == '日常(漫画)') {
          return {
            'query': {
              'pages': [
                {
                  'pageid': 36981,
                  'title': '日常(漫画)',
                  'extract': '''
<p>《日常》（日语：日常）是一部漫画，并有动画等衍生作品。</p>
<h2>故事简介</h2><p>围绕高中女生们展开的日常故事。</p>
''',
                  'fullurl': 'https://zh.moegirl.org.cn/日常(漫画)',
                },
              ],
            },
          };
        }
        return {
          'query': {
            'pages': [
              {
                'pageid': 629068,
                'title': '日常',
                'extract': '日常可以指多个条目。',
                'pageprops': {'disambiguation': ''},
                'fullurl': 'https://zh.moegirl.org.cn/日常',
              },
            ],
          },
        };
      });

      final entry = await service.findForSubject(_nichijou);

      expect(entry?.title, '日常(漫画)');
      expect(entry?.sections.single.title, '故事简介');
    },
  );

  test(
    'does not return an incompatible or low-confidence prefix result',
    () async {
      final service = _service((options) {
        if (options.queryParameters['generator'] == 'prefixsearch') {
          return {
            'query': {
              'pages': [
                {
                  'pageid': 1,
                  'title': '日常(歌曲)',
                  'extract': '《日常》是一首歌曲。',
                  'fullurl': 'https://zh.moegirl.org.cn/日常(歌曲)',
                },
                {
                  'pageid': 2,
                  'title': '日常番',
                  'extract': '日常番是一类动画题材。',
                  'fullurl': 'https://zh.moegirl.org.cn/日常番',
                },
              ],
            },
          };
        }
        return {
          'query': {
            'pages': [
              {
                'pageid': 629068,
                'title': '日常',
                'extract': '日常可以指多个条目。',
                'pageprops': {'disambiguation': ''},
                'fullurl': 'https://zh.moegirl.org.cn/日常',
              },
            ],
          },
        };
      });

      expect(await service.findForSubject(_nichijou), isNull);
    },
  );

  test('treats a disabled optional prefix module as no match', () async {
    final service = _service((options) {
      if (options.queryParameters['generator'] == 'prefixsearch') {
        return {
          'error': {
            'code': 'action-notallowed',
            'info': 'Unauthorized API call',
          },
        };
      }
      return {
        'query': {
          'pages': [
            {
              'pageid': 629068,
              'title': '日常',
              'extract': '日常可以指多个条目。',
              'pageprops': {'disambiguation': ''},
              'fullurl': 'https://zh.moegirl.org.cn/日常',
            },
          ],
        },
      };
    });

    expect(await service.findForSubject(_nichijou), isNull);
  });

  test('retries one transient connection failure', () async {
    var requestCount = 0;
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requestCount++;
          if (requestCount == 1) {
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.connectionError,
                message: 'temporary connection failure',
              ),
            );
            return;
          }
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: {
                'query': {
                  'pages': [
                    {
                      'pageid': 435173,
                      'title': '葬送的芙莉莲',
                      'extract': '<p>《葬送的芙莉莲》是一部漫画及动画作品。</p>',
                      'fullurl': 'https://zh.moegirl.org.cn/葬送的芙莉莲',
                    },
                  ],
                },
              },
            ),
          );
        },
      ),
    );
    final service = MoegirlService(dio: dio, cacheEnabled: false);

    final entry = await service.findForSubject(_frieren);

    expect(entry?.title, '葬送的芙莉莲');
    expect(requestCount, 2);
  });

  test('strips HTML tags and decodes entities in heading-less extracts', () async {
    final service = _service((options) {
      return {
        'query': {
          'pages': [
            {
              'pageid': 777,
              'title': '短页',
              'extract':
                  '<p>《<b>短页</b>》是一部<a href="/wiki/某作品">作品</a>，由A&amp;B制作。</p>',
              'fullurl': 'https://zh.moegirl.org.cn/短页',
            },
          ],
        },
      };
    });

    final entry = await service.findForSubject(_stubPage);

    expect(entry?.title, '短页');
    expect(entry?.extract, isNot(contains('<')));
    expect(entry?.extract, contains('A&B'));
  });

  test('classifies an HTTP error as a request failure, not a connection issue',
      () async {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.badResponse,
              response: Response<dynamic>(
                requestOptions: options,
                statusCode: 403,
                data: '<html>WAF block</html>',
              ),
            ),
          );
        },
      ),
    );
    final service = MoegirlService(dio: dio, cacheEnabled: false);

    await expectLater(
      service.findForSubject(_frieren),
      throwsA(
        isA<MoegirlException>().having(
          (e) => e.message,
          'message',
          contains('HTTP 403'),
        ),
      ),
    );
  });

  test('keeps the prefix result when the full re-fetch yields no usable entry',
      () async {
    final service = _service((options) {
      if (options.queryParameters['generator'] == 'prefixsearch') {
        return {
          'query': {
            'pages': [
              {
                'pageid': 36981,
                'title': '日常(漫画)',
                'extract': '《日常》（日语：日常）是一部漫画，并有动画等衍生作品。',
                'fullurl': 'https://zh.moegirl.org.cn/日常(漫画)',
              },
            ],
          },
        };
      }
      if (options.queryParameters['titles'] == '日常(漫画)') {
        return {
          'query': {'pages': <Object?>[]},
        };
      }
      return {
        'query': {
          'pages': [
            {
              'pageid': 629068,
              'title': '日常',
              'extract': '日常可以指多个条目。',
              'pageprops': {'disambiguation': ''},
              'fullurl': 'https://zh.moegirl.org.cn/日常',
            },
          ],
        },
      };
    });

    final entry = await service.findForSubject(_nichijou);

    expect(entry?.title, '日常(漫画)');
  });

  test('entry cache JSON round-trips', () {
    const entry = MoegirlEntry(
      pageId: 12,
      title: '标题',
      extract: '简介',
      url: 'https://zh.moegirl.org.cn/标题',
      revisionId: 34,
      sections: [MoegirlSection(title: '章节', body: '内容', level: 2)],
    );

    final restored = MoegirlEntry.fromJson(entry.toJson());

    expect(restored.pageId, entry.pageId);
    expect(restored.title, entry.title);
    expect(restored.extract, entry.extract);
    expect(restored.url, entry.url);
    expect(restored.revisionId, entry.revisionId);
    expect(restored.sections.single.title, '章节');
    expect(restored.sections.single.body, '内容');
  });

  testWidgets('renders an entry as native expandable sections', (tester) async {
    const entry = MoegirlEntry(
      pageId: 12,
      title: '测试条目',
      extract: '原生导语',
      url: 'https://zh.moegirl.org.cn/测试条目',
      sections: [MoegirlSection(title: '作品介绍', body: '原生章节正文', level: 2)],
    );

    await tester.pumpWidget(
      const MaterialApp(home: MoegirlDetailScreen(entry: entry)),
    );

    expect(find.text('萌娘百科补充资料'), findsOneWidget);
    expect(find.text('导语'), findsOneWidget);
    expect(find.text('作品介绍'), findsOneWidget);
    expect(find.text('原生章节正文'), findsOneWidget);
  });
}

MoegirlService _service(
  Map<String, dynamic> Function(RequestOptions options) responseFor,
) {
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        handler.resolve(
          Response<dynamic>(
            requestOptions: options,
            statusCode: 200,
            data: responseFor(options),
          ),
        );
      },
    ),
  );
  return MoegirlService(dio: dio, cacheEnabled: false);
}

const _frieren = Subject(
  id: 400602,
  type: SubjectType.anime,
  name: '葬送のフリーレン',
  nameCn: '葬送的芙莉莲',
  imageUrl: '',
  summary: '',
  episodeCount: 28,
  score: 0,
  rank: 0,
  date: '',
);

const _nichijou = Subject(
  id: 9912,
  type: SubjectType.anime,
  name: '日常',
  nameCn: '日常',
  imageUrl: '',
  summary: '',
  episodeCount: 26,
  score: 0,
  rank: 0,
  date: '',
);

const _stubPage = Subject(
  id: 700001,
  type: SubjectType.anime,
  name: 'Short Page',
  nameCn: '短页',
  imageUrl: '',
  summary: '',
  episodeCount: 1,
  score: 0,
  rank: 0,
  date: '',
);
