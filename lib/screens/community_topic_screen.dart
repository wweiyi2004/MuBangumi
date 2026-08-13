import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/community_service.dart';
import '../models/community_models.dart';
import '../state/user_preferences_controller.dart';
import '../widgets/community_composer.dart';
import '../widgets/community_widgets.dart';
import 'user_profile_page.dart';
import 'website_login_screen.dart';

class CommunityTopicScreen extends ConsumerStatefulWidget {
  const CommunityTopicScreen({super.key, required this.topic});

  final CommunityTopic topic;

  @override
  ConsumerState<CommunityTopicScreen> createState() =>
      _CommunityTopicScreenState();
}

class _CommunityTopicScreenState extends ConsumerState<CommunityTopicScreen> {
  final _service = CommunityService.shared;
  CommunityTopicDetail? _detail;
  bool _loading = true;
  String? _error;
  Set<String> _friendUsernames = const {};
  final Set<String> _reactionBusyPostIds = {};

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    unawaited(_loadFriendUsernames());
  }

  Future<void> _loadFriendUsernames() async {
    final username = _service.currentUsername;
    if (username == null || username.isEmpty) return;
    // Defer until after first paint so opening a topic stays snappy.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    try {
      final page = await _service.loadFriends(username, limit: 40);
      if (!mounted) return;
      setState(() {
        _friendUsernames = {
          for (final friend in page.data) friend.username.toLowerCase(),
        };
      });
    } catch (_) {
      // Friend badges are optional enhancement.
    }
  }

  Future<void> _load({bool refresh = false}) async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final detail = await _service.loadTopic(widget.topic, refresh: refresh);
      if (!mounted) return;
      setState(() {
        _detail = detail;
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

  Future<void> _reply({CommunityPost? post}) async {
    if (!_service.isAuthenticated) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先登录后再回复')));
      return;
    }
    final topicId = _service.resolveTopicId(widget.topic);
    if (topicId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法识别话题编号，请返回列表重新打开该话题')));
      return;
    }
    // Top-level reply uses 0. Nested replies use the target post id.
    // Original post reply is still nested under the OP in Bangumi's model.
    final replyTo = post == null
        ? null
        : CommunityService.parseReplyId(post.id);
    final sent = await showCommunityComposer(
      context,
      heading: post == null ? '回复话题' : '回复 ${post.author}',
      warning: _oldTopicWarning,
      onSubmit: (_, content, token) => _service.replyToTopic(
        topic: widget.topic,
        content: content,
        turnstileToken: token,
        replyTo: replyTo,
      ),
    );
    if (!sent || !mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('回复已发送')));
    await _load(refresh: true);
  }

  Future<void> _updateReaction(CommunityPost post, int? value) async {
    if (!_service.isAuthenticated || _reactionBusyPostIds.contains(post.id)) {
      return;
    }
    setState(() => _reactionBusyPostIds.add(post.id));
    try {
      await _service.updatePostReaction(
        topic: widget.topic,
        post: post,
        value: value,
      );
      await _load(refresh: true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _reactionBusyPostIds.remove(post.id));
      }
    }
  }

  String? get _oldTopicWarning {
    final lastUpdated = widget.topic.updatedAt;
    if (lastUpdated == null) return null;
    final inactiveDays = DateTime.now().difference(lastUpdated).inDays;
    if (inactiveDays < 180) return null;
    return '这个话题已经 $inactiveDays 天没有更新，请确认回复仍与当前讨论有关。';
  }

  Future<void> _openWeb() async {
    await openSeededCommunityWeb(
      context,
      initialUrl: widget.topic.webUrl,
      title: widget.topic.title,
      showSectionSwitcher: false,
    );
  }

  String? _usernameFromUserUrl(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || uri.pathSegments.isEmpty) return null;
    final index = uri.pathSegments.indexOf('user');
    if (index < 0 || index + 1 >= uri.pathSegments.length) return null;
    final username = uri.pathSegments[index + 1].trim();
    return username.isEmpty ? null : username;
  }

  bool _isFriendPost(CommunityPost post) {
    final username = _usernameFromUserUrl(post.userUrl)?.toLowerCase();
    if (username == null) return false;
    return _friendUsernames.contains(username);
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.topic.kind.label),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : () => _load(refresh: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: '在官网查看',
            onPressed: _openWeb,
            icon: const Icon(Icons.language_rounded),
          ),
        ],
      ),
      floatingActionButton: _service.isAuthenticated && detail != null
          ? FloatingActionButton.extended(
              onPressed: _reply,
              icon: const Icon(Icons.reply_rounded),
              label: const Text('回复'),
            )
          : null,
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    final detail = _detail;
    final preferences = ref.watch(userPreferencesProvider);
    if (_loading && detail == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && detail == null) {
      return CommunityErrorView(message: _error!, onRetry: _load);
    }
    if (detail == null) return const SizedBox.shrink();
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return RefreshIndicator(
      onRefresh: () => _load(refresh: true),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(wide ? 80 : 14, 16, wide ? 80 : 14, 96),
        itemCount: detail.posts.length + 2,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 920),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      detail.title,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    if (detail.sourceTitle.isNotEmpty) ...[
                      const SizedBox(height: 7),
                      Text(
                        detail.sourceTitle,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    if (detail.posts.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(28),
                        child: Center(child: Text('还没有可显示的回复')),
                      ),
                  ],
                ),
              ),
            );
          }
          if (index == detail.posts.length + 1) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 920),
                child: Column(
                  children: [
                    if (_loading) const LinearProgressIndicator(),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }
          final post = detail.posts[index - 1];
          final username = _usernameFromUserUrl(post.userUrl);
          final supportsReactions =
              widget.topic.kind == CommunityTopicKind.group ||
              widget.topic.kind == CommunityTopicKind.subject;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 920),
              child: BlockedCommunityContent(
                key: ValueKey('topic-post-${post.id}'),
                username: username ?? post.author,
                blocked: preferences.isBlocked(username ?? ''),
                child: CommunityPostCard(
                  post: post,
                  isFriend: _isFriendPost(post),
                  currentUsername: _service.currentUsername,
                  reactionBusy: _reactionBusyPostIds.contains(post.id),
                  onReactionChanged:
                      _service.isAuthenticated && supportsReactions
                      ? (value) => _updateReaction(post, value)
                      : null,
                  onReply: _service.isAuthenticated
                      ? () => _reply(post: post)
                      : null,
                  onOpenUser: username == null
                      ? null
                      : () => openUserProfile(
                          context,
                          username: username,
                          nickname: post.author,
                          avatarUrl: post.avatarUrl,
                        ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
