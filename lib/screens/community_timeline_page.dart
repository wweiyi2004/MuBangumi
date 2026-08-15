import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/community_service.dart';
import '../models/bangumi_models.dart';
import '../models/community_models.dart';
import '../state/user_preferences_controller.dart';
import '../widgets/community_composer.dart';
import '../widgets/community_widgets.dart';
import 'subject_detail_screen.dart';
import 'user_profile_page.dart';

class CommunityTimelinePage extends ConsumerStatefulWidget {
  const CommunityTimelinePage({
    super.key,
    this.initialMode = CommunityTimelineMode.friends,
    this.initialTimelineId,
    this.username,
  });

  final CommunityTimelineMode initialMode;
  final int? initialTimelineId;
  final String? username;

  @override
  ConsumerState<CommunityTimelinePage> createState() =>
      _CommunityTimelinePageState();
}

class _CommunityTimelinePageState extends ConsumerState<CommunityTimelinePage> {
  final _service = CommunityService.shared;
  final _scrollController = ScrollController();
  final _initialTimelineKey = GlobalKey();
  late CommunityTimelineMode _mode;
  List<CommunityTimelineItem> _items = const [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;
  int _requestId = 0;
  final Map<int, List<CommunityTimelineReply>> _replies = {};
  final Set<int> _expandedReplies = {};
  final Set<int> _loadingReplies = {};
  final Map<int, String> _replyErrors = {};
  bool _initialTargetRevealed = false;
  bool _initialTargetFailed = false;

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
    _scrollController.addListener(_onScroll);
    unawaited(_loadCacheThenRefresh());
  }

  void _onScroll() {
    if (_scrollController.position.extentAfter < 500) {
      unawaited(_loadMore());
    }
  }

  Future<void> _loadCacheThenRefresh() async {
    final mode = _mode;
    final requestId = ++_requestId;
    if (!_isUserTimeline && _anchorUntil == null) {
      final cached = await _service.readCachedTimeline(mode);
      if (cached != null &&
          cached.isNotEmpty &&
          mounted &&
          requestId == _requestId &&
          mode == _mode) {
        setState(() {
          _items = cached;
          _loading = false;
        });
      }
    }
    await _load(refresh: true, requestId: requestId);
  }

  Future<List<CommunityTimelineItem>> _fetchTimeline({
    required CommunityTimelineMode mode,
    int? until,
    bool refresh = false,
  }) {
    final username = widget.username?.trim() ?? '';
    if (username.isNotEmpty) {
      return _service.loadUserTimeline(
        username,
        limit: 20,
        until: until,
        refresh: refresh,
      );
    }
    return _service.loadTimeline(mode, until: until, refresh: refresh);
  }

  Future<void> _load({bool refresh = false, int? requestId}) async {
    final mode = _mode;
    final activeRequest = requestId ?? ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _fetchTimeline(
        mode: mode,
        until: _anchorUntil,
        refresh: refresh,
      );
      if (!mounted || activeRequest != _requestId || mode != _mode) return;
      setState(() {
        _items = items;
        _hasMore = items.length >= 20;
        _loading = false;
      });
      _revealInitialTarget();
    } catch (error) {
      if (!mounted || activeRequest != _requestId || mode != _mode) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
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
    if (_loading || _loadingMore || !_hasMore || _items.isEmpty) return;
    final mode = _mode;
    final requestId = _requestId;
    setState(() => _loadingMore = true);
    try {
      final next = await _fetchTimeline(mode: mode, until: _items.last.id);
      if (!mounted || mode != _mode || requestId != _requestId) return;
      final known = _items.map((item) => item.id).toSet();
      setState(() {
        _items = [..._items, ...next.where((item) => known.add(item.id))];
        _hasMore = next.length >= 20;
      });
    } catch (error) {
      if (!mounted || mode != _mode || requestId != _requestId) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _selectMode(CommunityTimelineMode mode) {
    if (_mode == mode || _isUserTimeline) return;
    setState(() {
      _mode = mode;
      _items = const [];
      _hasMore = true;
      _error = null;
      _loadingMore = false;
      _initialTargetFailed = true;
      _replies.clear();
      _expandedReplies.clear();
      _loadingReplies.clear();
      _replyErrors.clear();
    });
    unawaited(_loadCacheThenRefresh());
  }

  Future<void> _post() async {
    final sent = await showCommunityComposer(
      context,
      heading: '发布动态',
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
    final sent = await showCommunityComposer(
      context,
      heading: '回复 $target',
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
    await _load(refresh: true);
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
    if (_loadingReplies.contains(item.id)) return;
    setState(() {
      _loadingReplies.add(item.id);
      _replyErrors.remove(item.id);
    });
    try {
      final replies = await _service.loadTimelineReplies(
        item.id,
        refresh: refresh,
      );
      if (!mounted) return;
      setState(() {
        _replies[item.id] = replies;
        _loadingReplies.remove(item.id);
      });
    } catch (error) {
      if (!mounted) return;
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
      MaterialPageRoute<void>(
        builder: (_) => SubjectDetailScreen(subject: subject),
      ),
    );
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (!_isUserTimeline) ...[
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
            FilledButton.icon(
              onPressed: _service.isAuthenticated ? _post : null,
              icon: const Icon(Icons.edit_rounded, size: 18),
              label: const Text('发动态'),
            ),
          ],
        ),
        const SizedBox(height: 12),
      ],
      Expanded(child: _buildBody()),
    ],
  );

  Widget _buildBody() {
    final preferences = ref.watch(userPreferencesProvider);
    if (_loading && _items.isEmpty) {
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
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 30),
        itemCount: _items.length + 1,
        itemBuilder: (context, index) {
          if (index == _items.length) {
            return Padding(
              padding: const EdgeInsets.all(18),
              child: Center(
                child: _loadingMore
                    ? const CircularProgressIndicator()
                    : Text(_hasMore ? '继续向下浏览' : '已经到底了'),
              ),
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
