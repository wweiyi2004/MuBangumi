import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/network/community_service.dart';
import 'package:mubangumi/models/community_models.dart';

class ProgressService extends CommunityService {
  final gates = <int, Completer<CommunityTopicDetail>>{};
  @override
  Future<CommunityTopicDetail> loadTopic(
    CommunityTopic topic, {
    bool refresh = false,
  }) => gates
      .putIfAbsent(topic.id, () => Completer<CommunityTopicDetail>())
      .future;
}

void main() {
  for (final changeAccount in [false, true]) {
    test(
      'reply excerpts arrive independently, old-account progress is suppressed ($changeAccount)',
      () async {
        final service = ProgressService()..setCurrentUsername('alice');
        addTearDown(service.dispose);
        final notices = [
          for (var i = 1; i <= 2; i++)
            BangumiNotice(
              id: i,
              title: 'topic',
              type: 1,
              mainId: 100 + i,
              relatedId: 200 + i,
              unread: true,
              createdAt: DateTime(2026),
            ),
        ];
        final updates = <Set<int>>[];
        final operation = service.loadNoticeContents(
          notices,
          onProgress: (contents, ids) => updates.add(ids),
        );
        while (service.gates.length < 2) {
          await Future<void>.delayed(Duration.zero);
        }
        if (changeAccount) service.setCurrentUsername('bob');
        service.gates[101]!.complete(
          const CommunityTopicDetail(
            title: '',
            posts: [CommunityPost(id: '201', author: 'a', body: '第一条')],
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(
          updates,
          changeAccount
              ? isEmpty
              : [
                  {1},
                ],
        );
        service.gates[102]!.complete(
          const CommunityTopicDetail(
            title: '',
            posts: [CommunityPost(id: '202', author: 'b', body: '第二条')],
          ),
        );
        final contents = await operation;
        expect(contents, changeAccount ? isEmpty : {1: '第一条', 2: '第二条'});
      },
    );
  }
}
