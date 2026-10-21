import 'dart:convert';
import '../state/community_submission_controller.dart';
import '../widgets/community_submission_card.dart';
import '../widgets/content_loading.dart';
import '../models/community_topic_submission.dart';
import '../core/theme/anime_icon.dart';
import '../state/service_providers.dart';
import '../navigation/app_destination.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import '../widgets/social_chat_style.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../core/storage/browsing_store.dart';
import '../core/auth/website_identity.dart';
import '../models/topic_reading_position.dart';
import '../state/session_controller.dart';

import '../core/network/community_service.dart';
import '../models/community_models.dart';
import '../state/user_preferences_controller.dart';
import '../widgets/community_composer.dart';
import '../widgets/community_widgets.dart';
import '../widgets/community_loading.dart';
import 'website_login_screen.dart';

class CommunityTopicScreen extends ConsumerStatefulWidget {
  const CommunityTopicScreen({super.key, required this.topic, this.service});
  final CommunityService? service;

  final CommunityTopic topic;

  @override
  ConsumerState<CommunityTopicScreen> createState() =>
      _CommunityTopicScreenState();
}

class _CommunityTopicScreenState extends ConsumerState<CommunityTopicScreen> {
  late final _service = widget.service ?? communityServiceFor(context);
  CommunityTopicDetail? _detail;
  bool _loading = true;
  int _requestId = 0;
  String? _error;
  bool _needsWebsiteRecovery = false;
  Set<String> _friendUsernames = const {};
  final Set<String> _reactionBusyPostIds = {};
  final Set<String> _mutationBusyPostIds = {};
  final _itemScroll = ItemScrollController();
  final _positions = ItemPositionsListener.create();
  late final TopicReadingRepository _readingStore;
  late final AppLifecycleListener _lifecycle;
  String _readingAccount = '';
  TopicReadingPosition? _resumePosition, _candidate;
  Timer? _saveTimer;
  bool _trackReading = false;
  int _readingGeneration = 0;
  String? _readingError;
  String _filter = 'all';
  bool _friendsLoading = false;
  bool _friendsFailed = false;
  bool _targetNavigationHandled = false;
  int? get _targetPostId =>
      widget.topic.targetPostId ??
      int.tryParse(
        RegExp(r'^post_(\d+)$')
                .firstMatch(Uri.tryParse(widget.topic.webUrl)?.fragment ?? '')
                ?.group(1) ??
            '',
      );
  String get _topicKey =>
      '${widget.topic.kind.name}:${_service.resolveTopicId(widget.topic) ?? widget.topic.url}';
  bool get _sameReadingAccount =>
      (_service.currentUsername ?? '') == _readingAccount;

