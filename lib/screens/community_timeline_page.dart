import '../core/theme/anime_icon.dart';
import '../state/service_providers.dart';
import '../navigation/app_destination.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/community_service.dart';
import '../models/bangumi_models.dart';
import '../models/community_models.dart';
import '../state/user_preferences_controller.dart';
import '../widgets/community_composer.dart';
import '../widgets/community_widgets.dart';
import '../widgets/community_loading.dart';
import '../widgets/community_paging.dart';
import 'community_target_navigation.dart';
import 'website_login_screen.dart';

class CommunityTimelinePage extends ConsumerStatefulWidget {
  const CommunityTimelinePage({
    super.key,
    this.service,
    this.tokenProvider,
    this.initialMode = CommunityTimelineMode.friends,
    this.initialTimelineId,
    this.username,
    this.showModeSelector = true,
    this.usePrimaryScrollController = false,
  });

  final CommunityService? service;
  final CommunityTokenProvider? tokenProvider;
  final CommunityTimelineMode initialMode;
  final int? initialTimelineId;
  final String? username;
  final bool showModeSelector;
  final bool usePrimaryScrollController;

  @override
  ConsumerState<CommunityTimelinePage> createState() =>
      _CommunityTimelinePageState();
}

class _CommunityTimelinePageState extends ConsumerState<CommunityTimelinePage> {
  late final _service = widget.service ?? communityServiceFor(context);
  final _scrollController = ScrollController();
  final _initialTimelineKey = GlobalKey();
  late CommunityTimelineMode _mode;
  List<CommunityTimelineItem> _items = const [];
  final _paging = CommunityPaging(loading: true);
  String? _error;
  int _requestId = 0;
  int _lastSuccessfulRequest = -1;
  int? _nextUntil;
  int? _nextWebsitePage;
  String? _sourceNotice;
  bool _websiteLoginRequired = false;
  final Map<int, List<CommunityTimelineReply>> _replies = {};
  final Set<int> _expandedReplies = {};
  final Set<int> _loadingReplies = {};
  final Map<int, String> _replyErrors = {};
  final Map<int, int> _replyRequestIds = {};
  int _replyGeneration = 0;
  bool _initialTargetRevealed = false;
  bool _initialTargetFailed = false;
  final _mutationBusy = <int>{};
  final _deletedIds = <int>{};
  final _reactionOverrides = <int, List<CommunityReaction>>{};
  Timer? _refreshTimer;
  late final AppLifecycleListener _lifecycleListener;
  bool? _visible;
  bool _foreground = true;

  List<CommunityTimelineItem> _visibleItems(
    List<CommunityTimelineItem> items,
  ) => items
      .where((item) => !_deletedIds.contains(item.id))
      .map(
        (item) => _reactionOverrides.containsKey(item.id)
            ? item.copyWith(reactions: _reactionOverrides[item.id])
            : item,
      )
      .toList();

  bool get _isUserTimeline => widget.username?.trim().isNotEmpty == true;

  bool get _initialTargetSettled =>
      _initialTargetRevealed || _initialTargetFailed;

