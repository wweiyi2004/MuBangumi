import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/network/bangumi_endpoints.dart';
import '../models/bangumi_models.dart';
import '../models/community_models.dart';
import '../state/session_controller.dart';
import '../widgets/subject_widgets.dart';
import 'subject_detail_screen.dart';

/// Opens a Bangumi user profile with collection / progress overview.
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
      builder: (_) => UserProfilePage(
        username: value,
        seed: BangumiUser(
          id: id,
          username: value,
          nickname: (nickname == null || nickname.trim().isEmpty)
              ? value
              : nickname.trim(),
          avatarUrl: avatarUrl?.trim() ?? '',
          sign: sign?.trim() ?? '',
        ),
      ),
    ),
  );
}

void openUserProfileFromCommunity(
  BuildContext context,
  CommunityUser user,
) => openUserProfile(
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

class UserProfilePage extends ConsumerStatefulWidget {
  const UserProfilePage({super.key, required this.username, this.seed});

  final String username;
  final BangumiUser? seed;

  @override
  ConsumerState<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends ConsumerState<UserProfilePage> {
  BangumiUser? _user;
  SubjectType _subjectType = SubjectType.anime;
  CollectionType? _statusFilter = CollectionType.doing;
  Map<CollectionType, int> _counts = const {};
  List<UserCollection> _items = const [];
  bool _loadingProfile = true;
  bool _loadingCollections = true;
  String? _error;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _user = widget.seed;
    Future.microtask(_loadAll);
  }

  Future<void> _loadAll() async {
    await Future.wait([_loadProfile(), _loadCollections()]);
  }

  Future<void> _loadProfile() async {
    try {
      final user = await ref
          .read(bangumiApiProvider)
          .getUser(widget.username);
      if (!mounted) return;
      setState(() {
        _user = user;
        _loadingProfile = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingProfile = false);
      // Keep seed profile if network profile fetch fails.
    }
  }

  Future<void> _loadCollections() async {
    final requestId = ++_requestId;
    final subjectType = _subjectType;
    final status = _statusFilter;
    setState(() {
      _loadingCollections = true;
      _error = null;
    });
    try {
      final api = ref.read(bangumiApiProvider);
      final countsFuture = api.getUserCollectionCounts(
        widget.username,
        subjectType: subjectType,
      );
      final itemsFuture = api.getUserCollections(
        widget.username,
        subjectType: subjectType,
        collectionType: status,
        // Doing lists stay moderate; full browse caps for responsiveness.
        maxItems: status == null ? 80 : 60,
      );
      final counts = await countsFuture;
      final items = await itemsFuture;
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _counts = counts;
        _items = items;
        _loadingCollections = false;
      });
    } catch (error) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _loadingCollections = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  int get _totalCount =>
      _counts.values.fold<int>(0, (sum, value) => sum + value);

  @override
  Widget build(BuildContext context) {
    final user = _user;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(user?.displayName ?? widget.username),
        actions: [
          IconButton(
            tooltip: '加为好友（官网）',
            onPressed: () => launchUrl(
              Uri.parse(
                'https://bgm.tv/user/${Uri.encodeComponent(widget.username)}',
              ),
              mode: LaunchMode.externalApplication,
            ),
            icon: const Icon(Icons.person_add_alt_1_outlined),
          ),
          IconButton(
            tooltip: '发短信（官网）',
            onPressed: () => launchUrl(
              Uri.parse(
                'https://bgm.tv/pm/compose/${Uri.encodeComponent(widget.username)}.chii',
              ),
              mode: LaunchMode.externalApplication,
            ),
            icon: const Icon(Icons.mail_outline_rounded),
          ),
          IconButton(
            tooltip: '在 Bangumi 打开',
            onPressed: () => launchUrl(
              Uri.parse(
                'https://bgm.tv/user/${Uri.encodeComponent(widget.username)}',
              ),
              mode: LaunchMode.externalApplication,
            ),
            icon: const Icon(Icons.open_in_new_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadAll,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              radius: 34,
                              backgroundColor: scheme.primaryContainer,
                              backgroundImage:
                                  user == null || user.avatarUrl.isEmpty
                                  ? null
                                  : CachedNetworkImageProvider(
                                      BangumiEndpoints.imageUrl(user.avatarUrl),
                                    ),
                              child: user == null || user.avatarUrl.isEmpty
                                  ? Text(
                                      (user?.displayName ?? widget.username)
                                          .characters
                                          .first
                                          .toUpperCase(),
                                      style: Theme.of(
                                        context,
                                      ).textTheme.headlineSmall,
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    user?.displayName ?? widget.username,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.headlineSmall,
                                  ),
                                  Text(
                                    '@${user?.username ?? widget.username}',
                                    style: TextStyle(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                  if ((user?.sign ?? '').isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(user!.sign),
                                  ],
                                  if (_loadingProfile) ...[
                                    const SizedBox(height: 10),
                                    const LinearProgressIndicator(minHeight: 2),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '${_subjectType.label}收藏概况',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final type in SubjectType.values) ...[
                            ChoiceChip(
                              avatar: Icon(subjectTypeIcon(type), size: 16),
                              label: Text(type.label),
                              selected: _subjectType == type,
                              onSelected: (_) {
                                if (_subjectType == type) return;
                                setState(() {
                                  _subjectType = type;
                                  _statusFilter = CollectionType.doing;
                                });
                                _loadCollections();
                              },
                            ),
                            const SizedBox(width: 8),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final width = (constraints.maxWidth - 20) / 3;
                        return Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _StatCard(
                              width: width,
                              value: _counts[CollectionType.doing] ?? 0,
                              label: CollectionType.doing.labelFor(
                                _subjectType,
                              ),
                              selected: _statusFilter == CollectionType.doing,
                              onTap: () => _selectStatus(CollectionType.doing),
                            ),
                            _StatCard(
                              width: width,
                              value: _counts[CollectionType.done] ?? 0,
                              label: CollectionType.done.labelFor(_subjectType),
                              selected: _statusFilter == CollectionType.done,
                              onTap: () => _selectStatus(CollectionType.done),
                            ),
                            _StatCard(
                              width: width,
                              value: _counts[CollectionType.wish] ?? 0,
                              label: CollectionType.wish.labelFor(_subjectType),
                              selected: _statusFilter == CollectionType.wish,
                              onTap: () => _selectStatus(CollectionType.wish),
                            ),
                            _StatCard(
                              width: width,
                              value: _counts[CollectionType.onHold] ?? 0,
                              label: CollectionType.onHold.labelFor(
                                _subjectType,
                              ),
                              selected: _statusFilter == CollectionType.onHold,
                              onTap: () => _selectStatus(CollectionType.onHold),
                            ),
                            _StatCard(
                              width: width,
                              value: _counts[CollectionType.dropped] ?? 0,
                              label: CollectionType.dropped.labelFor(
                                _subjectType,
                              ),
                              selected: _statusFilter == CollectionType.dropped,
                              onTap: () =>
                                  _selectStatus(CollectionType.dropped),
                            ),
                            _StatCard(
                              width: width,
                              value: _totalCount,
                              label: '全部',
                              selected: _statusFilter == null,
                              onTap: () => _selectStatus(null),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _statusFilter == null
                                ? '收藏列表'
                                : _statusFilter!.labelFor(_subjectType),
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        Text(
                          _loadingCollections
                              ? '加载中…'
                              : '${_items.length} 部'
                                    '${_statusFilter != null && (_counts[_statusFilter] ?? 0) > _items.length ? '（预览）' : ''}',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ),
            if (_loadingCollections && _items.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null && _items.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: EmptyState(
                    icon: Icons.cloud_off_outlined,
                    title: '收藏加载失败',
                    message: _error!,
                    action: FilledButton.tonalIcon(
                      onPressed: _loadCollections,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('重试'),
                    ),
                  ),
                ),
              )
            else if (_items.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: EmptyState(
                    icon: Icons.inbox_outlined,
                    title: '这里还是空的',
                    message: '该用户可能没有公开此状态的收藏，或尚未添加作品。',
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
                sliver: SliverLayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.crossAxisExtent >= 1050
                        ? 3
                        : constraints.crossAxisExtent >= 640
                        ? 2
                        : 1;
                    return SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        mainAxisExtent: 128,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                      ),
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final collection = _items[index];
                        return SubjectTile(
                          subject: collection.subject,
                          collection: collection,
                          showTypeBadge: false,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => SubjectDetailScreen(
                                subject: collection.subject,
                              ),
                            ),
                          ),
                        );
                      }, childCount: _items.length),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _selectStatus(CollectionType? type) {
    if (_statusFilter == type) return;
    setState(() => _statusFilter = type);
    _loadCollections();
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.width,
    required this.value,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final double width;
  final int value;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: width,
      child: Material(
        color: selected
            ? scheme.primaryContainer.withValues(alpha: .75)
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
            child: Column(
              children: [
                Text(
                  '$value',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: selected ? scheme.onPrimaryContainer : null,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: selected
                        ? scheme.onPrimaryContainer
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
