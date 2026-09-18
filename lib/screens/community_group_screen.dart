import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../widgets/social_group_widgets.dart';
import '../widgets/social_chat_style.dart';

import '../core/network/community_service.dart';
import '../models/community_models.dart';
import '../widgets/community_composer.dart';
import '../widgets/community_widgets.dart';
import '../widgets/community_loading.dart';
import '../widgets/group_qr_sheet.dart';
import 'community_page.dart';
import 'community_topic_screen.dart';
import 'community_group_browse_screen.dart';
import 'user_profile_page.dart';
import 'website_login_screen.dart';

class CommunityGroupScreen extends StatefulWidget {
  const CommunityGroupScreen({
    super.key,
    required this.group,
    this.service,
    this.initialDetail,
  });
  final CommunityService? service;

  final CommunityGroup group;
  final CommunityGroupDetail? initialDetail;

  @override
  State<CommunityGroupScreen> createState() => _CommunityGroupScreenState();
}

class _CommunityGroupScreenState extends State<CommunityGroupScreen> {
  late final _service = widget.service ?? CommunityService.shared;
  CommunityGroupDetail? _detail;
  bool _loading = true;
  int _requestId = 0;
  int _lastSuccessfulRequest = -1;
  String? _error;

  String get _slug => widget.group.slug.isNotEmpty
      ? widget.group.slug
      : Uri.tryParse(widget.group.url)?.pathSegments.lastOrNull ?? '';

  @override
  void initState() {
    super.initState();
    _detail = widget.initialDetail;
    _service.accountChanges.addListener(_resetAccount);
    unawaited(_loadCacheThenRefresh());
  }

  void _resetAccount() {
    _requestId++;
    scheduleMicrotask(() {
      if (!mounted) return;
      setState(() => _detail = null);
      unawaited(_load(refresh: true));
    });
  }

  @override
  void dispose() {
    _requestId++;
    _service.accountChanges.removeListener(_resetAccount);
    super.dispose();
  }

  Future<void> _loadCacheThenRefresh() async {
    final requestId = ++_requestId;
    final network = _load(requestId: requestId);
    Future<void> restore() async {
      if (widget.initialDetail != null) return;
      try {
        final cached = await _service.readCachedGroupDetail(_slug);
        if (!mounted ||
            requestId != _requestId ||
            _lastSuccessfulRequest == requestId ||
            cached == null) {
          return;
        }
        setState(() => _detail = cached);
      } catch (_) {}
    }

    unawaited(restore());
    await network;
  }

