import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/external_link.dart';
import '../core/insights/subject_meta_insights.dart';
import '../core/layout/app_layout.dart';
import '../core/network/bangumi_endpoints.dart';
import '../core/network/bangumi_support.dart';
import '../core/network/community_service.dart';
import '../core/network/moegirl_service.dart';
import '../core/network/netaba_api.dart';
import '../core/storage/snapshot_cache.dart';
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
import 'moegirl_detail_screen.dart';
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
  bool _loadingEpisodes = false;
  String? _episodesError;
  String? _metaError;
  String? _topicsError;
  String? _commentsError;
  String? _friendsError;
  bool _loadingMoegirl = false;
  bool _moegirlAttempted = false;
  NetabaSubjectHistory? _scoreHistory;
  MoegirlEntry? _moegirlEntry;
  String? _historyError;
  String? _moegirlError;
  int? _episodeTypeFilter; // null = all, 0 = main
  final Set<int> _updatingEpisodes = {};
  late final SessionController _sessionController;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _sessionController = ref.read(sessionProvider.notifier);
    _details = widget.subject;
    _loading = false;
    Future.microtask(_load);
  }

  int _loadGeneration = 0;
  String? _loadUsername;

  bool _isCurrentLoad(int generation) =>
      mounted &&
      generation == _loadGeneration &&
      ref.read(sessionProvider).user?.username == _loadUsername;

  Future<void> _load() async {
    if (!mounted) return;
    final generation = ++_loadGeneration;
    _loadUsername = ref.read(sessionProvider).user?.username;
    setState(() {
      _loading = _details == null;
      _error = null;
      _friendsExpanded = false;
      _friendsLoaded = false;
      _friendStatuses = const [];
      _loadingEpisodes = widget.subject.type.hasEpisodes;
      _episodesError = null;
    });
    // A slow episode request must not hold the synopsis or other sections.
    final primary = Future.wait([
      _loadSubjectInfo(generation),
      _loadEpisodeInfo(generation),
    ]);
    unawaited(_loadMeta(widget.subject.id));
    unawaited(_loadComments(widget.subject.id));
    unawaited(_loadTopics(widget.subject.id));
    unawaited(_loadScoreHistory(widget.subject.id));
    await primary;
  }

  Future<void> _loadSubjectInfo(int generation) async {
    try {
      final details = await ref
          .read(bangumiApiProvider)
          .getSubject(widget.subject.id);
      if (!_isCurrentLoad(generation)) return;
      setState(() {
        _details = details;
        _loading = false;
      });
    } catch (_) {
      if (!_isCurrentLoad(generation)) return;
      // The list item's information stays usable if the full detail is offline.
      setState(() => _loading = false);
    }
  }

  Future<void> _loadEpisodeInfo(int generation) async {
    if (!widget.subject.type.hasEpisodes) return;
    final api = ref.read(bangumiApiProvider);
    final cache = ref.read(snapshotCacheProvider);
    final hasCollection =
        ref.read(sessionProvider).collectionFor(widget.subject.id) != null;
    var networkApplied = false;
    Future<void> restoreCache() async {
      if (!hasCollection) return;
      try {
        final cached = await cache.readEpisodeCollections(widget.subject.id);
        if (cached == null || !_isCurrentLoad(generation) || networkApplied) {
          return;
        }
        final local = await _sessionController.applyPendingEpisodeChanges(
          widget.subject.id,
          cached,
        );
        if (!_isCurrentLoad(generation) || networkApplied) return;
        setState(() {
          _episodes = [for (final item in local) item.episode];
          _episodeTypes = {
            for (final item in local) item.episode.id: item.type,
          };
        });
      } catch (_) {
        // Failed optional storage must never prevent the network request.
      }
    }

    unawaited(restoreCache());
    try {
      if (hasCollection) {
        var items = await api.getEpisodeCollections(
          widget.subject.id,
          episodeType: null,
        );
        if (!_isCurrentLoad(generation)) return;
        items = await _sessionController.applyPendingEpisodeChanges(
          widget.subject.id,
          items,
        );
        if (!_isCurrentLoad(generation)) return;
        networkApplied = true;
        setState(() {
          _episodes = [for (final item in items) item.episode];
          _episodeTypes = {
            for (final item in items) item.episode.id: item.type,
          };
        });
        unawaited(
          cache
              .writeEpisodeCollections(widget.subject.id, items)
              .catchError((Object _) {}),
        );
      } else {
        final episodes = await api.getEpisodes(
          widget.subject.id,
          episodeType: null,
        );
        if (!_isCurrentLoad(generation)) return;
        setState(() {
          _episodes = episodes;
          _episodeTypes = const {};
        });
      }
    } catch (_) {
      // Keep any restored episode progress visible while offline.
      if (_isCurrentLoad(generation)) {
        setState(() => _episodesError = '章节加载失败，请重试');
      }
    } finally {
      if (_isCurrentLoad(generation)) {
        setState(() => _loadingEpisodes = false);
      }
    }
  }

  Future<void> _loadScoreHistory(int subjectId) async {
    setState(() {
      _loadingHistory = true;
      _historyError = null;
    });
    try {
      final history = await ref
          .read(netabaApiProvider)
          .getSubjectHistory(subjectId);
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
    setState(() {
      _loadingMeta = true;
      _metaError = null;
    });
    var failed = false;
    Future<Object?> guarded<T>(Future<T> future, List<T> fallback) =>
        future.then<Object?>((value) => value).catchError((Object _) {
          failed = true;
          return fallback;
        });
    try {
      final api = ref.read(bangumiApiProvider);
      // Independent sections: one failing request must not discard the others.
      final results = await Future.wait<Object?>([
        guarded(
          api.getSubjectCharacters(subjectId),
          const <SubjectCharacter>[],
        ),
        guarded(api.getSubjectPersons(subjectId), const <SubjectPerson>[]),
        guarded(api.getRelatedSubjects(subjectId), const <RelatedSubject>[]),
      ]);
      if (!mounted) return;
      setState(() {
        _characters = results[0] as List<SubjectCharacter>;
        _persons = results[1] as List<SubjectPerson>;
        _related = results[2] as List<RelatedSubject>;
        _loadingMeta = false;
        if (failed) _metaError = '部分关联信息加载失败';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingMeta = false;
        _metaError = '角色 / 制作人员 / 关联条目加载失败';
      });
    }
  }

  Future<void> _loadTopics(int subjectId) async {
    setState(() {
      _loadingTopics = true;
      _topicsError = null;
    });
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
      setState(() {
        _loadingTopics = false;
        _topicsError = '讨论加载失败';
      });
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
        _commentsError = null;
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
          _commentsError = null;
        }
        // HTML pages are typically ~20 items; short page => end.
        _commentsHasMore = comments.length >= 10;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingComments = false;
        _loadingMoreComments = false;
        if (!append) _commentsError = '吐槽加载失败';
      });
    }
  }

  Future<void> _loadFriendStatuses(int subjectId) async {
    final me = ref.read(sessionProvider).user;
    if (me == null || _loadingFriends) return;
    setState(() {
      _friendsExpanded = true;
      _loadingFriends = true;
      _friendsError = null;
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
        _friendsError = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingFriends = false;
        _friendsLoaded = true;
        _friendsError = '好友收藏加载失败';
      });
    }
  }

  Future<void> _loadMoegirl(Subject subject) async {
    if (_loadingMoegirl) return;
    final forceRefresh = _moegirlAttempted;
    setState(() {
      _loadingMoegirl = true;
      _moegirlAttempted = true;
      _moegirlError = null;
    });
    try {
      final entry = await MoegirlService.shared.findForSubject(
        subject,
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      setState(() {
        _moegirlEntry = entry;
        _loadingMoegirl = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingMoegirl = false;
        _moegirlError = error is MoegirlException
            ? error.message
            : '获取萌娘百科资料失败，请稍后重试';
      });
    }
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
                        error: _friendsError,
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
                      SizedBox(height: blockGap),
                      _MoegirlPanel(
                        entry: _moegirlEntry,
                        loading: _loadingMoegirl,
                        attempted: _moegirlAttempted,
                        error: _moegirlError,
                        onLoad: () => _loadMoegirl(subject),
                        onSearch: () => _openMoegirlSearch(subject),
                        onOpen: _moegirlEntry == null
                            ? null
                            : () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => MoegirlDetailScreen(
                                    entry: _moegirlEntry!,
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
                              onPressed: () {
                                setState(() {
                                  _loadingEpisodes = true;
                                  _episodesError = null;
                                });
                                unawaited(_loadEpisodeInfo(_loadGeneration));
                              },
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
                        error: _metaError,
                        onRetry: () => _loadMeta(subject.id),
                        trailing: _MetaCount('${_characters.length} 个角色'),
                        child: _CharacterRail(
                          characters: _characters,
                          onOpen: (character) => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => CharacterDetailScreen(
                                characterId: character.id,
                                seedName: character.displayName,
                                seedImageUrl: character.imageUrl,
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: sectionGap),
                      _MetaSection(
                        title: '制作人员',
                        loading: _loadingMeta,
                        empty: _persons.isEmpty,
                        error: _metaError,
                        onRetry: () => _loadMeta(subject.id),
                        trailing: _MetaCount('${_persons.length} 条职员记录'),
                        child: _StaffRoleGroups(
                          people: _persons,
                          onOpen: (person) => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => PersonDetailScreen(
                                personId: person.id,
                                seedName: person.displayName,
                                seedImageUrl: person.imageUrl,
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: sectionGap),
                      _MetaSection(
                        title: '关联条目',
                        loading: _loadingMeta,
                        empty: _related.isEmpty,
                        error: _metaError,
                        onRetry: () => _loadMeta(subject.id),
                        trailing: _MetaCount('${_related.length} 个条目'),
                        child: _RelatedSubjectRail(
                          subjects: _related,
                          onOpen: (item) => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => SubjectDetailScreen(
                                subject: item.toSubject(),
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: sectionGap),
                      _MetaSection(
                        title: '讨论',
                        loading: _loadingTopics,
                        empty: _topics.isEmpty,
                        error: _topicsError,
                        onRetry: () => _loadTopics(subject.id),
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
                              trailing: const Icon(Icons.chevron_right_rounded),
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
                        error: _commentsError,
                        onRetry: () => _loadComments(subject.id),
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

  Future<void> _reloadEpisodeWatchState(int subjectId) async {
    try {
      var episodeCollections = await ref
          .read(bangumiApiProvider)
          .getEpisodeCollections(subjectId, episodeType: null);
      episodeCollections = await _sessionController.applyPendingEpisodeChanges(
        subjectId,
        episodeCollections,
      );
      await SnapshotCache.shared.writeEpisodeCollections(
        subjectId,
        episodeCollections,
      );
      if (!mounted) return;
      setState(() {
        _episodes = [for (final item in episodeCollections) item.episode];
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
      previousType: previousType,
      trackGlobalBusy: false,
    );
    if (!mounted) return;
    setState(() {
      _updatingEpisodes.remove(episode.id);
      if (error != null) {
        _episodeTypes = {..._episodeTypes, episode.id: previousType};
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
    return LayoutBuilder(
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
          size: BangumiImageSize.large,
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
            Text(subject.displayName, style: titleStyle),
            if (subject.nameCn.isNotEmpty && subject.name.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                subject.name,
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
                  _Meta(icon: Icons.tv_outlined, text: subject.platform),
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
                    ...subject.tags.where((t) => !subject.metaTags.contains(t)),
                  ].take(compact ? 8 : 10))
                    ActionChip(
                      label: Text(tag),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onPressed: onTagTap == null ? null : () => onTagTap!(tag),
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
                    unawaited(launchExternalLink(uri));
                  },
                  icon: const Icon(Icons.public_rounded, size: 18),
                  label: const Text('官方网站'),
                ),
              );

        final myCollection =
            collection == null ||
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
                if (tags != null) ...[const SizedBox(height: 12), tags],
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
                    if (tags != null) ...[const SizedBox(height: 14), tags],
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
    );
  }
}

class _MoegirlPanel extends StatelessWidget {
  const _MoegirlPanel({
    required this.entry,
    required this.loading,
    required this.attempted,
    required this.error,
    required this.onLoad,
    required this.onSearch,
    required this.onOpen,
  });

  final MoegirlEntry? entry;
  final bool loading;
  final bool attempted;
  final String? error;
  final VoidCallback onLoad;
  final VoidCallback onSearch;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('补充资料', style: theme.textTheme.titleLarge),
        const SizedBox(height: 10),
        if (!attempted && !loading)
          OutlinedButton.icon(
            onPressed: onLoad,
            icon: const Icon(Icons.auto_stories_outlined),
            label: const Text('从萌娘百科补充'),
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              border: Border.symmetric(
                horizontal: BorderSide(color: scheme.outlineVariant),
              ),
            ),
            child: loading
                ? const Row(
                    children: [
                      SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 12),
                      Expanded(child: Text('正在匹配萌娘百科条目…')),
                    ],
                  )
                : entry != null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry!.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _ExpandableText(
                        text: entry!.extract,
                        style: theme.textTheme.bodyLarge,
                        collapsedLines: 7,
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: onOpen,
                            icon: const Icon(Icons.article_outlined),
                            label: Text(
                              entry!.sections.isEmpty
                                  ? '阅读全文'
                                  : '阅读全文 · ${entry!.sections.length} 章',
                            ),
                          ),
                          Text(
                            '文本来自萌娘百科 · CC BY-NC-SA 3.0 CN',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () => unawaited(
                              launchExternalLink(Uri.tryParse(entry!.url)),
                            ),
                            icon: const Icon(Icons.open_in_new_rounded),
                            label: const Text('查看原文'),
                          ),
                        ],
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        error ?? '未找到可信匹配，已避免展示可能错误的条目。',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: error == null
                              ? scheme.onSurfaceVariant
                              : scheme.error,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: onLoad,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('重试'),
                          ),
                          TextButton.icon(
                            onPressed: onSearch,
                            icon: const Icon(Icons.search_rounded),
                            label: const Text('手动搜索'),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
      ],
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
    return Container(
      decoration: BoxDecoration(
        border: Border.symmetric(
          horizontal: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: narrow ? 12 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '评分详情',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
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
                    style:
                        (narrow
                                ? Theme.of(context).textTheme.headlineSmall
                                : Theme.of(context).textTheme.headlineMedium)
                            ?.copyWith(
                              color: const Color(0xFFF3A646),
                              fontWeight: FontWeight.w700,
                            ),
                  ),
                if (subject.ratingTotal > 0) Text('${subject.ratingTotal} 人评分'),
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
                subject.wishCount + subject.collectCount + subject.doingCount >
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
    this.error,
  });

  final bool loading;
  final bool expanded;
  final bool loaded;
  final List<FriendSubjectStatus> statuses;
  final SubjectType subjectType;
  final VoidCallback onExpand;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.symmetric(
          horizontal: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '好友收藏',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
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
                    statuses.isEmpty && error != null
                        ? error!
                        : (statuses.isEmpty
                              ? '暂无好友收藏'
                              : '${statuses.length} 位好友'),
                    style: TextStyle(
                      color: statuses.isEmpty && error != null
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
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
                                status.user.displayName.isEmpty
                                    ? '?'
                                    : status.user.displayName.characters.first
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
      Text(text, style: TextStyle(fontSize: compact ? 12.5 : null)),
    ],
  );
}

class _EpisodeGrid extends StatefulWidget {
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
  State<_EpisodeGrid> createState() => _EpisodeGridState();
}

class _EpisodeGridState extends State<_EpisodeGrid> {
  static const _pageSize = 60;
  int _visibleCount = _pageSize;

  @override
  void didUpdateWidget(covariant _EpisodeGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.episodes.length != widget.episodes.length) {
      _visibleCount = _pageSize;
    }
  }

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
        final cellW = ((width - spacing * (target - 1)) / target).clamp(
          48.0,
          64.0,
        );
        final cellH = width < 420 ? 42.0 : 44.0;
        final visibleCount = _visibleCount < widget.episodes.length
            ? _visibleCount
            : widget.episodes.length;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final episode in widget.episodes.take(visibleCount))
                  Tooltip(
                    message: episode.displayName,
                    child: SizedBox(
                      width: cellW,
                      height: cellH,
                      child: widget.episodeTypes[episode.id] == 2
                          ? FilledButton(
                              onPressed:
                                  widget.enabled &&
                                      !widget.updatingEpisodes.contains(
                                        episode.id,
                                      )
                                  ? () => widget.onTap(episode, true)
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
                              onPressed:
                                  widget.enabled &&
                                      !widget.updatingEpisodes.contains(
                                        episode.id,
                                      )
                                  ? () => widget.onTap(episode, false)
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
            ),
            if (visibleCount < widget.episodes.length) ...[
              const SizedBox(height: 10),
              Center(
                child: TextButton.icon(
                  onPressed: () => setState(() {
                    final next = _visibleCount + _pageSize;
                    _visibleCount = next < widget.episodes.length
                        ? next
                        : widget.episodes.length;
                  }),
                  icon: const Icon(Icons.expand_more_rounded),
                  label: Text(
                    '继续显示（$visibleCount / ${widget.episodes.length}）',
                  ),
                ),
              ),
            ],
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
        // Measurement-only painter: release native text layout resources
        // immediately instead of leaking one per rebuild.
        painter.dispose();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.text,
              style: widget.style,
              maxLines: _expanded ? null : widget.collapsedLines,
              overflow: _expanded
                  ? TextOverflow.visible
                  : TextOverflow.ellipsis,
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
              label: Text(_expanded ? '收起' : '展开全部 ${widget.itemCount} 项'),
            ),
          ),
      ],
    );
  }
}

class _MetaCount extends StatelessWidget {
  const _MetaCount(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: Theme.of(context).textTheme.labelLarge?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}

class _HorizontalCardRail extends StatefulWidget {
  const _HorizontalCardRail({
    required this.itemCount,
    required this.itemWidth,
    required this.height,
    required this.itemBuilder,
  });

  final int itemCount;
  final double itemWidth;
  final double height;
  final Widget Function(BuildContext context, int index) itemBuilder;

  @override
  State<_HorizontalCardRail> createState() => _HorizontalCardRailState();
}

class _HorizontalCardRailState extends State<_HorizontalCardRail> {
  final ScrollController _controller = ScrollController();
  bool _canGoBack = false;
  bool _canGoForward = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_syncButtons);
  }

  @override
  void didUpdateWidget(covariant _HorizontalCardRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.itemCount != widget.itemCount) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncButtons());
    }
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_syncButtons)
      ..dispose();
    super.dispose();
  }

  void _syncButtons() {
    if (!mounted || !_controller.hasClients) return;
    final position = _controller.position;
    final canGoBack = position.pixels > position.minScrollExtent + 2;
    final canGoForward = position.pixels < position.maxScrollExtent - 2;
    if (canGoBack == _canGoBack && canGoForward == _canGoForward) return;
    setState(() {
      _canGoBack = canGoBack;
      _canGoForward = canGoForward;
    });
  }

  void _move(double direction) {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    final target = (position.pixels + position.viewportDimension * direction)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncButtons());
    final showArrows = MediaQuery.sizeOf(context).width >= 600;
    return SizedBox(
      height: widget.height,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ListView.separated(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            itemCount: widget.itemCount,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) => SizedBox(
              width: widget.itemWidth,
              child: widget.itemBuilder(context, index),
            ),
          ),
          if (showArrows && _canGoBack)
            Positioned(
              left: 4,
              child: IconButton.filledTonal(
                tooltip: '向前浏览',
                onPressed: () => _move(-.8),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
            ),
          if (showArrows && _canGoForward)
            Positioned(
              right: 4,
              child: IconButton.filledTonal(
                tooltip: '继续浏览',
                onPressed: () => _move(.8),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ),
        ],
      ),
    );
  }
}

