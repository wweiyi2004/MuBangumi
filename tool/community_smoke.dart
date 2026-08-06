// ignore_for_file: avoid_print

import 'package:mubangumi/core/network/community_service.dart';
import 'package:mubangumi/models/community_models.dart';

Future<void> main() async {
  final service = CommunityService.shared;
  final topics = await service.loadTopicPage(
    RakuenMode.subjectTrending,
    refresh: true,
  );
  final groupTopics = await service.loadTopicPage(
    RakuenMode.groupAll,
    refresh: true,
  );
  final groups = await service.loadGroupPage(refresh: true);
  if (topics.data.isEmpty) throw StateError('热门条目讨论没有解析出话题');
  if (groupTopics.data.isEmpty) throw StateError('小组话题没有解析出话题');
  if (groups.data.isEmpty) throw StateError('所有小组没有解析出小组');
  final topicDetail = await service.loadTopic(topics.data.first, refresh: true);
  final groupDetail = await service.loadGroupDetail(
    groups.data.first.slug,
    refresh: true,
  );
  final timeline = await service.loadTimeline(
    CommunityTimelineMode.all,
    refresh: true,
  );
  if (timeline.isEmpty) throw StateError('全站时间线没有解析出动态');
  final progressItems = timeline
      .where((item) => item.progress != null)
      .toList();
  if (progressItems.isEmpty) throw StateError('全站时间线没有解析出章节进度');
  // A public status with replies, retained as a live P1 reply-schema fixture.
  const replyFixtureId = 70972536;
  final replies = await service.loadTimelineReplies(
    replyFixtureId,
    refresh: true,
  );
  if (replies.isEmpty) throw StateError('时光机回复没有解析出正文');
  print(
    'topics=${topics.data.length}/${topics.total}, '
    'groupTopics=${groupTopics.data.length}/${groupTopics.total}, '
    'groups=${groups.data.length}/${groups.total}, '
    'firstTopicPosts=${topicDetail.posts.length}, '
    'groupMembers=${groupDetail.members.length}, timeline=${timeline.length}, '
    'progress=${progressItems.first.progress?.episode?.id ?? progressItems.first.progress?.episodeProgress}, '
    'replyItem=$replyFixtureId, timelineReplies=${replies.length}',
  );
}
