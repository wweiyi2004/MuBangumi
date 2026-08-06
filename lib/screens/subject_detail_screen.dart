import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/layout/app_layout.dart';
import '../core/network/bangumi_endpoints.dart';
import '../core/network/bangumi_support.dart';
import '../core/network/community_service.dart';
import '../core/network/netaba_api.dart';
import '../models/bangumi_models.dart';
import '../models/community_models.dart';
import '../models/netaba_models.dart';
import '../state/session_controller.dart';
import '../widgets/collection_editor_sheet.dart';
import '../widgets/score_history_chart.dart';
import '../widgets/subject_widgets.dart';
import 'character_detail_screen.dart';
import 'community_topic_screen.dart';
import 'discover_page.dart';
import 'person_detail_screen.dart';
import 'user_profile_page.dart';

class SubjectDetailScreen extends ConsumerStatefulWidget {
  const SubjectDetailScreen({super.key, required this.subject});

  final Subject subject;

  @override
  ConsumerState<SubjectDetailScreen> createState() =>
      _SubjectDetailScreenState();
}

class _SubjectDetailScreenState extends ConsumerState<SubjectDetailScreen> {
  Subject? _details;
  List<Episode> _episodes = const [];
  Map<int, int> _episodeTypes = const {};
  List<FriendSubjectStatus> _friendStatuses = const [];
  List<SubjectCharacter> _characters = const [];
  List<SubjectPerson> _persons = const [];
  List<RelatedSubject> _related = const [];
  List<SubjectComment> _comments = const [];
  List<CommunityTopic> _topics = const [];
  int _commentsPage = 1;
  bool _commentsHasMore = true;
  bool _loadingFriends = false;
  bool _friendsExpanded = false;
  bool _friendsLoaded = false;
  bool _loadingMeta = false;
  bool _loadingComments = false;
  bool _loadingMoreComments = false;
  bool _loadingTopics = false;
  bool _loadingHistory = false;
  NetabaSubjectHistory? _scoreHistory;
  String? _historyError;
  int? _episodeTypeFilter; // null = all, 0 = main
  final Set<int> _updatingEpisodes = {};
  late final SessionController _sessionController;
  bool _episodesChanged = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _sessionController = ref.read(sessionProvider.notifier);
    Future.microtask(_load);
  }

  @override
  void dispose() {
    if (_episodesChanged) {
      unawaited(_sessionController.refresh(showIndicator: false));
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(bangumiApiProvider);
      final hasCollection =
          ref.read(sessionProvider).collectionFor(widget.subject.id) != null;
      final details = await api.getSubject(widget.subject.id);
      List<Episode> episodes = const [];
      Map<int, int> episodeTypes = {};
      if (details.type.hasEpisodes || widget.subject.type.hasEpisodes) {
        if (hasCollection) {
          // Explicit null = all types for SP/OP/ED filter UI.
          final episodeCollections = await api.getEpisodeCollections(
            widget.subject.id,
            episodeType: null,
          );
          episodes = [for (final item in episodeCollections) item.episode];
          episodeTypes = {
            for (final item in episodeCollections) item.episode.id: item.type,
          };
        } else {
          // Explicit null = all types for SP/OP/ED filter UI.
          episodes = await api.getEpisodes(
            widget.subject.id,
            episodeType: null,
          );
        }
      }
      if (!mounted) return;
      setState(() {
        _details = details;
        _episodes = episodes;
        _episodeTypes = episodeTypes;
        _loading = false;
        _friendsExpanded = false;
        _friendsLoaded = false;
        _friendStatuses = const [];
      });
      unawaited(_loadMeta(widget.subject.id));
      unawaited(_loadComments(widget.subject.id));
      unawaited(_loadTopics(widget.subject.id));
      unawaited(_loadScoreHistory(widget.subject.id));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _loadScoreHistory(int subjectId) async {
    setState(() {
      _loadingHistory = true;
      _historyError = null;
    });
    try {
      final history =
          await ref.read(netabaApiProvider).getSubjectHistory(subjectId);
      if (!mounted) return;
      setState(() {
        _scoreHistory = history;
        _loadingHistory = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingHistory = false;
        _historyError = _netabaErrorMessage(error);
      });
    }
  }

  String _netabaErrorMessage(Object error) {
    if (error is NetabaApiException) return error.message;
    if (error is DioException) {
      final nested = error.error;
      if (nested is NetabaApiException) return nested.message;
    }
    final text = error.toString();
    final match = RegExp(r'NetabaApiException[:\s]*([^\n]+)').firstMatch(text);
    if (match != null) return match.group(1)!.trim();
    return '获取评分历史失败';
  }

  Future<void> _loadMeta(int subjectId) async {
    setState(() => _loadingMeta = true);
    try {
      final api = ref.read(bangumiApiProvider);
      final results = await Future.wait([
        api.getSubjectCharacters(subjectId),
        api.getSubjectPersons(subjectId),
        api.getRelatedSubjects(subjectId),
      ]);
      if (!mounted) return;
      setState(() {
        _characters = results[0] as List<SubjectCharacter>;
        _persons = results[1] as List<SubjectPerson>;
        _related = results[2] as List<RelatedSubject>;
        _loadingMeta = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMeta = false);
    }
  }

  Future<void> _loadTopics(int subjectId) async {
    setState(() => _loadingTopics = true);
    try {
      final topics = await CommunityService.shared.loadTopicsForSubject(
        subjectId,
      );
      if (!mounted) return;
      setState(() {
        _topics = topics;
        _loadingTopics = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingTopics = false);
    }
  }

  Future<void> _loadComments(int subjectId, {bool append = false}) async {
    if (append) {
      if (_loadingMoreComments || !_commentsHasMore) return;
      setState(() => _loadingMoreComments = true);
    } else {
      setState(() {
        _loadingComments = true;
        _commentsPage = 1;
        _commentsHasMore = true;
      });
    }
    final page = append ? _commentsPage + 1 : 1;
    try {
      final comments = await ref
          .read(bangumiApiProvider)
          .getSubjectComments(subjectId, page: page);
      if (!mounted) return;
      setState(() {
        if (append) {
          final seen = {for (final c in _comments) c.id};
          _comments = [
            ..._comments,
            for (final c in comments)
              if (c.id == 0 || seen.add(c.id)) c,
          ];
          _commentsPage = page;
          _loadingMoreComments = false;
        } else {
          _comments = comments;
          _commentsPage = 1;
          _loadingComments = false;
        }
        // HTML pages are typically ~20 items; short page => end.
        _commentsHasMore = comments.length >= 10;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingComments = false;
        _loadingMoreComments = false;
      });
    }
  }

  Future<void> _loadFriendStatuses(int subjectId) async {
    final me = ref.read(sessionProvider).user;
    if (me == null || _loadingFriends) return;
    setState(() {
      _friendsExpanded = true;
      _loadingFriends = true;
    });
    try {
      final friends = await CommunityService.shared.loadFriends(
        me.username,
        limit: 20,
      );
      final statuses = await ref
          .read(bangumiApiProvider)
          .getFriendsSubjectStatus(
            subjectId,
            friends: friends.data,
            limit: 12,
            concurrency: 3,
          );
      if (!mounted) return;
      setState(() {
        _friendStatuses = statuses;
        _loadingFriends = false;
        _friendsLoaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingFriends = false;
        _friendsLoaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final subject = _details == null
        ? widget.subject
        : widget.subject.merge(_details!);
    final collection = session.collectionFor(subject.id);
    final busy = session.updatingSubjects.contains(subject.id);
    final watchedCount = _episodeTypes.values.where((type) => type == 2).length;
    final narrow = AppLayout.isPhone(context);
    final pagePadding = AppLayout.pageInsets(context, top: 12, bottom: 40);
    final sectionGap = AppLayout.sectionGap(context);
    final blockGap = AppLayout.blockGap(context);
    final listPreview = narrow ? 6 : 24;
    final topicPreview = narrow ? 5 : 12;
    final relatedPreview = narrow ? 10 : 20;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          subject.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? EmptyState(
              icon: Icons.cloud_off_outlined,
              title: '详情加载失败',
              message: _error!,
              action: FilledButton.tonalIcon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('重试'),
              ),
            )
          : SingleChildScrollView(
              padding: pagePadding,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1020),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SubjectHeader(
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
                        _RatingPanel(subject: subject),
                      ],
                      SizedBox(height: sectionGap),
                      ScoreHistoryPanel(
                        loading: _loadingHistory,
                        error: _historyError,
                        history: _scoreHistory,
                        subjectId: subject.id,
                        compact: narrow,
                        initiallyExpanded: !narrow,
                        onRetry: () => unawaited(_loadScoreHistory(subject.id)),
                      ),
                      SizedBox(height: sectionGap),
                      _FriendsWatchingPanel(
                        loading: _loadingFriends,
                        expanded: _friendsExpanded,
                        loaded: _friendsLoaded,
                        statuses: _friendStatuses,
                        subjectType: subject.type,
                        onExpand: () => _loadFriendStatuses(subject.id),
                      ),
                      if (subject.summary.isNotEmpty) ...[
                        SizedBox(height: blockGap),
                        Text(
                          '简介',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 10),
                        _ExpandableText(
                          text: subject.summary,
                          style: Theme.of(context).textTheme.bodyLarge,
                          collapsedLines: narrow ? 5 : 10,
                        ),
                      ],
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
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
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
                                  label: Text(
                                    BangumiSupport.episodeTypeLabel(type),
                                  ),
                                  selected: _episodeTypeFilter == type,
                                  onSelected: (_) => setState(
                                    () => _episodeTypeFilter = type,
                                  ),
                                ),
                                const SizedBox(width: 8),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        if (_visibleEpisodes.isEmpty)
                          const EmptyState(
                            icon: Icons.format_list_numbered_rounded,
                            title: '暂无章节数据',
                            message: '这个条目还没有可用的章节信息。',
                          )
                        else
                          _EpisodeGrid(
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
                      _MetaSection(
                        title: '角色',
                        loading: _loadingMeta,
                        empty: _characters.isEmpty,
                        child: _ExpandableItemList(
                          itemCount: _characters.length,
                          previewCount: listPreview,
                          itemBuilder: (index) {
                            final c = _characters[index];
                            return ListTile(
                              dense: narrow,
                              visualDensity: narrow
                                  ? VisualDensity.compact
                                  : VisualDensity.standard,
                              contentPadding: EdgeInsets.zero,
                              leading: _MetaAvatar(url: c.imageUrl),
                              title: Text(
                                c.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                [
                                  if (c.relation.isNotEmpty) c.relation,
                                  if (c.actorNames.isNotEmpty)
                                    'CV: ${c.actorNames.join(' / ')}',
                                ].join(' · '),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: const Icon(
                                Icons.chevron_right_rounded,
                              ),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => CharacterDetailScreen(
                                    characterId: c.id,
                                    seedName: c.displayName,
                                    seedImageUrl: c.imageUrl,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      SizedBox(height: sectionGap),
                      _MetaSection(
                        title: '制作人员',
                        loading: _loadingMeta,
                        empty: _persons.isEmpty,
                        child: _ExpandableItemList(
                          itemCount: _persons.length,
                          previewCount: listPreview,
                          itemBuilder: (index) {
                            final p = _persons[index];
                            return ListTile(
                              dense: narrow,
                              visualDensity: narrow
                                  ? VisualDensity.compact
                                  : VisualDensity.standard,
                              contentPadding: EdgeInsets.zero,
                              leading: _MetaAvatar(url: p.imageUrl),
                              title: Text(
                                p.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                [
                                  if (p.relation.isNotEmpty) p.relation,
                                  if (p.career.isNotEmpty)
                                    p.career.join(' / '),
                                ].join(' · '),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: const Icon(
                                Icons.chevron_right_rounded,
                              ),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => PersonDetailScreen(
                                    personId: p.id,
                                    seedName: p.displayName,
                                    seedImageUrl: p.imageUrl,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      SizedBox(height: sectionGap),
                      _MetaSection(
                        title: '关联条目',
                        loading: _loadingMeta,
                        empty: _related.isEmpty,
                        child: _ExpandableChipWrap(
                          itemCount: _related.length,
                          previewCount: relatedPreview,
                          chipBuilder: (index) {
                            final item = _related[index];
                            return ActionChip(
                              avatar: item.imageUrl.isEmpty
                                  ? null
                                  : CircleAvatar(
                                      backgroundImage:
                                          CachedNetworkImageProvider(
                                        BangumiEndpoints.imageUrl(
                                          item.imageUrl,
                                        ),
                                      ),
                                    ),
                              label: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: narrow ? 180 : 260,
                                ),
                                child: Text(
                                  item.relation.isEmpty
                                      ? item.displayName
                                      : '${item.relation} · ${item.displayName}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => SubjectDetailScreen(
                                      subject: item.toSubject(),
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
                      SizedBox(height: sectionGap),
                      _MetaSection(
                        title: '讨论',
                        loading: _loadingTopics,
                        empty: _topics.isEmpty,
                        trailing: TextButton(
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
                        child: _ExpandableItemList(
                          itemCount: _topics.length,
                          previewCount: topicPreview,
                          itemBuilder: (index) {
                            final topic = _topics[index];
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
                                  if (topic.replyCount > 0)
                                    '${topic.replyCount} 回复',
                                ].join(' · '),
                              ),
                              trailing: const Icon(
                                Icons.chevron_right_rounded,
                              ),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      CommunityTopicScreen(topic: topic),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      SizedBox(height: sectionGap),
                      _MetaSection(
                        title: '吐槽',
                        loading: _loadingComments,
                        empty: _comments.isEmpty,
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
                            for (final c in _comments)
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
                            if (_commentsHasMore && _comments.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: TextButton(
                                  onPressed: _loadingMoreComments
                                      ? null
                                      : () => _loadComments(
                                          subject.id,
                                          append: true,
                                        ),
                                  child: Text(
                                    _loadingMoreComments ? '加载中…' : '加载更多吐槽',
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
    showAppMessage(context, error ?? successText);
    if (error == null &&
        subject.type.hasEpisodes &&
        (!hadCollection || type == CollectionType.done)) {
      await _reloadEpisodeWatchState(subject.id);
      _episodesChanged = true;
    }
  }

  Future<void> _reloadEpisodeWatchState(int subjectId) async {
    try {
      final episodeCollections = await ref
          .read(bangumiApiProvider)
          .getEpisodeCollections(subjectId, episodeType: null);
      if (!mounted) return;
      setState(() {
        _episodes = [
          for (final item in episodeCollections) item.episode,
        ];
        _episodeTypes = {
          for (final item in episodeCollections) item.episode.id: item.type,
        };
      });
    } catch (_) {
      // Keep the uncollected episode list if watch-state fetch fails.
    }
  }

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
    final previousType = _episodeTypes[episode.id] ?? 0;
    setState(() {
      _updatingEpisodes.add(episode.id);
      _episodeTypes = {..._episodeTypes, episode.id: type};
    });
    final error = await _sessionController.setEpisode(
      subjectId: subjectId,
      episodeId: episode.id,
      type: type,
      refreshCollection: false,
      trackGlobalBusy: false,
    );
    if (!mounted) return;
    setState(() {
      _updatingEpisodes.remove(episode.id);
      if (error != null) {
        _episodeTypes = {..._episodeTypes, episode.id: previousType};
      } else {
        _episodesChanged = true;
      }
    });
    if (error != null) {
      showAppMessage(context, error);
    }
  }
}

class _SubjectHeader extends StatelessWidget {
  const _SubjectHeader({
    required this.subject,
    required this.collection,
    required this.busy,
    required this.onCollectionChanged,
    required this.onManageCollection,
    this.onTagTap,
  });

  final Subject subject;
  final UserCollection? collection;
  final bool busy;
  final ValueChanged<CollectionType> onCollectionChanged;
  final VoidCallback onManageCollection;
  final ValueChanged<String>? onTagTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 620;
          final veryNarrow = constraints.maxWidth < 380;
          final padding = compact ? 14.0 : 20.0;
          final coverW = veryNarrow
              ? 96.0
              : compact
                  ? 112.0
                  : 170.0;
          final coverH = veryNarrow
              ? 136.0
              : compact
                  ? 158.0
                  : 240.0;
          final cover = SubjectCover(
            subject: subject,
            width: coverW,
            height: coverH,
            borderRadius: compact ? 14 : 18,
          );

          final titleStyle = compact
              ? Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  )
              : Theme.of(context).textTheme.headlineMedium;

          final titleBlock = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                subject.displayName,
                style: titleStyle,
                maxLines: compact ? 3 : 4,
                overflow: TextOverflow.ellipsis,
              ),
              if (subject.nameCn.isNotEmpty && subject.name.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  subject.name,
                  maxLines: compact ? 2 : 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: compact ? 13 : null,
                  ),
                ),
              ],
              SizedBox(height: compact ? 10 : 14),
              Wrap(
                spacing: compact ? 8 : 12,
                runSpacing: 6,
                children: [
                  _Meta(
                    icon: subjectTypeIcon(subject.type),
                    text: subject.type.label,
                    compact: compact,
                  ),
                  if (subject.score > 0)
                    _Meta(
                      icon: Icons.star_rounded,
                      text: subject.score.toStringAsFixed(2),
                      color: const Color(0xFFF3A646),
                      compact: compact,
                    ),
                  if (subject.rank > 0)
                    _Meta(
                      icon: Icons.emoji_events_outlined,
                      text: '#${subject.rank}',
                      compact: compact,
                    ),
                  if (!compact && subject.ratingTotal > 0)
                    _Meta(
                      icon: Icons.how_to_vote_outlined,
                      text: '${subject.ratingTotal} 人评分',
                    ),
                  if (subject.episodeCount > 0)
                    _Meta(
                      icon: Icons.play_circle_outline_rounded,
                      text: '${subject.episodeCount} 话',
                      compact: compact,
                    ),
                  if (subject.volumeCount > 0)
                    _Meta(
                      icon: Icons.menu_book_outlined,
                      text: '${subject.volumeCount} 卷',
                      compact: compact,
                    ),
                  if (subject.date.isNotEmpty)
                    _Meta(
                      icon: Icons.calendar_today_outlined,
                      text: subject.date,
                      compact: compact,
                    ),
                  if (!compact && subject.platform.isNotEmpty)
                    _Meta(
                      icon: Icons.tv_outlined,
                      text: subject.platform,
                    ),
                  if (subject.nsfw)
                    _Meta(
                      icon: Icons.warning_amber_rounded,
                      text: 'NSFW',
                      color: const Color(0xFFE95383),
                      compact: compact,
                    ),
                ],
              ),
            ],
          );

          final tags = subject.metaTags.isEmpty && subject.tags.isEmpty
              ? null
              : Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final tag in [
                      ...subject.metaTags,
                      ...subject.tags.where(
                        (t) => !subject.metaTags.contains(t),
                      ),
                    ].take(compact ? 8 : 10))
                      ActionChip(
                        label: Text(tag),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        onPressed: onTagTap == null
                            ? null
                            : () => onTagTap!(tag),
                      ),
                  ],
                );

          final officialSite = subject.officialSite.isEmpty
              ? null
              : Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onPressed: () {
                      final raw = subject.officialSite.trim();
                      final uri = Uri.tryParse(
                        raw.startsWith('http') ? raw : 'https://$raw',
                      );
                      if (uri != null) {
                        launchUrl(uri, mode: LaunchMode.externalApplication);
                      }
                    },
                    icon: const Icon(Icons.public_rounded, size: 18),
                    label: const Text('官方网站'),
                  ),
                );

          final myCollection = collection == null ||
                  (collection!.rate <= 0 &&
                      collection!.comment.isEmpty &&
                      collection!.tags.isEmpty)
              ? null
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        if (collection!.rate > 0)
                          Chip(
                            avatar: const Icon(Icons.star_rounded, size: 18),
                            label: Text('我的评分 ${collection!.rate}'),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                        if (collection!.private)
                          const Chip(
                            avatar: Icon(Icons.lock_outline_rounded, size: 16),
                            label: Text('仅自己可见'),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                        for (final tag in collection!.tags.take(compact ? 4 : 6))
                          ActionChip(
                            label: Text(tag),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            onPressed: onTagTap == null
                                ? null
                                : () => onTagTap!(tag),
                          ),
                      ],
                    ),
                    if (collection!.comment.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        collection!.comment,
                        maxLines: compact ? 3 : 6,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                );

          final collectButton = MenuAnchor(
            builder: (context, controller, child) => FilledButton.icon(
              onPressed: busy
                  ? null
                  : () => controller.isOpen
                      ? controller.close()
                      : controller.open(),
              icon: busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      collection == null
                          ? Icons.add_rounded
                          : Icons.bookmark_rounded,
                    ),
              label: Text(
                collection?.type.labelFor(subject.type) ?? '加入收藏',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            menuChildren: [
              for (final type in CollectionType.values)
                MenuItemButton(
                  leadingIcon: collection?.type == type
                      ? const Icon(Icons.check_rounded)
                      : null,
                  onPressed: () => onCollectionChanged(type),
                  child: Text(type.labelFor(subject.type)),
                ),
            ],
          );

          final manageButton = OutlinedButton.icon(
            onPressed: busy ? null : onManageCollection,
            icon: const Icon(Icons.edit_note_rounded),
            label: Text(compact ? '评分' : '评分与吐槽'),
          );

          final actions = compact
              ? Row(
                  children: [
                    Expanded(child: collectButton),
                    const SizedBox(width: 8),
                    Expanded(child: manageButton),
                  ],
                )
              : Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    SizedBox(width: 210, child: collectButton),
                    manageButton,
                  ],
                );

          if (compact) {
            return Padding(
              padding: EdgeInsets.all(padding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      cover,
                      SizedBox(width: veryNarrow ? 12 : 14),
                      Expanded(child: titleBlock),
                    ],
                  ),
                  if (tags != null) ...[
                    const SizedBox(height: 12),
                    tags,
                  ],
                  if (officialSite != null) ...[
                    const SizedBox(height: 4),
                    officialSite,
                  ],
                  if (myCollection != null) ...[
                    const SizedBox(height: 10),
                    myCollection,
                  ],
                  const SizedBox(height: 12),
                  actions,
                ],
              ),
            );
          }

          return Padding(
            padding: EdgeInsets.all(padding),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                cover,
                const SizedBox(width: 28),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      titleBlock,
                      if (tags != null) ...[
                        const SizedBox(height: 14),
                        tags,
                      ],
                      if (officialSite != null) ...[
                        const SizedBox(height: 4),
                        officialSite,
                      ],
                      if (myCollection != null) ...[
                        const SizedBox(height: 12),
                        myCollection,
                      ],
                      const SizedBox(height: 12),
                      actions,
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _RatingPanel extends StatelessWidget {
  const _RatingPanel({required this.subject});

  final Subject subject;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final narrow = MediaQuery.sizeOf(context).width < 600;
    final maxCount = subject.ratingCount.values.fold<int>(
      0,
      (max, value) => value > max ? value : max,
    );
    return Card(
      child: Padding(
        padding: EdgeInsets.all(narrow ? 12 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '评分详情',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Flexible(
                  child: Text(
                    '争议度 ${subject.controversyLabel}',
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: narrow ? 12.5 : null,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 14,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (subject.score > 0)
                  Text(
                    subject.score.toStringAsFixed(2),
                    style: (narrow
                            ? Theme.of(context).textTheme.headlineSmall
                            : Theme.of(context).textTheme.headlineMedium)
                        ?.copyWith(
                      color: const Color(0xFFF3A646),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                if (subject.ratingTotal > 0)
                  Text('${subject.ratingTotal} 人评分'),
                if (subject.ratingStdDev > 0)
                  Text('σ ${subject.ratingStdDev.toStringAsFixed(2)}'),
                if (subject.rank > 0) Text('排名 #${subject.rank}'),
              ],
            ),
            if (maxCount > 0) ...[
              const SizedBox(height: 14),
              for (var score = 10; score >= 1; score--)
                Padding(
                  padding: EdgeInsets.only(bottom: narrow ? 4 : 5),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 20,
                        child: Text(
                          '$score',
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: (subject.ratingCount[score] ?? 0) / maxCount,
                            minHeight: narrow ? 7 : 8,
                            backgroundColor: scheme.surfaceContainerHighest,
                            color: const Color(0xFFF3A646),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: narrow ? 36 : 42,
                        child: Text(
                          '${subject.ratingCount[score] ?? 0}',
                          textAlign: TextAlign.end,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            if (subject.collectionTotal > 0 ||
                subject.wishCount +
                        subject.collectCount +
                        subject.doingCount >
                    0) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (subject.wishCount > 0)
                    Chip(
                      label: Text(
                        '${CollectionType.wish.labelFor(subject.type)} ${subject.wishCount}',
                      ),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  if (subject.doingCount > 0)
                    Chip(
                      label: Text(
                        '${CollectionType.doing.labelFor(subject.type)} ${subject.doingCount}',
                      ),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  if (subject.collectCount > 0)
                    Chip(
                      label: Text(
                        '${CollectionType.done.labelFor(subject.type)} ${subject.collectCount}',
                      ),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  if (subject.onHoldCount > 0)
                    Chip(
                      label: Text('搁置 ${subject.onHoldCount}'),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  if (subject.droppedCount > 0)
                    Chip(
                      label: Text('抛弃 ${subject.droppedCount}'),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FriendsWatchingPanel extends StatelessWidget {
  const _FriendsWatchingPanel({
    required this.loading,
    required this.expanded,
    required this.loaded,
    required this.statuses,
    required this.subjectType,
    required this.onExpand,
  });

  final bool loading;
  final bool expanded;
  final bool loaded;
  final List<FriendSubjectStatus> statuses;
  final SubjectType subjectType;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '好友看？',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                if (loading)
                  const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (!expanded)
                  TextButton.icon(
                    onPressed: onExpand,
                    icon: const Icon(Icons.people_outline_rounded, size: 18),
                    label: const Text('查看好友'),
                  )
                else
                  Text(
                    statuses.isEmpty ? '暂无好友收藏' : '${statuses.length} 位好友',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            if (!expanded && !loading)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '按需查询，避免打开条目时卡顿',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (loaded && statuses.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final status in statuses.take(12))
                    ActionChip(
                      avatar: CircleAvatar(
                        backgroundImage: status.user.avatarUrl.isEmpty
                            ? null
                            : CachedNetworkImageProvider(
                                BangumiEndpoints.imageUrl(
                                  status.user.avatarUrl,
                                ),
                              ),
                        child: status.user.avatarUrl.isEmpty
                            ? Text(
                                status.user.displayName.characters.first
                                    .toUpperCase(),
                              )
                            : null,
                      ),
                      label: Text(
                        '${status.user.displayName} · ${status.type.labelFor(subjectType)}'
                        '${status.rate > 0 ? ' ${status.rate}' : ''}',
                      ),
                      onPressed: () =>
                          openUserProfileFromBangumi(context, status.user),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({
    required this.icon,
    required this.text,
    this.color,
    this.compact = false,
  });

  final IconData icon;
  final String text;
  final Color? color;
  final bool compact;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        icon,
        size: compact ? 16 : 18,
        color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      SizedBox(width: compact ? 3 : 4),
      Text(
        text,
        style: TextStyle(fontSize: compact ? 12.5 : null),
      ),
    ],
  );
}

class _EpisodeGrid extends StatelessWidget {
  const _EpisodeGrid({
    required this.episodes,
    required this.episodeTypes,
    required this.updatingEpisodes,
    required this.enabled,
    required this.onTap,
  });

  final List<Episode> episodes;
  final Map<int, int> episodeTypes;
  final Set<int> updatingEpisodes;
  final bool enabled;
  final void Function(Episode episode, bool watched) onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        // Prefer ~5–7 cells per row on phones, keep ≥44 touch height.
        final target = width < 420
            ? 5.0
            : width < 600
                ? 6.0
                : 8.0;
        final spacing = width < 420 ? 7.0 : 9.0;
        final cellW = ((width - spacing * (target - 1)) / target)
            .clamp(48.0, 64.0);
        final cellH = width < 420 ? 42.0 : 44.0;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final episode in episodes)
              Tooltip(
                message: episode.displayName,
                child: SizedBox(
                  width: cellW,
                  height: cellH,
                  child: episodeTypes[episode.id] == 2
                      ? FilledButton(
                          onPressed: enabled &&
                                  !updatingEpisodes.contains(episode.id)
                              ? () => onTap(episode, true)
                              : null,
                          style: FilledButton.styleFrom(
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                            textStyle: TextStyle(
                              fontSize: width < 380 ? 13 : 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          child: Text(_episodeNumber(episode.number)),
                        )
                      : OutlinedButton(
                          onPressed: enabled &&
                                  !updatingEpisodes.contains(episode.id)
                              ? () => onTap(episode, false)
                              : null,
                          style: OutlinedButton.styleFrom(
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                            textStyle: TextStyle(
                              fontSize: width < 380 ? 13 : 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          child: Text(_episodeNumber(episode.number)),
                        ),
                ),
              ),
          ],
        );
      },
    );
  }

  String _episodeNumber(double value) =>
      value % 1 == 0 ? value.toInt().toString() : value.toStringAsFixed(1);
}

class _ExpandableText extends StatefulWidget {
  const _ExpandableText({
    required this.text,
    this.style,
    this.collapsedLines = 5,
  });

  final String text;
  final TextStyle? style;
  final int collapsedLines;

  @override
  State<_ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<_ExpandableText> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          maxLines: widget.collapsedLines,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: constraints.maxWidth);
        final overflow = painter.didExceedMaxLines;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.text,
              style: widget.style,
              maxLines: _expanded ? null : widget.collapsedLines,
              overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
            ),
            if (overflow)
              TextButton(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  foregroundColor: scheme.primary,
                ),
                onPressed: () => setState(() => _expanded = !_expanded),
                child: Text(_expanded ? '收起' : '展开全部'),
              ),
          ],
        );
      },
    );
  }
}

class _ExpandableItemList extends StatefulWidget {
  const _ExpandableItemList({
    required this.itemCount,
    required this.previewCount,
    required this.itemBuilder,
  });

  final int itemCount;
  final int previewCount;
  final Widget Function(int index) itemBuilder;

  @override
  State<_ExpandableItemList> createState() => _ExpandableItemListState();
}

class _ExpandableItemListState extends State<_ExpandableItemList> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    if (widget.itemCount == 0) return const SizedBox.shrink();
    final showAll = _expanded || widget.itemCount <= widget.previewCount;
    final count = showAll ? widget.itemCount : widget.previewCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < count; i++) widget.itemBuilder(i),
        if (widget.itemCount > widget.previewCount)
          Align(
            alignment: Alignment.center,
            child: TextButton.icon(
              onPressed: () => setState(() => _expanded = !_expanded),
              icon: Icon(
                _expanded
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
              ),
              label: Text(
                _expanded
                    ? '收起'
                    : '展开全部 ${widget.itemCount} 项',
              ),
            ),
          ),
      ],
    );
  }
}

class _ExpandableChipWrap extends StatefulWidget {
  const _ExpandableChipWrap({
    required this.itemCount,
    required this.previewCount,
    required this.chipBuilder,
  });

  final int itemCount;
  final int previewCount;
  final Widget Function(int index) chipBuilder;

  @override
  State<_ExpandableChipWrap> createState() => _ExpandableChipWrapState();
}

class _ExpandableChipWrapState extends State<_ExpandableChipWrap> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    if (widget.itemCount == 0) return const SizedBox.shrink();
    final showAll = _expanded || widget.itemCount <= widget.previewCount;
    final count = showAll ? widget.itemCount : widget.previewCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < count; i++) widget.chipBuilder(i),
          ],
        ),
        if (widget.itemCount > widget.previewCount)
          Align(
            alignment: Alignment.center,
            child: TextButton.icon(
              onPressed: () => setState(() => _expanded = !_expanded),
              icon: Icon(
                _expanded
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
              ),
              label: Text(
                _expanded ? '收起' : '展开全部 ${widget.itemCount} 项',
              ),
            ),
          ),
      ],
    );
  }
}

class _MetaSection extends StatelessWidget {
  const _MetaSection({
    required this.title,
    required this.loading,
    required this.empty,
    required this.child,
    this.trailing,
  });

  final String title;
  final bool loading;
  final bool empty;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 600;
    return Card(
      child: Padding(
        padding: EdgeInsets.all(narrow ? 12 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 10),
            if (loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else if (empty)
              Text(
                '暂无数据',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              )
            else
              child,
          ],
        ),
      ),
    );
  }
}

class _MetaAvatar extends StatelessWidget {
  const _MetaAvatar({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Icon(Icons.person_outline_rounded, size: 18),
      );
    }
    return CircleAvatar(
      backgroundImage: CachedNetworkImageProvider(
        BangumiEndpoints.imageUrl(url),
      ),
    );
  }
}