  Future<void> _load({bool refresh = false, int? requestId}) async {
    if (!mounted) return;
    final activeRequest = requestId ?? ++_requestId;
    if (_slug.isEmpty) {
      setState(() {
        _loading = false;
        _error = '无法识别小组地址';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await _service.loadGroupDetail(_slug, refresh: refresh);
      if (!mounted || activeRequest != _requestId) return;
      setState(() {
        _detail = detail;
        _lastSuccessfulRequest = activeRequest;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || activeRequest != _requestId) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _openMembershipOnWeb() async {
    // P1 暂无加入/退出小组写接口；应用内 WebView 完成网站会话操作后可返回刷新。
    if (!mounted) return;
    final identity = _service.identityRevision;
    if (!await ensureWebsiteAccess(context) || !mounted) return;
    final cookies = await loadWebsiteSeedCookies();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CommunityWebScreen(
          initialUrl: widget.group.url,
          title: _detail?.isJoined == true ? '退出小组' : '加入小组',
          showSectionSwitcher: false,
          seedCookies: cookies,
          loginHint: cookies.isEmpty ? '请在此登录后加入或退出小组。' : '若页面提示登录，请重新登录后继续。',
        ),
      ),
    );
    if (!mounted || identity != _service.identityRevision) return;
    try {
      final preview = await _service.loadGroupPreview(_slug);
      if (!mounted || identity != _service.identityRevision) return;
      setState(() => _detail = preview);
    } catch (_) {
      /* The full reload below retains the existing error UI. */
    }
    if (mounted && identity == _service.identityRevision) {
      await _load(refresh: true);
    }
  }

  Future<void> _createTopic() async {
    final draftAccount = _service.currentUsername;
    final sent = await showCommunityComposer(
      context,
      heading: '在「${_detail?.group.name ?? widget.group.name}」发帖',
      requireTitle: true,
      isAccountCurrent: () =>
          _service.isAuthenticated && _service.currentUsername == draftAccount,
      draftKey: communityDraftKey(draftAccount, ['group', _slug]),
      onSubmit: (title, content, token) => _service.createGroupTopic(
        slug: _slug,
        title: title,
        content: content,
        turnstileToken: token,
      ),
    );
    if (!sent || !mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('话题已发布')));
    await _load(refresh: true);
  }

  void _openTopic(CommunityTopic topic) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CommunityTopicScreen(topic: topic, service: _service),
      ),
    );
  }

  void _openAll({bool members = false}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CommunityGroupBrowseScreen(
          group: _detail?.group ?? widget.group,
          service: _service,
          members: members,
        ),
      ),
    );
  }

  Future<void> _openWeb() async {
    await openSeededCommunityWeb(
      context,
      initialUrl: widget.group.url,
      title: widget.group.name,
      showSectionSwitcher: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    return Scaffold(
      backgroundColor: SocialChatStyle.paper(context),
      appBar: AppBar(
        backgroundColor: SocialChatStyle.paper(context),
        surfaceTintColor: Colors.transparent,
        title: Row(
          children: [
            CommunityAvatar(
              imageUrl: detail?.group.imageUrl ?? widget.group.imageUrl,
              radius: 17,
              fallbackIcon: CupertinoIcons.person_3,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                detail?.group.name ?? widget.group.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '小组二维码',
            onPressed: () =>
                showGroupQr(context, detail?.group ?? widget.group),
            icon: const Icon(Icons.qr_code_rounded),
          ),
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
      floatingActionButton:
          _service.isAuthenticated && detail?.canCreateTopic == true
          ? FloatingActionButton.extended(
              onPressed: _createTopic,
              backgroundColor: SocialChatStyle.accent(context),
              foregroundColor: SocialChatStyle.dark(context)
                  ? Colors.black
                  : Colors.white,
              icon: const Icon(CupertinoIcons.chat_bubble_2),
              label: const Text('发起讨论'),
            )
          : null,
      body: SafeArea(
        child: Column(
          children: [
            if (_detail != null)
              CommunityRefreshStatus(
                loading: _loading,
                error: _error,
                onRetry: () => _load(refresh: true),
              ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    final detail = _detail;
    if (_loading && detail == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && detail == null) {
      return CommunityErrorView(message: _error!, onRetry: _load);
    }
    if (detail == null) return const SizedBox.shrink();
    return RefreshIndicator(
      onRefresh: () => _load(refresh: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _GroupHeader(
                    detail: detail,
                    onOpenMembershipPage: _openMembershipOnWeb,
                  ),
                  ExpansionTile(
                    title: const Text('小组资料'),
                    tilePadding: EdgeInsets.zero,
                    children: [
                      if (detail.description.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: SelectableText(detail.description),
                          ),
                        ),
                      ],
                      if (detail.moderators.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        _SectionTitle(
                          title: '管理员',
                          count: detail.moderators.length,
                        ),
                        const SizedBox(height: 9),
                        _MemberStrip(users: detail.moderators),
                      ],
                      if (detail.members.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        _SectionTitle(
                          title: '新成员',
                          count: detail.group.memberCount,
                        ),
                        const SizedBox(height: 9),
                        _MemberStrip(users: detail.members),
                      ],
                      const SizedBox(height: 20),
                    ],
                  ),
                  Wrap(
                    spacing: 12,
                    children: [
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: SocialChatStyle.accent(context),
                        ),
                        onPressed: () => _openAll(),
                        icon: const Icon(Icons.forum_outlined),
                        label: const Text('全部话题'),
                      ),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: SocialChatStyle.accent(context),
                        ),
                        onPressed: () => _openAll(members: true),
                        icon: const Icon(Icons.people_outline),
                        label: const Text('全部成员'),
                      ),
                    ],
                  ),
                  _SectionTitle(title: '小组讨论', count: detail.group.topicCount),
                  const SizedBox(height: 9),
                  if (detail.recentTopics.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: Text('还没有话题')),
                      ),
                    )
                  else
                    for (final topic in detail.recentTopics)
                      GroupDiscussionTile(
                        topic: topic,
                        onTap: () => _openTopic(topic),
                      ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.detail,
    required this.onOpenMembershipPage,
  });
  final CommunityGroupDetail detail;
  final VoidCallback onOpenMembershipPage;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            '${detail.group.memberCount} 位成员 · ${detail.group.topicCount} 个讨论',
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        TextButton(
          onPressed: onOpenMembershipPage,
          style: TextButton.styleFrom(
            foregroundColor: SocialChatStyle.accent(context),
          ),
          child: Text(detail.isJoined ? '已加入' : '加入'),
        ),
      ],
    ),
  );
}

class _MemberStrip extends StatelessWidget {
  const _MemberStrip({required this.users});

  final List<CommunityUser> users;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 88,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: users.length,
      separatorBuilder: (_, _) => const SizedBox(width: 10),
      itemBuilder: (context, index) {
        final user = users[index];
        return SizedBox(
          width: 72,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => openUserProfileFromCommunity(context, user),
            child: Column(
              children: [
                CommunityAvatar(imageUrl: user.avatarUrl, radius: 25),
                const SizedBox(height: 5),
                Text(
                  user.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
      ),
      if (count > 0) ...[
        const SizedBox(width: 7),
        Text('$count', style: Theme.of(context).textTheme.labelMedium),
      ],
    ],
  );
}
