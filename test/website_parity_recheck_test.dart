import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mubangumi/core/network/community_service.dart';
import 'package:mubangumi/core/shortcuts/shared_bangumi_link.dart';
import 'package:mubangumi/models/community_models.dart';
import 'package:mubangumi/navigation/app_destination.dart';
import 'package:mubangumi/screens/shared_bangumi_link_page.dart';
import 'package:mubangumi/widgets/community_rich_content.dart';

const _topic = CommunityTopic(
  id: 42,
  kind: CommunityTopicKind.subject,
  title: '占位标题',
  url: 'https://bgm.tv/rakuen/topic/subject/42',
  webUrl: 'https://bgm.tv/subject/topic/42',
);
const _body =
    '<h1 class="title">官网标题</h1><div class="postTopic" id="post_7">'
    '<div class="topic_content">官网正文</div></div>';

CommunityService _service(Object apiResponse, String htmlResponse) {
  final api = Dio()
    ..interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(Response(requestOptions: options, data: apiResponse));
        },
      ),
    );
  final html = Dio()
    ..interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(
            Response<String>(requestOptions: options, data: htmlResponse),
          );
        },
      ),
    );
  return CommunityService.test(p1Dio: api, htmlDio: html);
}

void main() {
  test(
    'an old subject response cannot initiate a fallback under another account',
    () async {
      final started = Completer<void>();
      final result = Completer<void>();
      var websiteReads = 0;
      final api = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) async {
              started.complete();
              await result.future;
              handler.resolve(
                Response(requestOptions: options, data: <String, dynamic>{}),
              );
            },
          ),
        );
      final html = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              websiteReads++;
              handler.resolve(
                Response<String>(requestOptions: options, data: _body),
              );
            },
          ),
        );
      final service = CommunityService.test(p1Dio: api, htmlDio: html)
        ..setCurrentUsername('alice');
      addTearDown(service.dispose);
      final request = service.loadTopic(_topic);
      await started.future;
      service.setCurrentUsername('bob');
      final assertion = expectLater(request, throwsA(isA<FormatException>()));
      result.complete();
      await assertion;
      expect(websiteReads, 0);
    },
  );
  for (final response in <Map<String, dynamic>>[
    {},
    {'replies': []},
    {
      'replies': [<String, dynamic>{}],
    },
    {
      'replies': [
        {'id': 7},
      ],
    },
  ]) {
    test(
      'incomplete subject P1 data falls back to the website: $response',
      () async {
        final service = _service(response, _body);
        addTearDown(service.dispose);
        final detail = await service.loadTopic(_topic);
        expect(detail.title, '官网标题');
        expect(detail.posts.single.body, '官网正文');
      },
    );
  }

  test(
    'incomplete group P1 rows also fall back to the public website',
    () async {
      final service = _service({
        'replies': [<String, dynamic>{}],
      }, _body);
      addTearDown(service.dispose);
      final detail = await service.loadTopic(
        const CommunityTopic(
          id: 42,
          kind: CommunityTopicKind.group,
          title: '占位',
          url: '',
          webUrl: 'https://bgm.tv/group/topic/42',
        ),
      );
      expect(detail.posts.single.body, '官网正文');
    },
  );

  for (final path in [
    'group/topic',
    'subject/topic',
    'ep',
    'person',
    'character',
  ]) {
    testWidgets('shared $path anchor reaches the native discussion route', (
      tester,
    ) async {
      TopicRoute? destination;
      await tester.pumpWidget(
        ProviderScope(
          child: AppRouteScope(
            resolve: (route) {
              destination = route as TopicRoute;
              return const Text('native discussion');
            },
            child: MaterialApp(
              home: SharedBangumiLinkPage(
                link: SharedBangumiLink.parse(
                  'https://bgm.tv/$path/42#post_7',
                )!,
              ),
            ),
          ),
        ),
      );
      expect(destination!.topic.targetPostId, 7);
      expect(destination!.topic.webUrl, endsWith('#post_7'));
    });
  }

  test(
    'subject challenge page is an error rather than an empty thread',
    () async {
      final service = _service(
        {},
        '<html><title>Just a moment...</title></html>',
      );
      addTearDown(service.dispose);
      await expectLater(
        service.loadTopic(_topic),
        throwsA(isA<FormatException>()),
      );
    },
  );

  testWidgets('HTML fallback keeps site smiles at inline smile dimensions', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CommunityRichContent.html(
            '前<img src="/img/smiles/tv/77.gif" class="smile" alt="(bgm100)">后',
          ),
        ),
      ),
    );
    final images = tester.widgetList<Image>(find.byType(Image));
    expect(images.single.height, 22);
    expect(tester.takeException(), isNull);
  });
}
