import '../state/service_providers.dart';
import '../navigation/app_destination.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/layout/app_layout.dart';
import '../core/network/bangumi_support.dart';
import '../core/network/netaba_api.dart';
import '../core/network/moegirl_service.dart';
import '../models/bangumi_models.dart';
import '../models/episode_edit.dart';
import '../features/subject_detail/application/subject_episode_loader.dart';
import '../features/subject_detail/application/subject_supplement_controller.dart';
import '../features/subject_detail/application/subject_friends_controller.dart';
import '../features/subject_detail/application/subject_comments_controller.dart';
import '../features/subject_detail/presentation/subject_detail_header.dart';
import '../features/subject_detail/presentation/subject_moegirl_panel.dart';
import '../features/subject_detail/presentation/subject_rating_panel.dart';
import '../features/subject_detail/presentation/subject_friends_panel.dart';
import '../features/subject_detail/presentation/subject_episode_grid.dart';
import '../features/subject_detail/presentation/subject_expandable_content.dart';
import '../features/subject_detail/presentation/subject_meta_sections.dart';

import '../widgets/episode_undo_message.dart';
import '../widgets/community_composer.dart';
import '../widgets/offline_status_banner.dart';
import '../state/session_controller.dart';
import '../widgets/collection_editor_sheet.dart';
import '../widgets/episode_grid_sheet.dart';
import '../widgets/mobile_subject_actions.dart';
import '../widgets/score_history_chart.dart';
import '../widgets/subject_widgets.dart';
import 'moegirl_detail_screen.dart';

class SubjectDetailScreen extends ConsumerStatefulWidget {
  const SubjectDetailScreen({super.key, required this.subject});

  final Subject subject;

  @override
  ConsumerState<SubjectDetailScreen> createState() =>
      _SubjectDetailScreenState();
}

class _SubjectDetailScreenState extends ConsumerState<SubjectDetailScreen> {
  late final _community = communityServiceFor(context);
  Future<void> _createDiscussion() async {
    final service = communityServiceFor(context);
    final account = service.currentUsername;
    if (!service.isAuthenticated) return;
    final sent = await showCommunityComposer(
      context,
      heading: '发表条目讨论',
      requireTitle: true,
      draftKey: communityDraftKey(account, [
        'subject',
        widget.subject.id,
        'new-topic',
      ]),
      isAccountCurrent: () =>
          service.isAuthenticated && service.currentUsername == account,
      onSubmit: (title, content, token) => service.createSubjectTopic(
        subjectId: widget.subject.id,
        title: title,
        content: content,
        turnstileToken: token,
      ),
    );
    if (sent && mounted && account == service.currentUsername) {
      await _content.topics.load();
    }
  }

  List<Episode> _episodes = const [];
  Map<int, int> _episodeTypes = const {};
  bool _loadingEpisodes = false;
  String? _episodesError;
  bool _episodesFromCache = false;
  DateTime? _episodesCachedAt;
  bool _friendsExpanded = false;
  late final SubjectSupplementController _content;
  late final SubjectCommentsController _comments;
  late final SubjectFriendsController _friends;
  (int?, String?, int?)? _accountKey;
  int? _episodeTypeFilter; // null = all, 0 = main
  final Set<int> _updatingEpisodes = {};
  late final SessionController _sessionController;
  late final SubjectEpisodeLoader _episodeLoader;