class _CharacterRail extends StatelessWidget {
  const _CharacterRail({required this.characters, required this.onOpen});

  final List<SubjectCharacter> characters;
  final ValueChanged<SubjectCharacter> onOpen;

  @override
  Widget build(BuildContext context) => _HorizontalCardRail(
    itemCount: characters.length,
    itemWidth: 216,
    height: 112,
    itemBuilder: (context, index) {
      final character = characters[index];
      return _CharacterCard(
        character: character,
        onTap: () => onOpen(character),
      );
    },
  );
}

class _CharacterCard extends StatelessWidget {
  const _CharacterCard({required this.character, required this.onTap});

  final SubjectCharacter character;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              _MetaImage(
                url: character.imageUrl,
                width: 62,
                height: 92,
                icon: Icons.face_outlined,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      character.displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (character.relation.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        character.relation,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: scheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ],
                    const Spacer(),
                    Text(
                      character.actorNames.isEmpty
                          ? '声优未收录'
                          : 'CV · ${character.actorNames.join(' / ')}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StaffRoleGroups extends StatefulWidget {
  const _StaffRoleGroups({required this.people, required this.onOpen});

  final List<SubjectPerson> people;
  final ValueChanged<SubjectPerson> onOpen;

  @override
  State<_StaffRoleGroups> createState() => _StaffRoleGroupsState();
}

class _StaffRoleGroupsState extends State<_StaffRoleGroups> {
  bool _expanded = false;

  @override
  void didUpdateWidget(covariant _StaffRoleGroups oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.people.length != widget.people.length) _expanded = false;
  }

  @override
  Widget build(BuildContext context) {
    final groups = groupSubjectStaffByRole(widget.people);
    final previewCount = MediaQuery.sizeOf(context).width < 600 ? 4 : 6;
    final visibleCount = _expanded
        ? groups.length
        : groups.length < previewCount
        ? groups.length
        : previewCount;
    final visibleGroups = groups.take(visibleCount).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final group in visibleGroups) ...[
          _StaffRoleRow(group: group, onOpen: widget.onOpen),
          if (group != visibleGroups.last) const SizedBox(height: 16),
        ],
        if (groups.length > previewCount) ...[
          const SizedBox(height: 8),
          Center(
            child: TextButton.icon(
              onPressed: () => setState(() => _expanded = !_expanded),
              icon: Icon(
                _expanded
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
              ),
              label: Text(_expanded ? '收起职位' : '展开全部 ${groups.length} 类职位'),
            ),
          ),
        ],
      ],
    );
  }
}

