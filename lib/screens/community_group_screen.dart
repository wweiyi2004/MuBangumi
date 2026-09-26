import '../state/service_providers.dart';
import '../navigation/app_destination.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../widgets/social_group_widgets.dart';
import '../widgets/social_chat_style.dart';

import '../core/network/community_service.dart';
import '../models/community_models.dart';
import '../models/community_topic_submission.dart';
import '../widgets/community_composer.dart';
import '../widgets/community_widgets.dart';
import '../widgets/community_loading.dart';
import '../widgets/group_qr_sheet.dart';
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
  late final _service = widget.service ?? communityServiceFor(context);
  CommunityGroupDetail? _detail;
  bool _loading = true;
  int _requestId = 0;
  int _lastSuccessfulRequest = -1;
  String? _error;
  CommunityTopic? _publishedTopic;
  bool _membershipBusy = false;

  String get _slug => widget.group.slug.isNotEmpty
      ? widget.group.slug
      : Uri.tryParse(widget.group.url)?.pathSegments.lastOrNull ?? '';

  @override
  void initState() {
    super.initState();
    _detail = widget.initialDetail;
    _service.accountChanges.addListener(_resetAccount);
    _service.contentPreferencesChanges.addListener(_resetAccount);
    unawaited(_loadCacheThenRefresh());
  }

  void _resetAccount() {
    _requestId++;
    scheduleMicrotask(() {
      if (!mounted) return;
      setState(() {
        _detail = null;
        _publishedTopic = null;
      });
      unawaited(_load(refresh: true));
    });
  }

  @override
  void dispose() {
    _requestId++;
    _service.accountChanges.removeListener(_resetAccount);
    _service.contentPreferencesChanges.removeListener(_resetAccount);
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
    if (_membershipBusy || !mounted) return;
    final identity = _service.identityRevision;
    setState(() => _membershipBusy = true);
    try {
      await _runMembershipOnWeb();
    } catch (error) {
      if (mounted && identity == _service.identityRevision) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is FormatException ? error.message : '暂时无法打开小组页面，请检查登录后重试',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _membershipBusy = false);
    }
  }

  Future<void> _runMembershipOnWeb() async {
    // P1 暂无加入/退出小组写接口；应用内 WebView 完成网站会话操作后可返回刷新。
    if (!mounted) return;
    final identity = _service.identityRevision;
    await openSeededCommunityWeb(
      context,
      initialUrl: 'https://bgm.tv/group/${Uri.encodeComponent(_slug)}',
      title: _detail?.canManage == true ? '管理小组' : '小组成员设置',
      showSectionSwitcher: false,
      loginHint: '可在此加入、退出或管理小组。',
    );
    if (!mounted || identity != _service.identityRevision) return;
    _requestId++;
    _service.invalidateGroupMembership();
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
    final identity = _service.identityRevision;
    final submission = CommunityTopicDraft();
    CommunityTopic? receipt;
    final sent = await showCommunityComposer(
      context,
      heading: '在「${_detail?.group.name ?? widget.group.name}」发帖',
      requireTitle: true,
      isAccountCurrent: () =>
          _service.isAuthenticated &&
          _service.currentUsername == draftAccount &&
          _service.identityRevision == identity,
      draftKey: communityDraftKey(draftAccount, ['group', _slug]),
      topicDraft: submission,
      submitLabel: '发布',
      onSubmit: (title, content, token) async {
        receipt = await _service.createGroupTopic(
          slug: _slug,
          title: title,
          content: content,
          turnstileToken: token,
        );
        submission.confirmedId = receipt!.id;
      },
      confirmSubmission: (title, content, attemptedAt) async {
        final id = submission.confirmedId;
        receipt = id != null
            ? _service.createdGroupTopic(slug: _slug, title: title, id: id)
            : await _service.findSubmittedGroupTopic(
                slug: _slug,
                title: title,
                content: content,
                attemptedAt: attemptedAt,
              );
        submission.confirmedId = receipt?.id;
        return receipt != null;
      },
      inspectSubmission: _openWeb,
    );
    if (!sent ||
        !mounted ||
        identity != _service.identityRevision ||
        receipt == null) {
      return;
    }
    setState(() => _publishedTopic = receipt);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已确认发布：帖子 #${receipt!.id}'),
        action: SnackBarAction(
          label: '查看帖子',
          onPressed: () => _openTopic(receipt!),
        ),
      ),
    );
    await _load(refresh: true);
  }

  void _openTopic(CommunityTopic topic) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TopicRoute(topic: topic, service: _service),
      ),
    );
  }

  void _openAll({bool members = false}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GroupBrowseRoute(
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
            if (_publishedTopic case final published?)
              ListTile(
                leading: const Icon(Icons.check_circle_outline),
                title: Text(
                  '已确认发布：${published.title}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text('帖子 #${published.id} · 列表可能延迟显示或等待审核'),
                trailing: TextButton(
                  onPressed: () => _openTopic(published),
                  child: const Text('查看帖子'),
                ),
              ),
            if (_detail != null)
              CommunityRefreshStatus(
                loading: _loading,
                error:
                    _error ??
                    (_detail!.unavailableSections.isEmpty
                        ? null
                        : '部分小组内容加载失败，成员状态和已加载内容仍可使用'),
                message:
                    _error == null && _detail!.unavailableSections.isNotEmpty
                    ? '部分小组内容加载失败，已保留成员状态和可用内容'
                    : '刷新失败，已保留当前内容',
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
                    onOpenMembershipPage: _membershipBusy
                        ? null
                        : _openMembershipOnWeb,
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
                          title: '创建者与管理员',
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
                  if (detail.unavailableSections.contains(
                    CommunityGroupSection.topics,
                  ))
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            const Text('话题暂时未能加载，不代表小组没有帖子'),
                            TextButton(
                              onPressed: _loading
                                  ? null
                                  : () => _load(refresh: true),
                              child: const Text('重新加载话题'),
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (detail.recentTopics.isEmpty)
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
  final VoidCallback? onOpenMembershipPage;
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
          child: Text(
            detail.canManage
                ? '${detail.membershipLabel} · 管理'
                : detail.membershipLabel,
          ),
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