  @override
  void initState() {
    super.initState();
    _sessionController = ref.read(sessionProvider.notifier);
    _content = SubjectSupplementController(
      subject: widget.subject,
      api: () => ref.read(bangumiApiProvider),
      loadHistory: (id) => ref.read(netabaApiProvider).getSubjectHistory(id),
      loadTopics: _community.loadTopicsForSubject,
      findMoegirl: MoegirlService.shared.findForSubject,
    );
    _comments = SubjectCommentsController(
      subjectId: widget.subject.id,
      api: () => ref.read(bangumiApiProvider),
    );
    _friends = SubjectFriendsController(
      subjectId: widget.subject.id,
      api: () => ref.read(bangumiApiProvider),
      readAccount: () => _sessionController.batchAccount,
      loadFriends: (username) async =>
          (await _community.loadFriends(username, limit: 20)).data,
    );
    _content.addListener(_onSectionsChanged);
    _comments.addListener(_onSectionsChanged);
    _friends.addListener(_onSectionsChanged);
    _accountKey = _currentAccountKey();

    _episodeLoader = SubjectEpisodeLoader(
      subject: widget.subject,
      api: ref.read(bangumiApiProvider),
      collections: _sessionController,
      onProgress: (progress) {
        if (!mounted) return;
        setState(() {
          _episodes = progress.episodes ?? _episodes;
          _episodeTypes = progress.types ?? _episodeTypes;
          _loadingEpisodes = progress.loading ?? _loadingEpisodes;
          if (progress.fromCache != null) {
            _episodesFromCache = progress.fromCache!;
            _episodesCachedAt = progress.cachedAt;
          }
          _episodesError = progress.clearError
              ? null
              : progress.error ?? _episodesError;
        });
      },
    );
    ref.listenManual(sessionProvider, (_, _) {
      final account = _currentAccountKey();
      if (!mounted || account == _accountKey) return;
      _accountKey = account;
      setState(() {
        _episodeTypes = const {};
        _episodesFromCache = false;
        _episodesCachedAt = null;
        _updatingEpisodes.clear();
      });
      unawaited(_load());
    });
    ref.listenManual(sessionProvider.select((state) => state.lastEpisodeEdit), (
      _,
      change,
    ) {
      if (!mounted || change == null || change.subjectId != widget.subject.id) {
        return;
      }
      setState(
        () => _episodeTypes = {..._episodeTypes, change.episodeId: change.type},
      );
    });
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _content.dispose();
    _comments.dispose();
    _friends.dispose();
    _episodeLoader.dispose();
    super.dispose();
  }

  (int?, String?, int?) _currentAccountKey() {
    final account = _sessionController.batchAccount;
    return (account?.userId, account?.username, account?.generation);
  }

