import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/network/bangumi_endpoints.dart';
import '../core/network/bangumi_support.dart';
import '../core/network/community_service.dart';
import '../models/bangumi_models.dart';
import '../state/session_controller.dart';
import '../widgets/collection_editor_sheet.dart';
import '../widgets/subject_widgets.dart';
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
  bool _loadingFriends = false;
  bool _friendsExpanded = false;
  bool _friendsLoaded = false;
  bool _loadingMeta = false;
  bool _loadingComments = false;
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
          final episodeCollections = await api.getEpisodeCollections(
            widget.subject.id,
          );
          episodes = [for (final item in episodeCollections) item.episode];
          episodeTypes = {
            for (final item in episodeCollections) item.episode.id: item.type,
          };
        } else {
          // Omit type filter so SP/OP/ED also load for filtering.
          episodes = await api.getEpisodes(widget.subject.id);
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
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
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

  Future<void> _loadComments(int subjectId) async {
    setState(() => _loadingComments = true);
    try {
      final comments = await ref
          .read(bangumiApiProvider)
          .getSubjectComments(subjectId);
      if (!mounted) return;
      setState(() {
        _comments = comments;
        _loadingComments = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingComments = false);
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('条目详情'),
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
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 60),
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
                      ),
                      if (subject.score > 0 || subject.ratingTotal > 0) ...[
                        const SizedBox(height: 18),
                        _RatingPanel(subject: subject),
                      ],
                      const SizedBox(height: 18),
                      _FriendsWatchingPanel(
                        loading: _loadingFriends,
                        expanded: _friendsExpanded,
                        loaded: _friendsLoaded,
                        statuses: _friendStatuses,
                        subjectType: subject.type,
                        onExpand: () => _loadFriendStatuses(subject.id),
                      ),
                      if (subject.summary.isNotEmpty) ...[
                        const SizedBox(height: 30),
                        Text(
                          '简介',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          subject.summary,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ],
                      if (subject.type.hasEpisodes) ...[
                        const SizedBox(height: 30),
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
                      const SizedBox(height: 30),
                      _MetaSection(
                        title: '角色',
                        loading: _loadingMeta,
                        empty: _characters.isEmpty,
                        child: Column(
                          children: [
                            for (final c in _characters.take(24))
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: _MetaAvatar(url: c.imageUrl),
                                title: Text(c.displayName),
                                subtitle: Text(
                                  [
                                    if (c.relation.isNotEmpty) c.relation,
                                    if (c.actors.isNotEmpty)
                                      'CV: ${c.actors.join(' / ')}',
                                  ].join(' · '),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      _MetaSection(
                        title: '制作人员',
                        loading: _loadingMeta,
                        empty: _persons.isEmpty,
                        child: Column(
                          children: [
                            for (final p in _persons.take(24))
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: _MetaAvatar(url: p.imageUrl),
                                title: Text(p.displayName),
                                subtitle: Text(
                                  [
                                    if (p.relation.isNotEmpty) p.relation,
                                    if (p.career.isNotEmpty)
                                      p.career.join(' / '),
                                  ].join(' · '),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      _MetaSection(
                        title: '关联条目',
                        loading: _loadingMeta,
                        empty: _related.isEmpty,
                        child: Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            for (final item in _related.take(20))
                              ActionChip(
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
                                label: Text(
                                  item.relation.isEmpty
                                      ? item.displayName
                                      : '${item.relation} · ${item.displayName}',
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
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      _MetaSection(
                        title: '吐槽',
                        loading: _loadingComments,
                        empty: _comments.isEmpty,
                        trailing: TextButton(
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
                            for (final c in _comments.take(30))
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  c.userName.isEmpty ? '用户' : c.userName,
                                ),
                                subtitle: Text(c.comment),
                                trailing: c.rate > 0
                                    ? Text(
                                        '${c.rate}',
                                        style: const TextStyle(
                                          color: Color(0xFFF3A646),
                                          fontWeight: FontWeight.w800,
                                        ),
                                      )
                                    : null,
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
          .getEpisodeCollections(subjectId);
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
  });

  final Subject subject;
  final UserCollection? collection;
  final bool busy;
  final ValueChanged<CollectionType> onCollectionChanged;
  final VoidCallback onManageCollection;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 620;
          final cover = SubjectCover(
            subject: subject,
            width: compact ? 122 : 170,
            height: compact ? 174 : 240,
            borderRadius: 18,
          );
          final info = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                subject.displayName,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              if (subject.nameCn.isNotEmpty && subject.name.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  subject.name,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  _Meta(
                    icon: subjectTypeIcon(subject.type),
                    text: subject.type.label,
                  ),
                  if (subject.score > 0)
                    _Meta(
                      icon: Icons.star_rounded,
                      text: subject.score.toStringAsFixed(2),
                      color: const Color(0xFFF3A646),
                    ),
                  if (subject.ratingTotal > 0)
                    _Meta(
                      icon: Icons.how_to_vote_outlined,
                      text: '${subject.ratingTotal} 人评分',
                    ),
                  if (subject.rank > 0)
                    _Meta(
                      icon: Icons.emoji_events_outlined,
                      text: '#${subject.rank}',
                    ),
                  if (subject.episodeCount > 0)
                    _Meta(
                      icon: Icons.play_circle_outline_rounded,
                      text: '${subject.episodeCount} 话',
                    ),
                  if (subject.volumeCount > 0)
                    _Meta(
                      icon: Icons.menu_book_outlined,
                      text: '${subject.volumeCount} 卷',
                    ),
                  if (subject.date.isNotEmpty)
                    _Meta(
                      icon: Icons.calendar_today_outlined,
                      text: subject.date,
                    ),
                ],
              ),
              if (subject.tags.isNotEmpty) ...[
                const SizedBox(height: 14),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final tag in subject.tags.take(5))
                      Chip(
                        label: Text(tag),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 18),
              if (collection != null &&
                  (collection!.rate > 0 ||
                      collection!.comment.isNotEmpty ||
                      collection!.tags.isNotEmpty)) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  children: [
                    if (collection!.rate > 0)
                      Chip(
                        avatar: const Icon(Icons.star_rounded, size: 18),
                        label: Text('我的评分 ${collection!.rate}'),
                        visualDensity: VisualDensity.compact,
                      ),
                    if (collection!.private)
                      const Chip(
                        avatar: Icon(Icons.lock_outline_rounded, size: 16),
                        label: Text('仅自己可见'),
                        visualDensity: VisualDensity.compact,
                      ),
                    for (final tag in collection!.tags.take(6))
                      Chip(
                        label: Text(tag),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
                if (collection!.comment.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    collection!.comment,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  SizedBox(
                    width: compact ? double.infinity : 210,
                    child: MenuAnchor(
                      builder: (context, controller, child) =>
                          FilledButton.icon(
                            onPressed: busy
                                ? null
                                : () => controller.isOpen
                                      ? controller.close()
                                      : controller.open(),
                            icon: busy
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Icon(
                                    collection == null
                                        ? Icons.add_rounded
                                        : Icons.bookmark_rounded,
                                  ),
                            label: Text(
                              collection?.type.labelFor(subject.type) ??
                                  '加入收藏',
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
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: busy ? null : onManageCollection,
                    icon: const Icon(Icons.edit_note_rounded),
                    label: const Text('评分与吐槽'),
                  ),
                ],
              ),
            ],
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    cover,
                    const SizedBox(width: 18),
                    Expanded(child: info),
                  ],
                ),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              cover,
              const SizedBox(width: 28),
              Expanded(child: info),
            ],
          );
        },
      ),
    ),
  );
}

class _RatingPanel extends StatelessWidget {
  const _RatingPanel({required this.subject});

  final Subject subject;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxCount = subject.ratingCount.values.fold<int>(
      0,
      (max, value) => value > max ? value : max,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '评分详情',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                Text(
                  '争议度 ${subject.controversyLabel}',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 14,
              runSpacing: 8,
              children: [
                if (subject.score > 0)
                  Text(
                    subject.score.toStringAsFixed(2),
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
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
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 22,
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
                            minHeight: 8,
                            backgroundColor: scheme.surfaceContainerHighest,
                            color: const Color(0xFFF3A646),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 42,
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
                    ),
                  if (subject.doingCount > 0)
                    Chip(
                      label: Text(
                        '${CollectionType.doing.labelFor(subject.type)} ${subject.doingCount}',
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  if (subject.collectCount > 0)
                    Chip(
                      label: Text(
                        '${CollectionType.done.labelFor(subject.type)} ${subject.collectCount}',
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  if (subject.onHoldCount > 0)
                    Chip(
                      label: Text('搁置 ${subject.onHoldCount}'),
                      visualDensity: VisualDensity.compact,
                    ),
                  if (subject.droppedCount > 0)
                    Chip(
                      label: Text('抛弃 ${subject.droppedCount}'),
                      visualDensity: VisualDensity.compact,
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
  const _Meta({required this.icon, required this.text, this.color});

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        icon,
        size: 18,
        color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      const SizedBox(width: 4),
      Text(text),
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
  Widget build(BuildContext context) => Wrap(
    spacing: 9,
    runSpacing: 9,
    children: [
      for (final episode in episodes)
        Tooltip(
          message: episode.displayName,
          child: SizedBox(
            width: 58,
            height: 44,
            child: episodeTypes[episode.id] == 2
                ? FilledButton(
                    onPressed: enabled && !updatingEpisodes.contains(episode.id)
                        ? () => onTap(episode, true)
                        : null,
                    style: FilledButton.styleFrom(padding: EdgeInsets.zero),
                    child: Text(_episodeNumber(episode.number)),
                  )
                : OutlinedButton(
                    onPressed: enabled && !updatingEpisodes.contains(episode.id)
                        ? () => onTap(episode, false)
                        : null,
                    style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                    child: Text(_episodeNumber(episode.number)),
                  ),
          ),
        ),
    ],
  );

  String _episodeNumber(double value) =>
      value % 1 == 0 ? value.toInt().toString() : value.toStringAsFixed(1);
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const Spacer(),
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