class _StaffRoleRow extends StatelessWidget {
  const _StaffRoleRow({required this.group, required this.onOpen});

  final SubjectStaffRoleGroup group;
  final ValueChanged<SubjectPerson> onOpen;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              group.role,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          _MetaCount('${group.people.length} 位'),
        ],
      ),
      const SizedBox(height: 8),
      _HorizontalCardRail(
        itemCount: group.people.length,
        itemWidth: 210,
        height: 82,
        itemBuilder: (context, index) {
          final person = group.people[index];
          return _StaffPersonCard(person: person, onTap: () => onOpen(person));
        },
      ),
    ],
  );
}

class _StaffPersonCard extends StatelessWidget {
  const _StaffPersonCard({required this.person, required this.onTap});

  final SubjectPerson person;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final identity = person.type == 2
        ? '公司'
        : person.type == 3
        ? '团体'
        : person.career.join(' / ');
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              _MetaImage(
                url: person.imageUrl,
                width: 48,
                height: 48,
                round: person.type != 2,
                icon: person.type == 2
                    ? Icons.business_outlined
                    : Icons.person_outline_rounded,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      person.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        if (identity.isNotEmpty) identity,
                        if (person.eps.isNotEmpty) '集数 ${person.eps}',
                        if (identity.isEmpty && person.eps.isEmpty) '人物资料',
                      ].join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RelatedSubjectRail extends StatelessWidget {
  const _RelatedSubjectRail({required this.subjects, required this.onOpen});

  final List<RelatedSubject> subjects;
  final ValueChanged<RelatedSubject> onOpen;

  @override
  Widget build(BuildContext context) => _HorizontalCardRail(
    itemCount: subjects.length,
    itemWidth: 154,
    height: subjectPosterItemHeight(
      154,
      1,
      textScaler: MediaQuery.textScalerOf(context),
    ),
    itemBuilder: (context, index) {
      final item = subjects[index];
      return SubjectPosterCard(
        subject: item.toSubject(),
        statusLabel: item.relation.isEmpty ? '关联作品' : item.relation,
        metaLabel: item.type.label,
        onTap: () => onOpen(item),
      );
    },
  );
}

class _MetaImage extends StatelessWidget {
  const _MetaImage({
    required this.url,
    required this.width,
    required this.height,
    required this.icon,
    this.round = false,
  });