  void _onSectionsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _friendsExpanded = false);
    _friends.reset();
    unawaited(_comments.load());
    await Future.wait([_content.load(), _episodeLoader.load()]);
  }

  Future<void> _loadFriendStatuses() async {
    setState(() => _friendsExpanded = true);
    await _friends.load();
  }

  void _openMoegirlSearch(Subject subject) {
    final uri = Uri.https('zh.moegirl.org.cn', '/Special:Search', {
      'search': subject.displayName,
    });
    unawaited(launchUrl(uri, mode: LaunchMode.externalApplication));
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final subject = widget.subject.merge(_content.details.value);
    final collection = session.collectionFor(subject.id);
    final busy = session.updatingSubjects.contains(subject.id);
    final watchedCount = _episodeTypes.values.where((type) => type == 2).length;
    final narrow = AppLayout.isPhone(context);
    final pagePadding = AppLayout.pageInsets(context, top: 12, bottom: 40);
    final sectionGap = AppLayout.sectionGap(context);
    final blockGap = AppLayout.blockGap(context);
    final topicPreview = narrow ? 5 : 12;

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: '在 Bangumi 打开',
            onPressed: () => launchUrl(
              Uri.parse('https://bgm.tv/subject/${subject.id}'),
              mode: LaunchMode.externalApplication,
            ),
            icon: const Icon(Icons.open_in_new_rounded),
          ),
          const SizedBox(width: 6),
        ],
      ),
      bottomNavigationBar: narrow
          ? MobileSubjectActions(
              key: const ValueKey('subject-mobile-actions'),
              busy: busy,
              collectionLabel: collection?.type.labelFor(subject.type) ?? '收藏',
              onCollection: () => _chooseCollection(subject),
              onComment: () => showCollectionEditorSheet(
                context,
                subject: subject,
                collection: collection,
                focusComment: true,
              ),
              onProgress: subject.type.hasEpisodes || subject.type.hasVolumes
                  ? () => _openProgress(subject)
                  : null,
            )
          : null,
      body: SingleChildScrollView(
        padding: pagePadding,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1020),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SubjectDetailHeader(
                  showActions: !narrow,
                  subject: subject,
                  collection: collection,
                  busy: busy,
                  onCollectionChanged: (type) =>
                      _changeCollection(subject, type),
                  onManageCollection: () => unawaited(
                    showCollectionEditorSheet(
                      context,
                      subject: subject,
                      collection: collection,
                    ),
                  ),
                  onTagTap: (tag) => openDiscoverTagSearch(
                    context,
                    tag: tag,
                    subjectType: subject.type,
                  ),
                ),
                if (subject.score > 0 || subject.ratingTotal > 0) ...[
                  SizedBox(height: sectionGap),
                  SubjectRatingPanel(subject: subject),
                ],
                SizedBox(height: sectionGap),
                ScoreHistoryPanel(
                  loading: _content.history.loading,
                  error: _content.history.error,
                  history: _content.history.value,
                  subjectId: subject.id,
                  compact: narrow,
                  initiallyExpanded: !narrow,
                  onRetry: () => unawaited(_content.history.load()),
                ),
                SizedBox(height: sectionGap),
                SubjectFriendsPanel(
                  onOpenUser: (user) =>
                      openUserProfileFromBangumi(context, user),
                  loading: _friends.loading,
                  expanded: _friendsExpanded,
                  loaded: _friends.loaded,
                  statuses: _friends.items,
                  subjectType: subject.type,
                  error: _friends.error,
                  onExpand: () {
                    if (_friends.loaded && _friends.error == null) {
                      setState(() => _friendsExpanded = true);
                    } else {
                      unawaited(_loadFriendStatuses());
                    }
                  },
                  onCollapse: () => setState(() => _friendsExpanded = false),
                ),
                if (subject.summary.isNotEmpty) ...[
                  SizedBox(height: blockGap),
                  Text('简介', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 10),
                  SubjectExpandableText(
                    text: subject.summary,
                    style: Theme.of(context).textTheme.bodyLarge,
                    collapsedLines: narrow ? 5 : 10,
                  ),
                ],
                SizedBox(height: blockGap),
                SubjectMoegirlPanel(
                  entry: _content.moegirl.value,
                  loading: _content.moegirl.loading,
                  attempted: _content.moegirl.attempted,
                  error: _content.moegirl.error,
                  onLoad: () => _content.loadMoegirl(),
                  onSearch: () => _openMoegirlSearch(subject),
                  onOpen: _content.moegirl.value == null
                      ? null
                      : () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => MoegirlDetailScreen(
                              entry: _content.moegirl.value!,
                            ),
                          ),
                        ),
                ),
                if (subject.type.hasEpisodes) ...[
                  SizedBox(height: blockGap),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '章节',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      Text(
                        collection == null
                            ? '${_visibleEpisodes.length} 话'
                            : '已看 $watchedCount / ${_visibleEpisodes.length}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  if (_episodesFromCache)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '已显示本地章节${_episodesCachedAt == null ? '' : ' · ${snapshotDateLabel(_episodesCachedAt!)}'}'
                        '${_episodesError == null ? '' : ' · 暂未获取最新内容'}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        ChoiceChip(
                          label: const Text('全部'),
                          selected: _episodeTypeFilter == null,
                          onSelected: (_) =>
                              setState(() => _episodeTypeFilter = null),
                        ),
                        const SizedBox(width: 8),
                        for (final type in _availableEpisodeTypes) ...[
                          ChoiceChip(
                            label: Text(BangumiSupport.episodeTypeLabel(type)),
                            selected: _episodeTypeFilter == type,
                            onSelected: (_) =>
                                setState(() => _episodeTypeFilter = type),
                          ),
                          const SizedBox(width: 8),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (_episodes.isEmpty && _loadingEpisodes)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else if (_episodes.isEmpty && _episodesError != null)
                    Center(
                      child: TextButton.icon(
                        onPressed: () => unawaited(_episodeLoader.load()),
                        icon: const Icon(Icons.refresh_rounded),
                        label: Text(_episodesError!),
                      ),
                    )
                  else if (_visibleEpisodes.isEmpty)
                    const EmptyState(
                      icon: Icons.format_list_numbered_rounded,
                      title: '暂无章节数据',
                      message: '这个条目还没有可用的章节信息。',
                    )
                  else
                    SubjectEpisodeGrid(
                      episodes: _visibleEpisodes,
                      episodeTypes: _episodeTypes,
                      updatingEpisodes: _updatingEpisodes,
                      enabled: collection != null && !busy,
                      onTap: (episode, watched) => _setEpisode(
                        subject.id,
                        episode,
                        watched ? 0 : 2,
                        hasCollection: collection != null,
                      ),
                    ),
                ],
                SizedBox(height: blockGap),
                SubjectMetaSection(
                  title: '角色',
                  loading: _content.metadata.loading,
                  empty: _content.metadata.value.characters.isEmpty,
                  error:
                      (_content.metadata.error ??
                      _content.metadata.value.warning),
                  onRetry: () => _content.metadata.load(),
                  trailing: SubjectMetaCount(
                    '${_content.metadata.value.characters.length} 个角色',
                  ),
                  child: SubjectCharacterRail(
                    characters: _content.metadata.value.characters,
                    onOpen: (character) => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => CharacterRoute(
                          characterId: character.id,
                          seedName: character.displayName,
                          seedImageUrl: character.imageUrl,
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: sectionGap),
                SubjectMetaSection(
                  title: '制作人员',
                  loading: _content.metadata.loading,
                  empty: _content.metadata.value.persons.isEmpty,
                  error:
                      (_content.metadata.error ??
                      _content.metadata.value.warning),
                  onRetry: () => _content.metadata.load(),
                  trailing: SubjectMetaCount(
                    '${_content.metadata.value.persons.length} 条职员记录',
                  ),
                  child: SubjectStaffRoleGroups(
                    people: _content.metadata.value.persons,
                    onOpen: (person) => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => PersonRoute(
                          personId: person.id,
                          seedName: person.displayName,
                          seedImageUrl: person.imageUrl,
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: sectionGap),
                SubjectMetaSection(
                  title: '关联条目',
                  loading: _content.metadata.loading,
                  empty: _content.metadata.value.related.isEmpty,
                  error:
                      (_content.metadata.error ??
                      _content.metadata.value.warning),
                  onRetry: () => _content.metadata.load(),
                  trailing: SubjectMetaCount(
                    '${_content.metadata.value.related.length} 个条目',
                  ),
                  child: SubjectRelatedRail(
                    subjects: _content.metadata.value.related,
                    onOpen: (item) => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            SubjectDetailScreen(subject: item.toSubject()),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: sectionGap),
                SubjectMetaSection(
                  title: '讨论',
                  loading: _content.topics.loading,
                  empty: _content.topics.value.isEmpty,
                  error: _content.topics.error,
                  onRetry: () => _content.topics.load(),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_community.isAuthenticated)
                        TextButton(
                          onPressed: _createDiscussion,
                          child: const Text('发讨论'),
                        ),
                      TextButton(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () => launchUrl(
                          Uri.parse(
                            'https://bgm.tv/subject/${subject.id}/board',
                          ),
                          mode: LaunchMode.externalApplication,
                        ),
                        child: const Text('官网'),
                      ),
                    ],
                  ),
                  child: SubjectExpandableItemList(
                    itemCount: _content.topics.value.length,
                    previewCount: topicPreview,
                    itemBuilder: (index) {
                      final topic = _content.topics.value[index];
                      return ListTile(
                        dense: narrow,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          topic.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          [
                            if (topic.author.isNotEmpty) topic.author,
                            if (topic.replyCount > 0) '${topic.replyCount} 回复',
                          ].join(' · '),
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => TopicRoute(topic: topic),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                SizedBox(height: sectionGap),
                SubjectMetaSection(
                  title: '吐槽',
                  loading: _comments.loading,
                  empty: _comments.items.isEmpty,
                  error: _comments.error,
                  onRetry: () => _comments.load(),
                  trailing: TextButton(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () => launchUrl(
                      Uri.parse(
                        'https://bgm.tv/subject/${subject.id}/comments',
                      ),
                      mode: LaunchMode.externalApplication,
                    ),
                    child: const Text('官网'),
                  ),
                  child: Column(
                    children: [
                      for (final c in _comments.items)
                        ListTile(
                          dense: narrow,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            c.userName.isEmpty ? '用户' : c.userName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            c.comment,
                            maxLines: narrow ? 4 : 8,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: c.rate > 0
                              ? Text(
                                  '${c.rate}',
                                  style: const TextStyle(
                                    color: Color(0xFFF3A646),
                                    fontWeight: FontWeight.w800,
                                  ),
                                )
                              : null,
                          onTap: c.profileUsername.isEmpty
                              ? null
                              : () => openUserProfile(
                                  context,
                                  username: c.profileUsername,
                                  nickname: c.userName,
                                  avatarUrl: c.avatarUrl,
                                ),
                        ),
                      if (_comments.hasMore && _comments.items.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: TextButton(
                            onPressed: _comments.loadingMore
                                ? null
                                : () => _comments.load(append: true),
                            child: Text(
                              _comments.loadingMore ? '加载中…' : '加载更多吐槽',
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Episode> get _visibleEpisodes =>
      BangumiSupport.filterEpisodesByType(_episodes, _episodeTypeFilter);

  List<int> get _availableEpisodeTypes {
    final set = <int>{};
    for (final ep in _episodes) {
      set.add(ep.type);
    }
    final list = set.toList()..sort();
    return list;
  }

  Future<void> _chooseCollection(Subject subject) async {
    final controller = ref.read(sessionProvider.notifier);
    final account = controller.batchAccount;
    final selected = ref.read(sessionProvider).collectionFor(subject.id)?.type;
    final type = await showModalBottomSheet<CollectionType>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final type in CollectionType.values)
              ListTile(
                title: Text(type.labelFor(subject.type)),
                trailing: selected == type
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.pop(context, type),
              ),
          ],
        ),
      ),
    );
    if (!mounted || type == null) return;
    if (account == null || !controller.isCurrentBatchAccount(account)) {
      showAppMessage(context, '登录状态已变化，请重新操作');
      return;
    }
    await _changeCollection(subject, type);
  }

  Future<void> _openProgress(Subject subject) async {
    final collection = ref.read(sessionProvider).collectionFor(subject.id);
    if (collection == null) {
      showAppMessage(context, '请先选择收藏状态，再记录进度');
      await _chooseCollection(subject);
      return;
    }
    if (subject.type.hasEpisodes) {
      await showEpisodeGridSheet(context, ref, collection);
    } else {
      await showCollectionEditorSheet(
        context,
        subject: subject,
        collection: collection,
      );
    }
  }

  Future<void> _changeCollection(Subject subject, CollectionType type) async {
    final hadCollection =
        ref.read(sessionProvider).collectionFor(subject.id) != null;
    final error = await ref
        .read(sessionProvider.notifier)
        .changeCollection(subject, type);
    if (!mounted) return;
    final successText = type == CollectionType.done && subject.type.hasEpisodes
        ? '已更新为“${type.labelFor(subject.type)}”，并自动补全章节进度'
        : '已更新为“${type.labelFor(subject.type)}”';
    final pending = ref.read(sessionProvider).pendingSyncCount;
    showAppMessage(
      context,
      error ?? (pending > 0 ? '$successText；已保存在本机，联网后自动同步' : successText),
    );
    if (error == null &&
        subject.type.hasEpisodes &&
        (!hadCollection || type == CollectionType.done)) {
      await _reloadEpisodeWatchState(subject.id);
    }
  }

  Future<void> _reloadEpisodeWatchState(int subjectId) =>
      _episodeLoader.load(silent: true);

  Future<void> _setEpisode(
    int subjectId,
    Episode episode,
    int type, {
    required bool hasCollection,
  }) async {
    if (!hasCollection) {
      showAppMessage(context, '请先把条目加入收藏');
      return;
    }
    if (_updatingEpisodes.contains(episode.id)) return;
    final account = ref.read(sessionProvider).user?.id;
    final previousType = _episodeTypes[episode.id] ?? 0;
    setState(() {
      _updatingEpisodes.add(episode.id);
      _episodeTypes = {..._episodeTypes, episode.id: type};
    });
    EpisodeUndo? undo;
    final error = await _sessionController.setEpisode(
      subjectId: subjectId,
      episodeId: episode.id,
      type: type,
      previousType: previousType,
      episode: episode,
      onUndoReady: (value) => undo = value,
      trackGlobalBusy: false,
    );
    if (!mounted || ref.read(sessionProvider).user?.id != account) return;
    setState(() {
      _updatingEpisodes.remove(episode.id);
      if (error != null) {
        _episodeTypes = {..._episodeTypes, episode.id: previousType};
      }
    });
    if (error != null) {
      showAppMessage(context, error);
    } else if (undo != null) {
      showEpisodeUndoMessage(context, _sessionController, undo!);
    }
  }
}
