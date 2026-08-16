import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/bangumi_endpoints.dart';
import '../core/network/community_service.dart';
import '../core/social/common_friends.dart';
import '../models/bangumi_models.dart';
import '../state/session_controller.dart';
import 'user_profile_page.dart';

class CommonFriendsPage extends ConsumerStatefulWidget {
  const CommonFriendsPage({
    super.key,
    required this.targetUsername,
    required this.targetDisplayName,
  });

  final String targetUsername;
  final String targetDisplayName;

  @override
  ConsumerState<CommonFriendsPage> createState() => _CommonFriendsPageState();
}

class _CommonFriendsPageState extends ConsumerState<CommonFriendsPage> {
  final _queryController = TextEditingController();
  List<BangumiUser> _friends = const [];
  bool _loading = true;
  String? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _load({bool refresh = false}) async {
    final me = ref.read(sessionProvider).user?.username.trim() ?? '';
    final target = widget.targetUsername.trim();
    if (me.isEmpty || target.isEmpty) {
      setState(() {
        _loading = false;
        _error = '请先登录后查看共同好友';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final pages = await Future.wait([
        CommunityService.shared.loadAllFriends(me, refresh: refresh),
        CommunityService.shared.loadAllFriends(target, refresh: refresh),
      ]);
      if (!mounted) return;
      setState(() {
        _friends = findCommonFriends(pages[0], pages[1]);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  List<BangumiUser> get _filtered {
    final keyword = _query.trim().toLowerCase();
    if (keyword.isEmpty) return _friends;
    return _friends
        .where(
          (user) =>
              user.nickname.toLowerCase().contains(keyword) ||
              user.username.toLowerCase().contains(keyword) ||
              user.sign.toLowerCase().contains(keyword),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final items = _filtered;
    return Scaffold(
      appBar: AppBar(title: const Text('共同好友')),
      body: RefreshIndicator(
        onRefresh: () => _load(refresh: true),
        child: _loading && _friends.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 180),
                  Center(child: CircularProgressIndicator()),
                ],
              )
            : _error != null && _friends.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: MediaQuery.sizeOf(context).height * 0.55,
                    child: _ErrorState(
                      message: _error!,
                      onRetry: () => _load(refresh: true),
                    ),
                  ),
                ],
              )
            : ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                itemCount: items.length + 2,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Card(
                            child: ListTile(
                              leading: const Icon(Icons.people_alt_rounded),
                              title: Text(
                                '你和 ${widget.targetDisplayName} 的共同好友',
                              ),
                              subtitle: Text('共 ${_friends.length} 位'),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _queryController,
                            onChanged: (value) =>
                                setState(() => _query = value),
                            decoration: const InputDecoration(
                              hintText: '搜索昵称、用户名或签名',
                              prefixIcon: Icon(Icons.search_rounded),
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  if (index == items.length + 1) {
                    if (items.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 56),
                        child: _EmptyState(
                          title: _friends.isEmpty ? '暂时没有共同好友' : '没有匹配的共同好友',
                          message: _friends.isEmpty
                              ? '当你们都添加同一位用户后，他会出现在这里。'
                              : '换个关键词试试。',
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  }
                  final friend = items[index - 1];
                  return _CommonFriendTile(
                    user: friend,
                    onTap: () => openUserProfileFromBangumi(context, friend),
                  );
                },
              ),
      ),
    );
  }
}

class _CommonFriendTile extends StatelessWidget {
  const _CommonFriendTile({required this.user, required this.onTap});

  final BangumiUser user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      leading: CircleAvatar(
        radius: 24,
        backgroundImage: user.avatarUrl.isEmpty
            ? null
            : CachedNetworkImageProvider(
                BangumiEndpoints.imageUrl(user.avatarUrl),
              ),
        child: user.avatarUrl.isEmpty
            ? Text(user.displayName.characters.first.toUpperCase())
            : null,
      ),
      title: Text(
        user.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '@${user.username}${user.sign.isEmpty ? '' : '\n${user.sign}'}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        Icons.people_outline_rounded,
        size: 42,
        color: Theme.of(context).colorScheme.outline,
      ),
      const SizedBox(height: 10),
      Text(title, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 6),
      Text(message, textAlign: TextAlign.center),
    ],
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Text(message, textAlign: TextAlign.center),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('重试'),
      ),
    ],
  );
}