  final String url;
  final double width;
  final double height;
  final IconData icon;
  final bool round;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final borderRadius = BorderRadius.circular(round ? width / 2 : 12);
    return ClipRRect(
      borderRadius: borderRadius,
      child: SizedBox(
        width: width,
        height: height,
        child: url.isEmpty
            ? ColoredBox(
                color: scheme.surfaceContainerHighest,
                child: Icon(icon, color: scheme.onSurfaceVariant),
              )
            : CachedNetworkImage(
                imageUrl: BangumiEndpoints.imageUrl(url),
                fit: BoxFit.cover,
                memCacheWidth: (width * 2).round(),
                memCacheHeight: (height * 2).round(),
                errorWidget: (_, _, _) => ColoredBox(
                  color: scheme.surfaceContainerHighest,
                  child: Icon(icon, color: scheme.onSurfaceVariant),
                ),
              ),
      ),
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
    this.error,
    this.onRetry,
  });

  final String title;
  final bool loading;
  final bool empty;
  final Widget child;
  final Widget? trailing;
  final String? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
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
            error != null
                ? Row(
                    children: [
                      Expanded(
                        child: Text(
                          error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                      if (onRetry != null)
                        TextButton.icon(
                          onPressed: onRetry,
                          icon: const Icon(Icons.refresh_rounded, size: 16),
                          label: const Text('重试'),
                        ),
                    ],
                  )
                : Text(
                    '暂无数据',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  )
          else
            child,
        ],
      ),
    );
  }
}