  @override
  void initState() {
    super.initState();
    _readingStore = ref.read(topicReadingRepositoryProvider);
    _readingAccount = _service.currentUsername ?? '';
    _positions.itemPositions.addListener(_recordVisiblePost);
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        if (state != AppLifecycleState.resumed) unawaited(_savePosition());
      },
    );
    ref.listenManual(sessionProvider.select((s) => s.user?.username), (_, _) {
      Future.microtask(() {
        if (!mounted || _sameReadingAccount) return;
        _saveTimer?.cancel();
        setState(() {
          _readingAccount = _service.currentUsername ?? '';
          _resumePosition = null;
          _candidate = null;
          _trackReading = false;
          _readingError = null;
          _filter = 'all';
          _friendUsernames = const {};
          _detail = null;
          _targetNavigationHandled = false;
        });
        unawaited(_loadReadingPosition());
        unawaited(_load());
        unawaited(_loadFriendUsernames());
      });
    });
    unawaited(_loadReadingPosition());
    unawaited(_load());
    unawaited(_loadFriendUsernames());
  }

  Future<void> _loadReadingPosition() async {
    final generation = ++_readingGeneration;
    final account = _readingAccount;
    if (account.isEmpty) return;
    try {
      final saved = await _readingStore.readTopicPosition(account, _topicKey);
      if (!mounted ||
          generation != _readingGeneration ||
          !_sameReadingAccount) {
        return;
      }
      setState(() {
        _resumePosition = saved;
        _readingError = null;
      });
    } catch (_) {
      if (mounted && generation == _readingGeneration && _sameReadingAccount) {
        setState(() => _readingError = '读取阅读位置失败');
      }
    }
  }

  void _recordVisiblePost() {
    if (!_trackReading ||
        _filter != 'all' ||
        !_sameReadingAccount ||
        _readingAccount.isEmpty) {
      return;
    }
    final posts = _detail?.posts;
    if (posts == null || posts.isEmpty) return;
    final visible =
        _positions.itemPositions.value
            .where(
              (p) =>
                  p.index > 0 &&
                  p.itemTrailingEdge > 0 &&
                  p.itemLeadingEdge < 1,
            )
            .toList()
          ..sort((a, b) => a.index.compareTo(b.index));
    if (visible.isEmpty) return;
    final index = visible.first.index - 1;
    if (index >= posts.length) return;
    _candidate = TopicReadingPosition(postId: posts[index].id, index: index);
    _saveTimer?.cancel();
    _saveTimer = Timer(
      const Duration(milliseconds: 450),
      () => unawaited(_savePosition()),
    );
  }

  Future<void> _savePosition() async {
    final position = _candidate;
    final account = _readingAccount;
    if (position == null || account.isEmpty || !_sameReadingAccount) return;
    try {
      await _readingStore.saveTopicPosition(account, _topicKey, position);
      if (mounted &&
          account == _readingAccount &&
          _sameReadingAccount &&
          _readingError != null) {
        setState(() => _readingError = null);
      }
    } catch (_) {
      if (mounted && account == _readingAccount && _sameReadingAccount) {
        setState(() => _readingError = '阅读位置未保存，请重试');
      }
    }
  }

  void _resumeReading() {
    final saved = _resumePosition;
    final posts = _detail?.posts;
    if (saved == null ||
        posts == null ||
        posts.isEmpty ||
        !_sameReadingAccount) {
      return;
    }
    var index = posts.indexWhere((post) => post.id == saved.postId);
    final missing = index < 0;
    if (missing) index = saved.index.clamp(0, posts.length - 1);
    setState(() {
      _filter = 'all';
      _trackReading = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_sameReadingAccount || !_itemScroll.isAttached) return;
      _itemScroll.jumpTo(index: index + 1);
      _trackReading = true;
      if (missing) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('原楼层已移除，已定位到附近内容')));
      }
    });
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    unawaited(_savePosition());
    _lifecycle.dispose();
    _positions.itemPositions.removeListener(_recordVisiblePost);
    super.dispose();
  }

  Future<void> _loadFriendUsernames() async {
    final username = _service.currentUsername;
    if (username == null || username.isEmpty) return;
    setState(() {
      _friendsLoading = true;
      _friendsFailed = false;
    });
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted || _service.currentUsername != username) return;
    try {
      final friends = await _service.loadAllFriends(username);
      if (!mounted || _service.currentUsername != username) return;
      setState(() {
        _friendUsernames = {
          for (final friend in friends) friend.username.toLowerCase(),
        };
        _friendsLoading = false;
      });
    } catch (_) {
      if (mounted && _service.currentUsername == username) {
        setState(() {
          _friendsLoading = false;
          _friendsFailed = true;
        });
      }
    }
  }

  Future<void> _load({bool refresh = false, int? requestId}) async {
    if (!mounted) return;
    final activeRequest = requestId ?? ++_requestId;
    final account = _service.currentUsername;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _needsWebsiteRecovery = false;
      });
    }
    try {
      final detail = await _service.loadTopic(widget.topic, refresh: refresh);
      if (!mounted ||
          activeRequest != _requestId ||
          account != _service.currentUsername) {
        return;
      }
      setState(() {
        _detail = detail;
        _loading = false;
      });
      _locateTargetPost(activeRequest);
    } catch (error) {
      if (!mounted ||
          activeRequest != _requestId ||
          account != _service.currentUsername) {
        return;
      }
      setState(() {
        _loading = false;
        _error = error is FormatException
            ? error.message
            : error.toString().replaceFirst('Exception: ', '');
        _needsWebsiteRecovery =
            error is WebsiteAccessException && error.status.requiresLogin;
      });
    }
  }

  void _locateTargetPost(int requestId) {
    final target = _targetPostId;
    if (_targetNavigationHandled || target == null || target <= 0) return;
    final index = _detail!.posts.indexWhere(
      (post) => CommunityService.parseReplyId(post.id) == target,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || requestId != _requestId || !_sameReadingAccount) return;
      if (index < 0) {
        _targetNavigationHandled = true;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('未找到目标回复，可能已被删除或暂时不可见')));
      } else if (_itemScroll.isAttached) {
        _itemScroll.jumpTo(index: index + 1);
        _targetNavigationHandled = true;
      }
    });
  }

  Future<void> _reply({CommunityPost? post}) async {
    if (widget.topic.kind.apiArea == null) {
      await _openWeb();
      return;
    }
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
    final draftAccount = _service.currentUsername;
    final identity = _service.identityRevision;
    final submission = CommunityTopicDraft(kind: 'reply')
      ..baselineIds = {
        for (final row in _detail?.posts ?? <CommunityPost>[]) row.id,
      };
    final registry = ref.read(communitySubmissionsProvider(_service));
    final key = communityDraftKey(draftAccount, [
      'topic',
      widget.topic.kind.name,
      topicId,
      post?.id ?? 'topic',
    ]);
    if (registry
        .forScope(_topicKey)
        .any(
          (entry) =>
              entry.draftKey == key &&
              entry.status == CommunitySubmissionStatus.publishing,
        )) {
      return;
    }
    var accepted = false;
    final sent = await showCommunityComposer(
      context,
      heading: post == null ? '回复话题' : '回复 ${post.author}',
      isAccountCurrent: () =>
          _service.isAuthenticated &&
          _service.currentUsername == draftAccount &&
          _service.identityRevision == identity,
      topicDraft: submission,
      onAccepted: (entry) {
        accepted = true;
        registry.add(_topicKey, entry);
        unawaited(
          entry.completion.then((_) {
            if (mounted &&
                entry.isAccountCurrent() &&
                entry.status == CommunitySubmissionStatus.sent) {
              unawaited(_load(refresh: true));
            }
          }),
        );
      },
      inspectSubmission: _openWeb,
      confirmSubmission: (_, content, attemptedAt) async {
        final detail = await _service.loadTopic(widget.topic, refresh: true);
        if (identity != _service.identityRevision) return false;
        final matches = detail.posts
            .where(
              (row) =>
                  !submission.baselineIds.contains(row.id) &&
                  _usernameFromUserUrl(row.userUrl)?.toLowerCase() ==
                      draftAccount?.toLowerCase() &&
                  (row.rawBody.isEmpty ? row.body : row.rawBody)
                          .replaceAll('\r\n', '\n')
                          .trim() ==
                      content.replaceAll('\r\n', '\n').trim() &&
                  row.createdAt != null &&
                  attemptedAt != null &&
                  !row.createdAt!.isBefore(
                    attemptedAt.subtract(const Duration(seconds: 5)),
                  ),
            )
            .toList();
        return matches.length == 1;
      },
      draftKey: communityDraftKey(draftAccount, [
        'topic',
        widget.topic.kind.name,
        topicId,
        post?.id ?? 'topic',
      ]),
      warning: _oldTopicWarning,
      replyContext: post == null ? null : '${post.author}：${post.body}',
      onSubmit: (_, content, token) => _service.replyToTopic(
        topic: widget.topic,
        content: content,
        turnstileToken: token,
        replyTo: replyTo,
      ),
    );
    if (!sent ||
        !mounted ||
        identity != _service.identityRevision ||
        accepted) {
      return;
    }
    registry.removeDraft(_topicKey, key);
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

  Future<void> _editPost(CommunityPost post) async {
    if (!_service.canManagePost(widget.topic, post)) return;
    final account = _service.currentUsername;
    final original = post.isOriginal && widget.topic.kind.isDiscussion;
    final saved = await showCommunityComposer(
      context,
      heading: original ? '编辑话题' : '编辑回复',
      requireTitle: original,
      initialTitle: _detail?.title ?? widget.topic.title,
      initialContent: post.rawBody,
      requireVerification: false,
      protectSubmission: false,
      submitLabel: '保存',
      isAccountCurrent: () =>
          _service.currentUsername == account && _service.isAuthenticated,
      draftKey: communityDraftKey(account, [
        'edit',
        widget.topic.kind.name,
        post.id,
      ]),
      onSubmit: (title, content, _) => _service.editPost(
        topic: widget.topic,
        post: post,
        title: title,
        content: content,
      ),
    );
    if (saved && mounted && account == _service.currentUsername) {
      await _load(refresh: true);
    }
  }

  Future<void> _deletePost(CommunityPost post) async {
    if (!_service.canManagePost(widget.topic, post) ||
        _mutationBusyPostIds.contains(post.id)) {
      return;
    }
    final account = _service.currentUsername;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这条回复？'),
        content: const Text('删除后无法恢复。'),
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
    if (confirmed != true || !mounted || account != _service.currentUsername) {
      return;
    }
    setState(() => _mutationBusyPostIds.add(post.id));
    try {
      await _service.deletePost(topic: widget.topic, post: post);
      if (mounted && account == _service.currentUsername) {
        await _load(refresh: true);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error
                  .toString()
                  .replaceFirst('Exception: ', '')
                  .replaceFirst('FormatException: ', ''),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _mutationBusyPostIds.remove(post.id));
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
      initialUrl: _targetPostId == null
          ? widget.topic.webUrl
          : Uri.parse(
              widget.topic.webUrl,
            ).replace(fragment: 'post_$_targetPostId').toString(),
      title: widget.topic.title,
      showSectionSwitcher: false,
    );
  }

  Future<void> _recoverWebsite() async {
    final identity = _service.identityRevision;
    if (await openWebsiteLoginScreen(context) == true &&
        mounted &&
        identity == _service.identityRevision) {
      await _load(refresh: true);
    }
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
    final groupDiscussion = widget.topic.kind == CommunityTopicKind.group;
    return Scaffold(
      backgroundColor: groupDiscussion ? SocialChatStyle.canvas(context) : null,
      bottomNavigationBar:
          groupDiscussion && _service.isAuthenticated && detail != null
          ? DiscussionReplyBar(onReply: _reply)
          : null,
      appBar: AppBar(
        backgroundColor: groupDiscussion
            ? SocialChatStyle.paper(context)
            : null,
        title: Text(groupDiscussion ? '小组讨论' : widget.topic.kind.label),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : () => _load(refresh: true),
            icon: const AnimeIcon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: '在官网查看',
            onPressed: _openWeb,
            icon: const AnimeIcon(Icons.language_rounded),
          ),
        ],
      ),
      floatingActionButton:
          !groupDiscussion && _service.isAuthenticated && detail != null
          ? FloatingActionButton.extended(
              onPressed: _reply,
              icon: const AnimeIcon(Icons.reply_rounded),
              label: Text(widget.topic.kind.apiArea == null ? '官网回复' : '回复'),
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
            if (detail != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final entry in {
                      'all': '全部',
                      if (detail.posts.any((post) => post.isOriginal))
                        'op': '只看楼主',
                      'friends': '只看好友',
                    }.entries)
                      ChoiceChip(
                        showCheckmark: !groupDiscussion,
                        selectedColor: groupDiscussion
                            ? SocialChatStyle.accent(
                                context,
                              ).withValues(alpha: .12)
                            : null,
                        label: Text(entry.value),
                        selected: _filter == entry.key,
                        onSelected:
                            entry.key == 'friends' &&
                                (_readingAccount.isEmpty ||
                                    _friendsLoading ||
                                    _friendsFailed)
                            ? null
                            : (_) {
                                unawaited(_savePosition());
                                _saveTimer?.cancel();
                                setState(() {
                                  _filter = entry.key;
                                  _candidate = null;
                                  _trackReading = false;
                                });
                              },
                      ),
                    if (_resumePosition != null)
                      TextButton.icon(
                        onPressed: _resumeReading,
                        icon: const AnimeIcon(Icons.history_rounded, size: 18),
                        label: const Text('继续上次阅读'),
                      ),
                    if (_friendsFailed)
                      TextButton(
                        onPressed: _loadFriendUsernames,
                        child: const Text('重试好友加载'),
                      ),
                    if (_readingError != null)
                      TextButton(
                        onPressed: () => _candidate == null
                            ? _loadReadingPosition()
                            : _savePosition(),
                        child: Text('$_readingError · 重试'),
                      ),
                  ],
                ),
              ),
            Expanded(child: ContentTransition(child: _buildBody())),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    final detail = _detail;
    final preferences = ref.watch(userPreferencesProvider);
    final pending = ref
        .watch(communitySubmissionsProvider(_service))
        .forScope(_topicKey)
        .where(
          (entry) =>
              entry.status != CommunitySubmissionStatus.sent ||
              !(detail?.posts.any(
                    (post) =>
                        _usernameFromUserUrl(post.userUrl)?.toLowerCase() ==
                            _service.currentUsername?.toLowerCase() &&
                        (post.rawBody.isEmpty ? post.body : post.rawBody)
                                .replaceAll('\r\n', '\n')
                                .trim() ==
                            entry.content.replaceAll('\r\n', '\n').trim() &&
                        post.createdAt != null &&
                        !post.createdAt!.isBefore(
                          entry.attemptedAt.subtract(
                            const Duration(seconds: 1),
                          ),
                        ),
                  ) ??
                  false),
        )
        .toList();
    if (_loading && detail == null) {
      return Column(
        children: [
          LoadingStatus(
            active: true,
            operation: _requestId,
            message: '正在加载讨论',
            onRetry: () => _load(refresh: true),
          ),
          const ContentSkeleton(),
        ],
      );
    }
    if (_error != null && detail == null) {
      return CommunityErrorView(
        message: _error!,
        onRetry: () => _load(refresh: true),
        onWebsiteRecovery: _needsWebsiteRecovery ? _recoverWebsite : null,
      );
    }
    if (detail == null) return const SizedBox.shrink();
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final original =
        detail.posts.where((post) => post.isOriginal).firstOrNull ??
        detail.posts.firstOrNull;
    final author = original == null
        ? null
        : _usernameFromUserUrl(original.userUrl);
    final posts = detail.posts
        .where(
          (post) =>
              _filter == 'all' ||
              (_filter == 'op' &&
                  (post.isOriginal ||
                      (author != null &&
                          _usernameFromUserUrl(post.userUrl)?.toLowerCase() ==
                              author.toLowerCase()))) ||
              (_filter == 'friends' && _isFriendPost(post)),
        )
        .toList();
    return RefreshIndicator(
      onRefresh: () => _load(refresh: true),
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is ScrollStartNotification &&
              notification.dragDetails != null) {
            _trackReading = true;
          }
          if (notification is ScrollEndNotification) _recordVisiblePost();
          return false;
        },
        child: ScrollablePositionedList.builder(
          key: ValueKey('topic-reading-$_readingAccount-$_filter'),
          itemScrollController: _itemScroll,
          itemPositionsListener: _positions,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(wide ? 80 : 14, 16, wide ? 80 : 14, 96),
          itemCount: posts.length + 1 + pending.length,
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
                            ?.copyWith(
                              fontWeight: FontWeight.w700,
                              fontSize:
                                  widget.topic.kind == CommunityTopicKind.group
                                  ? 20
                                  : null,
                            ),
                      ),
                      if (detail.sourceTitle.isNotEmpty) ...[
                        const SizedBox(height: 7),
                        Text(
                          detail.sourceTitle,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                color:
                                    widget.topic.kind ==
                                        CommunityTopicKind.group
                                    ? SocialChatStyle.accent(context)
                                    : Theme.of(context).colorScheme.primary,
                              ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      if (posts.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(28),
                          child: Center(child: Text('暂无符合条件的内容')),
                        ),
                    ],
                  ),
                ),
              );
            }
            if (index > posts.length) {
              return CommunitySubmissionCard(
                entry: pending[index - posts.length - 1],
                onInspect: () {
                  final entry = pending[index - posts.length - 1];
                  final target = entry.draftKey == null
                      ? 'topic'
                      : (jsonDecode(entry.draftKey!) as List).last;
                  if (target == 'topic') {
                    unawaited(_reply());
                    return;
                  }
                  final original = detail.posts
                      .where((row) => row.id == target)
                      .firstOrNull;
                  if (original != null) {
                    unawaited(_reply(post: original));
                  } else {
                    unawaited(_openWeb());
                  }
                },
              );
            }
            final post = posts[index - 1];
            final username = _usernameFromUserUrl(post.userUrl);
            final supportsReactions = widget.topic.kind.supportsReactions;
            final canManage =
                _service.canManagePost(widget.topic, post) &&
                !_mutationBusyPostIds.contains(post.id);
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 920),
                child: BlockedCommunityContent(
                  key: ValueKey('topic-post-${post.id}'),
                  username: username ?? post.author,
                  blocked: preferences.isBlocked(username ?? ''),
                  child: CommunityPostCard(
                    post: post,
                    discussionStyle:
                        widget.topic.kind == CommunityTopicKind.group,
                    onEdit: canManage ? () => _editPost(post) : null,
                    onDelete: canManage && !post.isOriginal
                        ? () => _deletePost(post)
                        : null,
                    onDeleteTopicOnWeb: canManage && post.isOriginal
                        ? _openWeb
                        : null,
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
      ),
    );
  }
}