  int? get _anchorUntil {
    if (_initialTargetSettled) return null;
    final targetId = widget.initialTimelineId;
    if (targetId == null || targetId <= 0) return null;
    return targetId + 1;
  }

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    _service.accountChanges.addListener(_resetAccount);
    _service.contentPreferencesChanges.addListener(_resetAccount);
    _scrollController.addListener(_onScroll);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _lifecycleListener = AppLifecycleListener(
      onStateChange: (state) {
        final resumed = state == AppLifecycleState.resumed;
        final becameForeground = resumed && !_foreground;
        _foreground = resumed;
        _updateRefreshTimer();
        if (becameForeground) _scheduleVisibleRefresh();
      },
    );
    unawaited(_loadCacheThenRefresh());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Retained profile, community and shell tabs all propagate TickerMode.
    final visible = TickerMode.valuesOf(context).enabled;
    final becameVisible = _visible == false && visible;
    _visible = visible;
    _updateRefreshTimer();
    if (becameVisible) _scheduleVisibleRefresh();
  }

  void _updateRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    if (_visible == true && _foreground) {
      _refreshTimer = Timer.periodic(
        const Duration(seconds: 60),
        (_) => _refreshVisibleTimeline(),
      );
    }
  }

  void _scheduleVisibleRefresh() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refreshVisibleTimeline();
    });
  }

  void _refreshVisibleTimeline() {
    if (!mounted ||
        _visible != true ||
        !_foreground ||
        _paging.loading ||
        _paging.loadingMore ||
        widget.initialTimelineId != null) {
      return;
    }
    final controller = widget.usePrimaryScrollController
        ? PrimaryScrollController.maybeOf(context)
        : _scrollController;
    // Do not replace paginated history or move the reader while scrolling.
    if (controller != null &&
        controller.positions.any(
          (position) =>
              position.pixels > position.minScrollExtent + 8 ||
              position.isScrollingNotifier.value,
        )) {
      return;
    }
    unawaited(_load(refresh: true));
  }

  void _onScroll() {
    if (_paging.shouldLoadMore(_scrollController.position, threshold: 500)) {
      unawaited(_loadMore());
    }
  }

  void _resetAccount() {
    _requestId++;
    _replyGeneration++;
    scheduleMicrotask(() {
      if (!mounted) return;
      setState(() {
        _items = [];
        _mutationBusy.clear();
        _deletedIds.clear();
        _reactionOverrides.clear();
        _replies.clear();
        _expandedReplies.clear();
        _loadingReplies.clear();
        _replyErrors.clear();
        _replyRequestIds.clear();
        _nextUntil = null;
        _nextWebsitePage = null;
        _sourceNotice = null;
        _websiteLoginRequired = false;
        _paging.hasMore = true;
      });
      unawaited(_load(refresh: true));
    });
  }

  Future<void> _react(CommunityTimelineItem item, int? value) async {
    if (_mutationBusy.contains(item.id)) return;
    final identity = _service.identityRevision;
    final username = _service.currentUsername;
    if (username == null) return;
    setState(() => _mutationBusy.add(item.id));
    try {
      await _service.updateTimelineReaction(item, value);
      if (!mounted || identity != _service.identityRevision) return;
      final current =
          _items.where((row) => row.id == item.id).firstOrNull ?? item;
      final reactions = <CommunityReaction>[];
      for (final reaction in current.reactions) {
        final users = reaction.users
            .where(
              (user) => user.username.toLowerCase() != username.toLowerCase(),
            )
            .toList();
        if (users.isNotEmpty) {
          reactions.add(CommunityReaction(value: reaction.value, users: users));
        }
      }
      if (value != null) {
        final selected = reactions
            .where((reaction) => reaction.value == value)
            .firstOrNull;
        reactions.removeWhere((reaction) => reaction.value == value);
        reactions.add(
          CommunityReaction(
            value: value,
            users: [
              ...?selected?.users,
              CommunityUser(id: 0, username: username, nickname: username),
            ],
          ),
        );
      }
      setState(() {
        _reactionOverrides[item.id] = reactions;
        _items = _visibleItems(_items);
      });
    } catch (error) {
      if (mounted && identity == _service.identityRevision) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$error'.replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted && identity == _service.identityRevision) {
        setState(() => _mutationBusy.remove(item.id));
      }
    }
  }

  Future<void> _delete(CommunityTimelineItem item) async {
    if (_mutationBusy.contains(item.id) || !_service.canDeleteTimeline(item)) {
      return;
    }
    final identity = _service.identityRevision;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这条动态？'),
        content: const Text('此动态及其所有回复都会被删除，无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true ||
        !mounted ||
        identity != _service.identityRevision) {
      return;
    }
    setState(() => _mutationBusy.add(item.id));
    try {
      await _service.deleteTimeline(item);
      if (!mounted || identity != _service.identityRevision) return;
      setState(() {
        _deletedIds.add(item.id);
        _items = _visibleItems(_items);
        _replies.remove(item.id);
        _expandedReplies.remove(item.id);
      });
      if (_items.isEmpty) await _load(refresh: true);
    } catch (error) {
      if (mounted && identity == _service.identityRevision) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$error'.replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted && identity == _service.identityRevision) {
        setState(() => _mutationBusy.remove(item.id));
      }
    }
  }

  Future<void> _loadCacheThenRefresh() async {
    final mode = _mode;
    final requestId = ++_requestId;
    final restoreAllowed = !_isUserTimeline && _anchorUntil == null;
    final network = _load(requestId: requestId, refresh: true);
    Future<void> restore() async {
      if (!restoreAllowed) return;
      try {
        final cached = await _service.readCachedTimeline(mode);
        if (!mounted ||
            requestId != _requestId ||
            _lastSuccessfulRequest == requestId ||
            cached == null ||
            cached.isEmpty) {
          return;
        }
        setState(() {
          _items = _visibleItems(cached);
          _nextUntil = cached.last.id;
          _paging.hasMore = cached.isNotEmpty;
        });
      } catch (_) {}
    }

    unawaited(restore());
    await network;
  }

  Future<CommunityTimelinePageResult> _fetchTimeline({
    required CommunityTimelineMode mode,
    int? until,
    int? websitePage,
    bool refresh = false,
  }) => _service.loadFreshTimelinePage(
    mode,
    username: widget.username,
    until: until,
    websitePage: websitePage,
    refresh: refresh,
  );

  Future<void> _load({bool refresh = false, int? requestId}) async {
    final mode = _mode;
    final activeRequest = requestId ?? ++_requestId;
    if (refresh) _reactionOverrides.clear();
    if (!mounted || activeRequest != _requestId) return;
    setState(() {
      _paging.begin();
      _error = null;
    });
    try {
      final anchor = _anchorUntil;
      CommunityTimelinePageResult? result;
      try {
        // Notification targets are usually recent, which P1 may not list yet.
        result = await _fetchTimeline(mode: mode, refresh: refresh);
      } catch (_) {
        if (anchor == null) rethrow;
      }
      if (!mounted || activeRequest != _requestId || mode != _mode) return;
      if (anchor != null &&
          result?.items.any((item) => item.id == widget.initialTimelineId) !=
              true) {
        // Older targets are beyond the website's first page: use the ID cursor.
        result = await _fetchTimeline(
          mode: mode,
          until: anchor,
          refresh: refresh,
        );
        if (!mounted || activeRequest != _requestId || mode != _mode) return;
      }
      final page = result!;
      final items = page.items;
      setState(() {
        final keepCurrent =
            page.notice != null &&
            _items.isNotEmpty &&
            _lastSuccessfulRequest >= 0;
        if (!keepCurrent) {
          _items = _visibleItems(items);
          _nextUntil = page.nextUntil;
          _nextWebsitePage = page.nextPage;
          _paging.hasMore = page.hasMore;
        }
        _lastSuccessfulRequest = activeRequest;
        _sourceNotice = page.notice;
        _websiteLoginRequired = page.websiteLoginRequired;
        _paging.loading = false;
      });
      _revealInitialTarget();
    } catch (error) {
      if (!mounted || activeRequest != _requestId || mode != _mode) return;
      setState(() {
        _paging.loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _verifyWebsiteLogin() async {
    if (await openWebsiteLoginScreen(context) == true && mounted) {
      await _load(refresh: true);
    }
  }

  void _revealInitialTarget() {
    final targetId = widget.initialTimelineId;
    if (_initialTargetSettled || targetId == null || targetId <= 0) return;
    CommunityTimelineItem? target;
    for (final item in _items) {
      if (item.id == targetId) {
        target = item;
        break;
      }
    }
    if (target == null) {
      _failInitialTarget();
      return;
    }
    _initialTargetRevealed = true;
    _expandedReplies.add(targetId);
    unawaited(_loadReplies(target));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final targetContext = _initialTimelineKey.currentContext;
      if (!mounted || targetContext == null) return;
      Scrollable.ensureVisible(
        targetContext,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        alignment: 0.15,
      );
    });
  }

  void _failInitialTarget() {
    if (_initialTargetSettled) return;
    _initialTargetFailed = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(const SnackBar(content: Text('没有找到对应的动态')));
    });
  }

  Future<void> _loadMore() async {
    if (!_paging.canLoadMore || _items.isEmpty) return;
    final mode = _mode;
    final requestId = _requestId;
    setState(_paging.beginLoadMore);
    try {
      final cursor = _nextUntil;
      final websitePage = _nextWebsitePage;
      final result = await _fetchTimeline(
        mode: mode,
        until: cursor,
        websitePage: websitePage,
      );
      final next = result.items;
      if (!mounted || mode != _mode || requestId != _requestId) return;
      final known = _items.map((item) => item.id).toSet();
      // A page can start mid-run of one user's events, without the avatar.
      final avatars = {
        for (final item in _items)
          if (item.user.avatarUrl.isNotEmpty)
            item.user.username.toLowerCase(): item.user,
      };
      setState(() {
        final added = [
          for (final item in next)
            if (known.add(item.id))
              item.user.avatarUrl.isEmpty &&
                      avatars[item.user.username.toLowerCase()] != null
                  ? item.copyWith(
                      user: CommunityUser(
                        id: item.user.id,
                        username: item.user.username,
                        nickname: item.user.nickname,
                        avatarUrl: avatars[item.user.username.toLowerCase()]!
                            .avatarUrl,
                        joinedAt: item.user.joinedAt,
                      ),
                    )
                  : item,
        ];
        _items = _visibleItems([..._items, ...added]);
        _nextUntil = result.nextUntil;
        _nextWebsitePage = result.nextPage;
        _paging.hasMore =
            result.hasMore &&
            (websitePage != null
                ? result.nextPage != null && result.nextPage! > websitePage
                : added.isNotEmpty &&
                      _nextUntil != null &&
                      cursor != null &&
                      _nextUntil! < cursor);
      });
    } catch (error) {
      if (!mounted || mode != _mode || requestId != _requestId) return;
      setState(() {
        _paging.loadMoreError = error.toString().replaceFirst(
          'Exception: ',
          '',
        );
      });
    } finally {
      if (mounted && requestId == _requestId) {
        setState(() => _paging.loadingMore = false);
      }
    }
  }

  void _selectMode(CommunityTimelineMode mode) {
    if (_mode == mode || _isUserTimeline) return;
    setState(() {
      _mode = mode;
      _items = const [];
      _paging.reset();
      _nextUntil = null;
      _nextWebsitePage = null;
      _sourceNotice = null;
      _websiteLoginRequired = false;
      _error = null;
      _initialTargetFailed = true;
      _replies.clear();
      _expandedReplies.clear();
      _loadingReplies.clear();
      _replyErrors.clear();
      _replyRequestIds.clear();
    });
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
    unawaited(_loadCacheThenRefresh());
  }

  Future<void> _post() async {
    final draftAccount = _service.currentUsername;
    final sent = await showCommunityComposer(
      context,
      heading: '发布动态',
      tokenProvider: widget.tokenProvider,
      isAccountCurrent: () =>
          _service.isAuthenticated && _service.currentUsername == draftAccount,
      draftKey: communityDraftKey(draftAccount, ['timeline', 'post']),
      contentLabel: '今天有什么新鲜事？',
      maxLength: 380,
      onSubmit: (_, content, token) =>
          _service.postTimeline(content: content, turnstileToken: token),
    );
    if (!sent || !mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('动态已发布')));
    await _load(refresh: true);
  }

  Future<void> _reply(
    CommunityTimelineItem item, {
    CommunityTimelineReply? reply,
    CommunityTimelineReply? parent,
  }) async {
    final target = reply?.user.displayName ?? item.user.displayName;
    final draftAccount = _service.currentUsername;
    final sent = await showCommunityComposer(
      context,
      heading: '回复 $target',
      tokenProvider: widget.tokenProvider,
      isAccountCurrent: () =>
          _service.isAuthenticated && _service.currentUsername == draftAccount,
      draftKey: communityDraftKey(draftAccount, [
        'timeline',
        item.id,
        reply?.id ?? 0,
      ]),
      onSubmit: (_, content, token) => _service.replyToTimeline(
        timelineId: item.id,
        content: content,
        turnstileToken: token,
        replyTo: reply == null ? null : (parent?.id ?? reply.id),
      ),
    );
    if (!sent || !mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('回复已发送')));
    setState(() => _expandedReplies.add(item.id));
    await _loadReplies(item, refresh: true);
    if (!mounted) return;
    setState(() {
      _items = [
        for (final current in _items)
          if (current.id == item.id)
            current.copyWith(
              replyCount: current.replyCount > item.replyCount
                  ? current.replyCount
                  : item.replyCount + 1,
            )
          else
            current,
      ];
    });
  }

  void _toggleReplies(CommunityTimelineItem item) {
    if (_expandedReplies.contains(item.id)) {
      setState(() => _expandedReplies.remove(item.id));
      return;
    }
    setState(() => _expandedReplies.add(item.id));
    if (!_replies.containsKey(item.id)) {
      unawaited(_loadReplies(item));
    }
  }

  Future<void> _loadReplies(
    CommunityTimelineItem item, {
    bool refresh = false,
  }) async {
    if (_loadingReplies.contains(item.id) && !refresh) return;
    final mode = _mode;
    final requestId = ++_replyGeneration;
    _replyRequestIds[item.id] = requestId;
    setState(() {
      _loadingReplies.add(item.id);
      _replyErrors.remove(item.id);
    });
    try {
      final replies = await _service.loadTimelineReplies(
        item.id,
        refresh: refresh,
      );
      if (!mounted || mode != _mode || _replyRequestIds[item.id] != requestId) {
        return;
      }
      setState(() {
        _replies[item.id] = replies;
        _loadingReplies.remove(item.id);
      });
    } catch (error) {
      if (!mounted || mode != _mode || _replyRequestIds[item.id] != requestId) {
        return;
      }
      setState(() {
        _loadingReplies.remove(item.id);
        _replyErrors[item.id] = error.toString().replaceFirst(
          'Exception: ',
          '',
        );
      });
    }
  }

  void _openSubject(CommunityTimelineProgress progress) {
    final episodeCount = int.tryParse(progress.episodeTotal) ?? 0;
    final subject = Subject(
      id: progress.subjectId,
      name: progress.subjectName,
      nameCn: progress.subjectNameCn,
      imageUrl: progress.imageUrl,
      summary: '',
      episodeCount: episodeCount,
      score: progress.score,
      rank: progress.rank,
      date: progress.episode?.airDate ?? '',
    );
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => SubjectRoute(subject: subject)),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _lifecycleListener.dispose();
    _service.accountChanges.removeListener(_resetAccount);
    _service.contentPreferencesChanges.removeListener(_resetAccount);
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (!_isUserTimeline && widget.showModeSelector) ...[
        Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<CommunityTimelineMode>(
                  segments: [
                    for (final mode in CommunityTimelineMode.values)
                      ButtonSegment(value: mode, label: Text(mode.label)),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (value) => _selectMode(value.first),
                  showSelectedIcon: false,
                ),
              ),
            ),
            const SizedBox(width: 10),
            IconButton(
              tooltip: '刷新动态',
              onPressed: _paging.loading ? null : () => _load(refresh: true),
              icon: const AnimeIcon(Icons.refresh_rounded),
            ),
          ],
        ),
        const SizedBox(height: 12),
      ],
      if (_isUserTimeline || !widget.showModeSelector)
        Align(
          alignment: Alignment.centerRight,
          child: IconButton(
            tooltip: '刷新动态',
            onPressed: _paging.loading ? null : () => _load(refresh: true),
            icon: const AnimeIcon(Icons.refresh_rounded),
          ),
        ),
      if (_items.isNotEmpty)
        CommunityRefreshStatus(
          loading: _paging.loading,
          error: _error,
          onRetry: () => _load(refresh: true),
        ),
      if (_sourceNotice != null && _websiteLoginRequired)
        _WebsiteLoginNotice(
          message: _sourceNotice!,
          onVerify: _verifyWebsiteLogin,
        )
      else if (_sourceNotice != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            _sourceNotice!,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      Expanded(
        child: Stack(
          children: [
            Positioned.fill(
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (widget.usePrimaryScrollController &&
                      _paging.shouldLoadMoreOnNotification(
                        notification,
                        threshold: 500,
                      )) {
                    unawaited(_loadMore());
                  }
                  return false;
                },
                child: _buildBody(),
              ),
            ),
            if (!_isUserTimeline && _service.isAuthenticated)
              Positioned(
                right: 12,
                bottom: 16,
                child: FloatingActionButton(
                  heroTag: 'compose-timeline-${_mode.name}',
                  tooltip: '发动态',
                  onPressed: _post,
                  child: const AnimeIcon(Icons.edit_outlined),
                ),
              ),
          ],
        ),
      ),
    ],
  );

  Widget _buildBody() {
    final preferences = ref.watch(userPreferencesProvider);
    if (_paging.loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _items.isEmpty) {
      return CommunityErrorView(
        message: _error!,
        onRetry: () => _load(refresh: true),
      );
    }
    if (_items.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _load(refresh: true),
        child: ListView(
          primary: widget.usePrimaryScrollController,
          controller: widget.usePrimaryScrollController
              ? null
              : _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 100),
            Center(child: Text('暂时没有动态')),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _load(refresh: true),
      child: ListView.builder(
        key: PageStorageKey('timeline-${_mode.name}-${widget.username ?? ''}'),
        primary: widget.usePrimaryScrollController,
        controller: widget.usePrimaryScrollController
            ? null
            : _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 88),
        itemCount: _items.length + 1,
        itemBuilder: (context, index) {
          if (index == _items.length) {
            return CommunityLoadMoreFooter(
              loading: _paging.loadingMore,
              hasMore: _paging.hasMore,
              error: _paging.loadMoreError,
              onLoad: _paging.loading ? null : () => _loadMore(),
            );
          }
          final item = _items[index];
          final progress = item.progress;
          final canReply = _service.isAuthenticated && item.isStatus;
          return BlockedCommunityContent(
            key: item.id == widget.initialTimelineId
                ? _initialTimelineKey
                : ValueKey('timeline-${item.id}'),
            username: item.user.username,
            blocked: preferences.isBlocked(item.user.username),
            child: CommunityTimelineCard(
              item: item,
              onOpenTarget: (target) =>
                  openCommunityTimelineTarget(context, target),
              currentUsername: _service.currentUsername,
              reactionBusy: _mutationBusy.contains(item.id),
              onReactionChanged: canReply
                  ? (value) => _react(item, value)
                  : null,
              onDelete:
                  _service.canDeleteTimeline(item) &&
                      !_mutationBusy.contains(item.id)
                  ? () => _delete(item)
                  : null,
              onReply: canReply ? () => _reply(item) : null,
              onOpenSubject: progress == null
                  ? null
                  : () => _openSubject(progress),
              onOpenUser: (user) => openUserProfileFromCommunity(context, user),
              replies: _replies[item.id],
              repliesExpanded: _expandedReplies.contains(item.id),
              repliesLoading: _loadingReplies.contains(item.id),
              repliesError: _replyErrors[item.id],
              onToggleReplies: item.isStatus
                  ? () => _toggleReplies(item)
                  : null,
              onReloadReplies: item.isStatus
                  ? () => _loadReplies(item, refresh: true)
                  : null,
              onReplyTo: canReply
                  ? (reply, parent) =>
                        _reply(item, reply: reply, parent: parent)
                  : null,
            ),
          );
        },
      ),
    );
  }
}

/// Shown when only verifying web login can bring the friends feed up to date.
class _WebsiteLoginNotice extends StatelessWidget {
  const _WebsiteLoginNotice({required this.message, required this.onVerify});
  final String message;
  final VoidCallback onVerify;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: scheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        child: Row(
          children: [
            AnimeIcon(
              Icons.history_toggle_off_rounded,
              color: scheme.onTertiaryContainer,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: scheme.onTertiaryContainer),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: onVerify,
              child: const Text('验证网页登录'),
            ),
          ],
        ),
      ),
    );
  }
}

class CommunityTimelineScreen extends StatelessWidget {
  const CommunityTimelineScreen({
    super.key,
    this.initialMode = CommunityTimelineMode.friends,
    this.initialTimelineId,
    this.username,
  });

  final CommunityTimelineMode initialMode;
  final int? initialTimelineId;
  final String? username;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('时光机')),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
        child: CommunityTimelinePage(
          initialMode: initialMode,
          initialTimelineId: initialTimelineId,
          username: username,
        ),
      ),
    ),
  );
}
