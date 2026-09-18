import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/network/community_service.dart';
import '../models/bangumi_models.dart';
import '../models/community_models.dart';
import '../state/session_controller.dart';
import '../state/background_controller.dart';
import '../widgets/profile_home_layout.dart';
import 'community_blog_screen.dart';
import 'community_timeline_page.dart';
import 'friends_page.dart';
import 'library_page.dart';
import 'settings_page.dart';

final _friendCountProvider = FutureProvider.autoDispose.family<int, String>(
  (ref, username) async =>
      (await CommunityService.shared.loadFriends(username, limit: 1)).total,
);

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});
  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  int _tab = 0;
  final _opened = <int>{0};
  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final user = session.user;
    if (user == null) return const Center(child: Text('尚未登录'));
    final friends = ref.watch(_friendCountProvider(user.username)).valueOrNull;
    final background = ref.watch(effectiveBackgroundProvider);
    return ProfileHomeLayout(
      coverImage: background.isActive
          ? FileImage(File(background.imagePath!))
          : null,
      nickname: user.displayName,
      username: user.username,
      sign: user.sign,
      avatarUrl: user.avatarUrl,
      total: session.collections.length,
      doing: session.collections
          .where((entry) => entry.type == CollectionType.doing)
          .length,
      friends: friends,
      selectedTab: _tab,
      onSelectTab: (index) => setState(() {
        _tab = index;
        _opened.add(index);
      }),
      onSettings: () => Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const SettingsPage())),
      onCollections: () => openCollectionLibrary(context, collectionType: null),
      onDoing: () =>
          openCollectionLibrary(context, collectionType: CollectionType.doing),
      onFriends: () => Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const FriendsPage())),
      content: ProfileFeedStack(
        key: ValueKey(user.id),
        index: _tab,
        children: [
          CommunityTimelinePage(
            usePrimaryScrollController: _tab == 0,
            initialMode: CommunityTimelineMode.me,
            showModeSelector: false,
          ),
          _opened.contains(1)
              ? CommunityTimelinePage(
                  usePrimaryScrollController: _tab == 1,
                  initialMode: CommunityTimelineMode.friends,
                  showModeSelector: false,
                )
              : const SizedBox.shrink(),
          _opened.contains(2)
              ? CommunityBlogListScreen(
                  embedded: true,
                  usePrimaryScrollController: _tab == 2,
                )
              : const SizedBox.shrink(),
        ],
      ),
    );
  }
}
