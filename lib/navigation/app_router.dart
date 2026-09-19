import 'package:flutter/material.dart';
import 'app_destination.dart';
import '../screens/subject_detail_screen.dart';
import '../screens/character_detail_screen.dart';
import '../screens/person_detail_screen.dart';
import '../screens/user_profile_page.dart';
import '../screens/community_group_screen.dart';
import '../screens/community_topic_screen.dart';
import '../screens/community_group_browse_screen.dart';
import '../screens/community_blog_screen.dart';
import '../screens/common_friends_page.dart';
import '../screens/discover_page.dart';
import '../screens/score_trends_page.dart';

abstract final class AppRouter {
  static Widget resolve(AppDestination route) => switch (route) {
    SubjectRoute() => SubjectDetailScreen(subject: route.subject),
    CharacterRoute() => CharacterDetailScreen(
      characterId: route.characterId,
      seedName: route.seedName,
      seedImageUrl: route.seedImageUrl,
    ),
    PersonRoute() => PersonDetailScreen(
      personId: route.personId,
      seedName: route.seedName,
      seedImageUrl: route.seedImageUrl,
    ),
    UserRoute() => UserProfilePage(username: route.username, seed: route.seed),
    GroupRoute() => CommunityGroupScreen(
      group: route.group,
      service: route.service,
      initialDetail: route.initialDetail,
    ),
    TopicRoute() => CommunityTopicScreen(
      topic: route.topic,
      service: route.service,
    ),
    GroupBrowseRoute() => CommunityGroupBrowseScreen(
      group: route.group,
      service: route.service,
      members: route.members,
    ),
    BlogRoute() => CommunityBlogScreen(
      blogId: route.blogId,
      service: route.service,
    ),
    BlogListRoute() => CommunityBlogListScreen(
      username: route.username,
      service: route.service,
      tokenProvider: route.tokenProvider,
      embedded: route.embedded,
      usePrimaryScrollController: route.usePrimaryScrollController,
    ),
    CommonFriendsRoute() => CommonFriendsPage(
      targetUsername: route.targetUsername,
      targetDisplayName: route.targetDisplayName,
    ),
    DiscoverRoute() => DiscoverPage(
      initialTag: route.initialTag,
      initialSubjectType: route.initialSubjectType,
      showTitle: route.showTitle,
    ),
    ScoreTrendsRoute() => const ScoreTrendsPage(),
  };
}
