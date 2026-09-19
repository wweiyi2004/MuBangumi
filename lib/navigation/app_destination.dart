import 'package:flutter/material.dart';
import '../core/network/community_service.dart';
import '../models/bangumi_models.dart';
import '../models/community_models.dart';
import '../widgets/community_composer.dart' show CommunityTokenProvider;

/// Cross-feature navigation describes a destination; only the composition root
/// knows which concrete screen renders it. Tests can supply a small resolver.
class AppRouteScope extends InheritedWidget {
  const AppRouteScope({super.key, required this.resolve, required super.child});
  final Widget Function(AppDestination) resolve;
  static AppRouteScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppRouteScope>();
    if (scope == null) {
      throw StateError(
        'AppRouteScope is required for cross-feature navigation',
      );
    }
    return scope;
  }

  @override
  bool updateShouldNotify(AppRouteScope oldWidget) =>
      resolve != oldWidget.resolve;
}

sealed class AppDestination extends StatelessWidget {
  const AppDestination({super.key});
  @override
  Widget build(BuildContext context) => AppRouteScope.of(context).resolve(this);
}

class SubjectRoute extends AppDestination {
  const SubjectRoute({super.key, required this.subject});
  final Subject subject;
}

class CharacterRoute extends AppDestination {
  const CharacterRoute({
    super.key,
    required this.characterId,
    this.seedName = '',
    this.seedImageUrl = '',
  });
  final int characterId;
  final String seedName, seedImageUrl;
}

class PersonRoute extends AppDestination {
  const PersonRoute({
    super.key,
    required this.personId,
    this.seedName = '',
    this.seedImageUrl = '',
  });
  final int personId;
  final String seedName, seedImageUrl;
}

class UserRoute extends AppDestination {
  const UserRoute({super.key, required this.username, this.seed});
  final String username;
  final BangumiUser? seed;
}

class GroupRoute extends AppDestination {
  const GroupRoute({
    super.key,
    required this.group,
    this.service,
    this.initialDetail,
  });
  final CommunityGroup group;
  final CommunityService? service;
  final CommunityGroupDetail? initialDetail;
}

class TopicRoute extends AppDestination {
  const TopicRoute({super.key, required this.topic, this.service});
  final CommunityTopic topic;
  final CommunityService? service;
}

class GroupBrowseRoute extends AppDestination {
  const GroupBrowseRoute({
    super.key,
    required this.group,
    required this.service,
    this.members = false,
  });
  final CommunityGroup group;
  final CommunityService service;
  final bool members;
}

class BlogRoute extends AppDestination {
  const BlogRoute({super.key, required this.blogId, this.service});
  final int blogId;
  final CommunityService? service;
}

class BlogListRoute extends AppDestination {
  const BlogListRoute({
    super.key,
    this.username,
    this.service,
    this.tokenProvider,
    this.embedded = false,
    this.usePrimaryScrollController = false,
  });
  final String? username;
  final CommunityService? service;
  final CommunityTokenProvider? tokenProvider;
  final bool embedded, usePrimaryScrollController;
}

class CommonFriendsRoute extends AppDestination {
  const CommonFriendsRoute({
    super.key,
    required this.targetUsername,
    required this.targetDisplayName,
  });
  final String targetUsername, targetDisplayName;
}

class DiscoverRoute extends AppDestination {
  const DiscoverRoute({
    super.key,
    this.initialTag = '',
    this.initialSubjectType,
    this.showTitle = true,
  });
  final String initialTag;
  final SubjectType? initialSubjectType;
  final bool showTitle;
}

class ScoreTrendsRoute extends AppDestination {
  const ScoreTrendsRoute({super.key});
}

void openUserProfile(
  BuildContext context, {
  required String username,
  String? nickname,
  String? avatarUrl,
  String? sign,
  int id = 0,
}) {
  final value = username.trim();
  if (value.isEmpty || value == 'unknown') return;
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => UserRoute(
        username: value,
        seed: BangumiUser(
          id: id,
          username: value,
          nickname: nickname?.trim().isNotEmpty == true
              ? nickname!.trim()
              : value,
          avatarUrl: avatarUrl?.trim() ?? '',
          sign: sign?.trim() ?? '',
        ),
      ),
    ),
  );
}

void openUserProfileFromCommunity(BuildContext context, CommunityUser user) =>
    openUserProfile(
      context,
      username: user.username,
      nickname: user.nickname,
      avatarUrl: user.avatarUrl,
      id: user.id,
    );
void openUserProfileFromBangumi(BuildContext context, BangumiUser user) =>
    openUserProfile(
      context,
      username: user.username,
      nickname: user.nickname,
      avatarUrl: user.avatarUrl,
      sign: user.sign,
      id: user.id,
    );
void openDiscoverTagSearch(
  BuildContext context, {
  required String tag,
  SubjectType subjectType = SubjectType.anime,
}) {
  final value = tag.trim();
  if (value.isEmpty) return;
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text('标签 · $value')),
        body: DiscoverRoute(initialTag: value, initialSubjectType: subjectType),
      ),
    ),
  );
}
