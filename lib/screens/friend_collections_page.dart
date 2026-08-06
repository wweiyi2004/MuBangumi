import 'package:flutter/material.dart';

import '../models/bangumi_models.dart';
import 'user_profile_page.dart';

/// Compatibility wrapper: friend collection browsing now lives in
/// [UserProfilePage].
class FriendCollectionsPage extends StatelessWidget {
  const FriendCollectionsPage({super.key, required this.user});

  final BangumiUser user;

  @override
  Widget build(BuildContext context) => UserProfilePage(
    username: user.username,
    seed: user,
  );
}
