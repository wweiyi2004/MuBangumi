import 'dart:async';

import 'package:flutter/material.dart';

import '../core/network/community_service.dart';
import '../models/community_models.dart';
import '../widgets/community_composer.dart';
import '../widgets/community_widgets.dart';
import 'community_page.dart';
import 'community_topic_screen.dart';
import 'user_profile_page.dart';
import 'website_login_screen.dart';

class CommunityGroupScreen extends StatefulWidget {
  const CommunityGroupScreen({super.key, required this.group});

  final CommunityGroup group;

  @override
  State<CommunityGroupScreen> createState() => _CommunityGroupScreenState();
}

class _CommunityGroupScreenState extends State<CommunityGroupScreen> {
  final _service = CommunityService.shared;
  CommunityGroupDetail? _detail;
  bool _loading = true;
  String? _error;

  String get _slug => widget.group.slug.isNotEmpty
      ? widget.group.slug
      : Uri.tryParse(widget.group.url)?.pathSegments.lastOrNull ?? '';

  @override
  void initState() {
    super.initState();
    unawaited(_loadCacheThenRefresh());
  }

  Future<void> _loadCacheThenRefresh() async {
    final cached = await _service.readCachedGroupDetail(_slug);
    if (cached != null && mounted) {
      setState(() {
        _detail = cached;
        _loading = false;
      });
    }
    await _load(refresh: true);
  }

  Future<void> _load({bool refresh = false}) async {
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

  Future<void> _openMembershipOnWeb() async {
    // P1 暂无加入/退出小组写接口；应用内 WebView 完成网站会话操作后可返回刷新。
    if (!mounted) return;
    final cookies = await loadWebsiteSeedCookies();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CommunityWebScreen(
          initialUrl: widget.group.url,
          title: _detail?.isJoined == true ? '退出小组' : '加入小组',
          showSectionSwitcher: false,
          seedCookies: cookies,
          loginHint: cookies.isEmpty
              ? '加入/退出小组使用官网会话。请先到「我的 → 同步网站登录」，或在此页登录。'
              : '已注入同步的网站会话。若仍提示登录，请重新同步网站登录。',
        ),
      ),
    );
    if (!mounted) return;
    await _load(refresh: true);
  }

  Future<void> _createTopic() async {
    final sent = await showCommunityComposer(
      context,
      heading: '在「${_detail?.group.name ?? widget.group.name}」发帖',
      requireTitle: true,
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
        builder: (_) => CommunityTopicScreen(topic: topic),
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
      appBar: AppBar(
        title: Text(detail?.group.name ?? widget.group.name),
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
      floatingActionButton:
          _service.isAuthenticated && detail?.canCreateTopic == true
          ? FloatingActionButton.extended(
              onPressed: _createTopic,
              icon: const Icon(Icons.edit_rounded),
              label: const Text('发帖'),
            )
          : null,
      body: SafeArea(child: _buildBody()),
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
              constraints: const BoxConstraints(maxWidth: 920),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _GroupHeader(
                    detail: detail,
                    onOpenMembershipPage: _openMembershipOnWeb,
                  ),
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
                  _SectionTitle(title: '最近话题', count: detail.group.topicCount),
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
                      CommunityTopicCard(
                        topic: topic,
                        onTap: () => _openTopic(topic),
                      ),
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
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Wrap(
        spacing: 16,
        runSpacing: 14,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          CommunityAvatar(
            imageUrl: detail.group.imageUrl,
            radius: 36,
            fallbackIcon: Icons.groups_rounded,
          ),
          SizedBox(
            width: 460,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  detail.group.name,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  '${detail.group.memberCount} 位成员 · '
                  '${detail.group.topicCount} 个话题 · ${detail.postCount} 条回复',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          detail.isJoined
              ? OutlinedButton.icon(
                  onPressed: onOpenMembershipPage,
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('退出小组'),
                )
              : FilledButton.icon(
                  onPressed: onOpenMembershipPage,
                  icon: const Icon(Icons.group_add_rounded),
                  label: const Text('加入小组'),
                ),
        ],
      ),
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
