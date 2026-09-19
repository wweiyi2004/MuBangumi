import 'dart:async';
import 'package:banjian_server/banjian_server.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/features/anime_appreciation/room_comments_sheet.dart';
import 'package:mubangumi/features/anime_appreciation/room_connection.dart';

class _CommentsApi extends RoomApi {
  _CommentsApi() : super(Uri.parse('http://127.0.0.1:43928'));
  final requests = <({Uri uri, Completer<Json> result})>[];
  @override
  Future<Json> request(String path, [Json? body]) {
    final result = Completer<Json>();
    requests.add((uri: Uri.parse(path), result: result));
    return result.future;
  }
}

Json _page(String text, {int? cursor}) => {
  'event': 'event-1',
  'round': 'round-1',
  'revision': 2,
  'total': cursor == null ? 1 : 51,
  'nextCursor': cursor,
  'comments': [
    {'id': 'comment-1', 'text': text, 'hidden': false},
  ],
};

void main() {
  testWidgets(
    'visibility changes revoke in-flight pages and reset historical cursors',
    (tester) async {
      final api = _CommentsApi();
      final live = ValueNotifier(1);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoomCommentsBrowser(
              api: api,
              eventId: 'event-1',
              roundId: 'round-1',
              live: live,
              stateKey: () => '${live.value}',
              isCurrent: () => true,
            ),
          ),
        ),
      );
      api.requests[0].result.complete(_page('公开第一页', cursor: 12));
      await tester.pumpAndSettle();
      await tester.tap(find.text('下一页'));
      await tester.pump();
      expect(api.requests[1].uri.queryParameters['before'], '12');
      live.value = 2;
      await tester.pump();
      expect(find.text('公开第一页'), findsNothing);
      api.requests[1].result.complete(_page('已经撤回的旧响应'));
      await tester.pump();
      expect(find.text('已经撤回的旧响应'), findsNothing);
      await tester.pump(const Duration(milliseconds: 160));
      expect(api.requests[2].uri.queryParameters.containsKey('before'), false);
      api.requests[2].result.complete(_page('自己的评论'));
      await tester.pumpAndSettle();
      expect(find.text('自己的评论'), findsOneWidget);
      expect(find.text('第 1 页'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      live.dispose();
    },
  );
}
