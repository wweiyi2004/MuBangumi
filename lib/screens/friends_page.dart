import '../state/service_providers.dart';
import '../navigation/app_destination.dart';
import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/bangumi_endpoints.dart';
import '../models/bangumi_models.dart';
import '../state/session_controller.dart';
import '../widgets/community_widgets.dart';
import '../widgets/friend_qr_actions.dart';
import '../widgets/subject_widgets.dart';

class FriendsPage extends ConsumerStatefulWidget {
  const FriendsPage({super.key, this.username});

  final String? username;

  @override
  ConsumerState<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends ConsumerState<FriendsPage> {
  late final _service = communityServiceFor(context);
  final _scrollController = ScrollController();
  final _queryController = TextEditingController();

  List<BangumiUser> _friends = const [];
  int _total = 0;
  int _nextOffset = 0;
  bool _hasMore = false;
  bool _removingFriend = false;
  bool _changed = false;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  int _requestId = 0;
  String _query = '';

  String get _username {
    final override = widget.username?.trim();
    if (override != null && override.isNotEmpty) return override;
    return ref.read(sessionProvider).user?.username ?? '';
  }

  bool get _isOwnList {
    final me = ref.read(sessionProvider).user?.username;
    if (me == null) return false;
    final override = widget.username?.trim();
    if (override == null || override.isEmpty) return true;
    return me.toLowerCase() == override.toLowerCase();
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    ref.listenManual(
      sessionProvider.select((state) => (state.user?.id, state.user?.username)),
      (_, _) => _resetAccount(),
    );
    Future.microtask(() => _load(refresh: true));
  }

  @override
  void didUpdateWidget(covariant FriendsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.username != widget.username) _resetAccount();
  }

  void _resetAccount() {
    _requestId++;
    _queryController.clear();
    setState(() {
      _changed = false;
      _friends = const [];
      _total = _nextOffset = 0;
      _hasMore = _loadingMore = false;
      _loading = true;
      _error = null;
      _query = '';
    });
    unawaited(Future.microtask(() => _load(refresh: true)));
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    _queryController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.extentAfter < 500) {
      unawaited(_loadMore());
    }
  }

  Future<void> _load({bool refresh = false}) async {
    if (!mounted) return;
    final requestId = ++_requestId;
    final username = _username;
    if (username.isEmpty) {
      setState(() {
        _loading = false;
        _friends = const [];
        _total = _nextOffset = 0;
        _hasMore = _loadingMore = false;
        _error = '无法识别当前用户';
      });
      return;
    }
    setState(() {
      _loading = true;
      _loadingMore = false;
      _error = null;
    });
    try {
      final page = await _service.loadFriends(username, refresh: refresh);
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _friends = page.data;
        _total = page.total;
        _nextOffset = page.rawCount ?? page.data.length;
        _hasMore = _nextOffset > 0 && _nextOffset < _total;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _loadMore() async {
    if (!mounted || _loading || _loadingMore || !_hasMore) {
      return;
    }
    final username = _username;
    final requestId = _requestId;
    setState(() => _loadingMore = true);
    try {
      final page = await _service.loadFriends(username, offset: _nextOffset);
      if (!mounted || requestId != _requestId) return;
      final known = _friends.map((user) => user.username.toLowerCase()).toSet();
      setState(() {
        _friends = [
          ..._friends,
          ...page.data.where((user) => known.add(user.username.toLowerCase())),
        ];
        _total = page.total;
        final consumed = page.rawCount ?? page.data.length;
        _nextOffset += consumed;
        _hasMore = consumed > 0 && _nextOffset < _total;
        _error = null;
      });
    } catch (error) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted && requestId == _requestId) {
        setState(() => _loadingMore = false);
      }
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

  void _openFriend(BangumiUser friend) {
    openUserProfileFromBangumi(context, friend);
  }

  @override
  Widget build(BuildContext context) => PopScope<bool>(
    canPop: !_changed,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) Navigator.of(context).pop(true);
    },
    child: _buildPage(context),
  );

  Widget _buildPage(BuildContext context) {
    final items = _filtered;
    final me = ref.watch(sessionProvider).user;
    return Scaffold(
      appBar: AppBar(
        title: const Text('好友'),
        actions: [
          if (_isOwnList && me != null) ...[
            IconButton(
              tooltip: '我的二维码',
              onPressed: () => showMyFriendQr(context, me),
              icon: const Icon(Icons.qr_code_2_rounded),
            ),
            IconButton(
              tooltip: '扫一扫',
              onPressed: () async {
                final added = await scanAndAddFriend(
                  context,
                  myUsername: me.username,
                );
                if (added &&
                    mounted &&
                    me.id == ref.read(sessionProvider).user?.id) {
                  setState(() => _changed = true);
                  await _load(refresh: true);
                }
              },
              icon: const Icon(Icons.qr_code_scanner_rounded),
            ),
          ],
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(refresh: true),
        child: _loading && _friends.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 160),
                  Center(child: CircularProgressIndicator()),
                ],
              )
            : _error != null && _friends.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: MediaQuery.sizeOf(context).height * 0.55,
                    child: CommunityErrorView(
                      message: _error!,
                      onRetry: () => _load(refresh: true),
                    ),
                  ),
                ],
              )
            : ListView.builder(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  MediaQuery.sizeOf(context).width < 420 ? 12 : 16,
                  12,
                  MediaQuery.sizeOf(context).width < 420 ? 12 : 16,
                  40,
                ),
                itemCount: items.length + 2,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _total > 0
                                ? '共 $_total 位好友'
                                : '共 ${items.length} 位好友',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                          const SizedBox(height: 12),
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
                    if (items.isEmpty && !_hasMore) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 60),
                        child: EmptyState(
                          icon: Icons.people_outline_rounded,
                          title: '没有匹配的好友',
                          message: '换个关键词，或下拉刷新好友列表。',
                        ),
                      );
                    }
                    return Padding(
                      padding: const EdgeInsets.all(18),
                      child: Center(
                        child: _loadingMore
                            ? const CircularProgressIndicator()
                            : Column(
                                children: [
                                  if (_error != null) Text(_error!),
                                  if (_hasMore)
                                    TextButton(
                                      onPressed: _loadMore,
                                      child: const Text('加载更多好友'),
                                    )
                                  else
                                    const Text('已经到底了'),
                                ],
                              ),
                      ),
                    );
                  }
                  final friend = items[index - 1];
                  return _FriendTile(
                    user: friend,
                    onTap: () => _openFriend(friend),
                    onRemove: _isOwnList ? () => _removeFriend(friend) : null,
                  );
                },
              ),
      ),
    );
  }

  Future<void> _removeFriend(BangumiUser friend) async {
    if (_removingFriend || !_isOwnList) return;
    _removingFriend = true;
    final identity = _service.identityRevision;
    final owner = ref.read(sessionProvider).user?.id;
    bool isCurrent() =>
        mounted &&
        identity == _service.identityRevision &&
        owner == ref.read(sessionProvider).user?.id &&
        _isOwnList;
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('解除好友'),
          content: Text('确定与 ${friend.displayName} 解除好友关系？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('解除'),
            ),
          ],
        ),
      );
      if (ok != true || !isCurrent()) return;
      try {
        await _service.removeFriend(friend.username);
        if (!mounted || !isCurrent()) return;
        setState(() {
          _changed = true;
          _friends = [
            for (final item in _friends)
              if (item.username != friend.username) item,
          ];
          if (_total > 0) _total -= 1;
          if (_nextOffset > 0) _nextOffset -= 1;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已解除与 ${friend.displayName} 的好友关系')),
        );
        await _load(refresh: true);
      } catch (error) {
        if (!mounted || !isCurrent()) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    } finally {
      _removingFriend = false;
    }
  }
}

class _FriendTile extends StatelessWidget {
  const _FriendTile({required this.user, required this.onTap, this.onRemove});

  final BangumiUser user;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        onLongPress: onRemove,
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: scheme.primaryContainer,
          backgroundImage: user.avatarUrl.isEmpty
              ? null
              : CachedNetworkImageProvider(
                  BangumiEndpoints.imageUrl(user.avatarUrl),
                ),
          child: user.avatarUrl.isEmpty
              ? Text(
                  user.displayName.characters.first.toUpperCase(),
                  style: Theme.of(context).textTheme.titleMedium,
                )
              : null,
        ),
        title: Text(
          user.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '@${user.username}',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            if (user.sign.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(user.sign, maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
          ],
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}
