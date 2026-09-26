import '../../models/community_models.dart';
import 'bangumi_endpoints.dart';

class CommunityP1Parser {
  static final _baseUri = Uri.parse('https://bgm.tv');
  static final _imageTag = RegExp(
    r'\[img(?:=[^\]]+)?\](.*?)\[/img\]',
    caseSensitive: false,
    dotAll: true,
  );
  static final _htmlImage = RegExp(
    r'''<img[^>]+src=["']([^"']+)["'][^>]*>''',
    caseSensitive: false,
  );
  static final _urlTag = RegExp(
    r'\[url(?:=[^\]]+)?\](.*?)\[/url\]',
    caseSensitive: false,
    dotAll: true,
  );
  static final _formatTag = RegExp(
    r'\[/?(?:b|i|u|s|del|quote|code|mask|size|color|align)(?:=[^\]]*)?\]',
    caseSensitive: false,
  );

  List<CommunityTopic> parseGroupTopics(Map<String, dynamic> page) =>
      _pageData(page)
          .map((json) => _parseTopic(json, CommunityTopicKind.group))
          .whereType<CommunityTopic>()
          .toList();

  List<CommunityTopic> parseSubjectTopics(Map<String, dynamic> page) =>
      _pageData(page)
          .map((json) => _parseTopic(json, CommunityTopicKind.subject))
          .whereType<CommunityTopic>()
          .toList();

  List<CommunityTopic> parseRakuenTopics(
    Map<String, dynamic> page,
  ) => _pageData(page)
      .map((json) {
        final kind = switch (_string(json['type'])) {
          'group' => CommunityTopicKind.group,
          'subject' => CommunityTopicKind.subject,
          'episode' => CommunityTopicKind.episode,
          'character' => CommunityTopicKind.character,
          'person' => CommunityTopicKind.person,
          _ => CommunityTopicKind.unknown,
        };
        if (kind.isDiscussion) return _parseTopic(json, kind);
        final id = _integer(json['id']);
        if (id <= 0 || kind == CommunityTopicKind.unknown) return null;
        final episode = _map(json['episode']);
        final subject = _map(json['subject']);
        final title = episode == null
            ? _subjectTitle(json)
            : '${_episodeTypeName(_integer(episode['type']))}.${_number(_double(episode['sort']))} ${_subjectTitle(episode)}'
                  .trim();
        final path = kind == CommunityTopicKind.episode ? 'ep' : kind.name;
        final rakuenPath = switch (kind) {
          CommunityTopicKind.character => 'crt',
          CommunityTopicKind.person => 'prsn',
          _ => 'ep',
        };
        final updated = _dateTime(json['updatedAt']);
        return CommunityTopic(
          id: id,
          kind: kind,
          title: title,
          url: 'https://bgm.tv/rakuen/topic/$rakuenPath/$id',
          webUrl: 'https://bgm.tv/$path/$id',
          sourceTitle: episode == null ? kind.label : _subjectTitle(subject),
          sourceUrl: episode == null
              ? 'https://bgm.tv/$path/$id'
              : _subjectUrl(subject),
          replyCount: _integer(episode?['comment'] ?? json['comment']),
          updatedAt: updated,
          updatedText: updated == null ? '' : _formatDateTime(updated),
        );
      })
      .whereType<CommunityTopic>()
      .toList();

  List<CommunityGroup> parseGroups(Map<String, dynamic> page) =>
      _pageData(page).map(_parseGroup).whereType<CommunityGroup>().toList();

  CommunityGroupDetail parseGroupDetail(
    Map<String, dynamic> json, {
    Map<String, dynamic>? membersPage,
    Map<String, dynamic>? moderatorsPage,
    Map<String, dynamic>? topicsPage,
    Set<CommunityGroupSection> unavailableSections = const {},
  }) {
    final group = _parseGroup(json);
    if (group == null) throw const FormatException('小组数据不完整');
    final membership = _map(json['membership']);
    final role = CommunityGroupRole.fromApi(membership?['role']);
    final hasMembershipIdentity =
        membership != null &&
        (_integer(membership['uid']) > 0 ||
            _dateTime(membership['joinedAt']) != null);
    final recentTopics = topicsPage == null
        ? const <CommunityTopic>[]
        : parseGroupTopics(topicsPage)
              .map(
                (topic) => CommunityTopic(
                  id: topic.id,
                  kind: topic.kind,
                  title: topic.title,
                  url: topic.url,
                  webUrl: topic.webUrl,
                  sourceTitle: group.name,
                  sourceUrl: group.url,
                  author: topic.author,
                  avatarUrl: topic.avatarUrl,
                  replyCount: topic.replyCount,
                  updatedText: topic.updatedText,
                  updatedAt: topic.updatedAt,
                ),
              )
              .toList();
    return CommunityGroupDetail(
      group: group,
      description: _string(json['description']),
      postCount: _integer(json['posts']),
      accessible: json['accessible'] != false,
      joinedAt: _dateTime(membership?['joinedAt']),
      membershipJoined:
          hasMembershipIdentity &&
          (!membership.containsKey('role') || role?.isActive == true),
      membershipRole: hasMembershipIdentity ? role : null,
      members: membersPage == null ? const [] : parseMembers(membersPage),
      moderators: moderatorsPage == null
          ? const []
          : parseMembers(moderatorsPage),
      recentTopics: recentTopics,
      unavailableSections: unavailableSections,
    );
  }

  List<CommunityUser> parseMembers(Map<String, dynamic> page) {
    final seen = <int>{};
    return _pageData(page)
        .map((json) => _parseUser(_map(json['user'])))
        .whereType<CommunityUser>()
        .where((user) => seen.add(user.id))
        .toList();
  }

  List<CommunityTimelineItem> parseTimeline(
    List<dynamic> data, {
    String? fallbackUsername,
    String? fallbackNickname,
    String? fallbackAvatarUrl,
  }) => data
      .map(_map)
      .whereType<Map<String, dynamic>>()
      .map(
        (json) => _parseTimelineItem(
          json,
          fallbackUsername: fallbackUsername,
          fallbackNickname: fallbackNickname,
          fallbackAvatarUrl: fallbackAvatarUrl,
        ),
      )
      .whereType<CommunityTimelineItem>()
      .toList();

  List<CommunityTimelineReply> parseTimelineReplies(List<dynamic> data) => data
      .map(_map)
      .whereType<Map<String, dynamic>>()
      .map(_parseTimelineReply)
      .whereType<CommunityTimelineReply>()
      .toList();

  List<BangumiNotice> parseNotices(Map<String, dynamic> page) =>
      _pageData(page).map(_parseNotice).whereType<BangumiNotice>().toList();

  BangumiNotice? _parseNotice(Map<String, dynamic> json) {
    final id = _integer(json['id']);
    if (id <= 0) return null;
    final createdAt = _dateTime(json['createdAt']);
    if (createdAt == null) return null;
    final sender = _parseUser(_map(json['sender']));
    return BangumiNotice(
      id: id,
      title: _string(json['title']),
      type: _integer(json['type']),
      mainId: _integer(json['mainID']),
      relatedId: _integer(json['relatedID']),
      unread: json['unread'] == true,
      createdAt: createdAt,
      sender: sender,
    );
  }

  CommunityTopicDetail parseTopicDetail(
    Map<String, dynamic> json,
    CommunityTopic topic,
  ) {
    final source = topic.kind == CommunityTopicKind.group
        ? _map(json['group'])
        : _map(json['subject']);
    final sourceTitle = topic.kind == CommunityTopicKind.subject
        ? _subjectTitle(source)
        : _string(source?['title']);
    final sourceUrl = switch (topic.kind) {
      CommunityTopicKind.group => _groupUrl(source),
      CommunityTopicKind.subject => _subjectUrl(source),
      _ => topic.sourceUrl,
    };
    final posts = <CommunityPost>[];
    final replies = _list(json['replies']);
    for (var floor = 0; floor < replies.length; floor++) {
      final reply = _map(replies[floor]);
      if (reply == null) continue;
      posts.add(_parsePost(reply, floor: floor, isOriginal: floor == 0));
      final nested = _list(reply['replies']);
      for (var index = 0; index < nested.length; index++) {
        final child = _map(nested[index]);
        if (child == null) continue;
        posts.add(
          _parsePost(
            child,
            floor: floor,
            nestedFloor: index + 1,
            isNested: true,
          ),
        );
      }
    }
    final jsonTitle = _string(json['title']);
    return CommunityTopicDetail(
      title: jsonTitle.isNotEmpty ? jsonTitle : topic.title,
      sourceTitle: sourceTitle.isNotEmpty ? sourceTitle : topic.sourceTitle,
      sourceUrl: sourceUrl.isNotEmpty ? sourceUrl : topic.sourceUrl,
      posts: posts,
    );
  }

  CommunityTopicDetail parseCommentThread(
    List<dynamic> data,
    CommunityTopic topic,
  ) {
    final posts = <CommunityPost>[];
    void add(Map<String, dynamic> json, int floor, {int? nestedFloor}) {
      posts.add(
        _parsePost(
          {...json, 'creator': json['user'] ?? json['creator']},
          floor: floor,
          nestedFloor: nestedFloor,
          isNested: nestedFloor != null,
        ),
      );
      final children = _list(
        json['replies'],
      ).map(_map).whereType<Map<String, dynamic>>();
      var index = 0;
      for (final child in children) {
        add(child, floor, nestedFloor: ++index);
      }
    }

    var floor = 0;
    for (final json in data.map(_map).whereType<Map<String, dynamic>>()) {
      add(json, ++floor);
    }
    return CommunityTopicDetail(
      title: topic.title,
      sourceTitle: topic.sourceTitle,
      sourceUrl: topic.sourceUrl,
      posts: posts,
    );
  }

  CommunityTopic? _parseTopic(
    Map<String, dynamic> json,
    CommunityTopicKind kind,
  ) {
    final id = _integer(json['id']);
    final title = _string(json['title']);
    if (id <= 0 || title.isEmpty) return null;
    final context = kind == CommunityTopicKind.group
        ? _map(json['group'])
        : _map(json['subject']);
    final creator = _map(json['creator']);
    final avatar = _map(creator?['avatar']);
    final updatedAt = _dateTime(json['updatedAt']);
    final sourceTitle = kind == CommunityTopicKind.subject
        ? _subjectTitle(context)
        : _string(context?['title']);
    final kindName = kind == CommunityTopicKind.group ? 'group' : 'subject';
    return CommunityTopic(
      id: id,
      kind: kind,
      title: title,
      url: _baseUri.resolve('/rakuen/topic/$kindName/$id').toString(),
      webUrl: _baseUri.resolve('/$kindName/topic/$id').toString(),
      sourceTitle: sourceTitle,
      sourceUrl: kind == CommunityTopicKind.group
          ? _groupUrl(context)
          : _subjectUrl(context),
      author: _userName(creator),
      avatarUrl: _string(avatar?['small']),
      replyCount: _integer(json['replyCount']),
      updatedText: updatedAt == null ? '' : _formatDateTime(updatedAt),
      updatedAt: updatedAt,
    );
  }

  CommunityPost _parsePost(
    Map<String, dynamic> json, {
    required int floor,
    int? nestedFloor,
    bool isOriginal = false,
    bool isNested = false,
  }) {
    final creator = _map(json['creator']);
    final avatar = _map(creator?['avatar']);
    final rawContent = _string(json['content']);
    final images = <String>{
      for (final match in _imageTag.allMatches(rawContent))
        if (_absolute(match.group(1)).isNotEmpty) _absolute(match.group(1)),
      for (final match in _htmlImage.allMatches(rawContent))
        if (_absolute(match.group(1)).isNotEmpty) _absolute(match.group(1)),
    }.toList();
    final createdAt = _dateTime(json['createdAt']);
    final floorText = isOriginal
        ? ''
        : nestedFloor == null
        ? '#$floor'
        // OP is unnumbered; nested replies under the OP use 楼主-n.
        : floor == 0
        ? '楼主-$nestedFloor'
        : '#$floor-$nestedFloor';
    final meta = [
      if (floorText.isNotEmpty) floorText,
      if (createdAt != null) _formatDateTime(createdAt),
    ].join(' · ');
    var body = rawContent
        .replaceAll(_imageTag, '')
        .replaceAll(_htmlImage, '')
        .replaceAllMapped(_urlTag, (match) => match.group(1) ?? '')
        .replaceAll(_formatTag, '')
        .replaceAll('\r\n', '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
    if (body.isEmpty && _integer(json['state']) != 0) {
      body = '（该回复已被删除或不可见）';
    }
    final username = _string(creator?['username']);
    return CommunityPost(
      id: _string(json['id']),
      author: _userName(creator),
      body: body,
      rawBody: rawContent,
      userUrl: username.isEmpty
          ? ''
          : _baseUri
                .resolve('/user/${Uri.encodeComponent(username)}')
                .toString(),
      avatarUrl: _string(avatar?['small']),
      meta: meta,
      images: images,
      isOriginal: isOriginal,
      isNested: isNested,
      reactions: _parseReactions(json['reactions']),
      canEdit: _integer(json['state']) == 0 && json['content'] is String,
    );
  }

  List<CommunityReaction> _parseReactions(Object? value) =>
      _list(value).map(_map).whereType<Map<String, dynamic>>().map((json) {
        final reactionValue = _integer(json['value']);
        final users = _list(json['users'])
            .map(_map)
            .whereType<Map<String, dynamic>>()
            .map(_parseUser)
            .whereType<CommunityUser>()
            .toList();
        return CommunityReaction(value: reactionValue, users: users);
      }).toList();

  CommunityGroup? _parseGroup(Map<String, dynamic> json) {
    final slug = _string(json['name']);
    final title = _string(json['title']);
    if (slug.isEmpty || title.isEmpty) return null;
    final icon = _map(json['icon']);
    final members = _integer(json['members']);
    return CommunityGroup(
      id: _integer(json['id']),
      slug: slug,
      name: title,
      url: _baseUri.resolve('/group/${Uri.encodeComponent(slug)}').toString(),
      imageUrl: _string(icon?['large']).isNotEmpty
          ? _string(icon?['large'])
          : _string(icon?['small']),
      memberText: members > 0 ? '$members 位成员' : '',
      memberCount: members,
      topicCount: _integer(json['topics']),
      createdAt: _dateTime(json['createdAt']),
      nsfw: json['nsfw'] == true,
    );
  }

  CommunityUser? _parseUser(Map<String, dynamic>? json) {
    if (json == null) return null;
    final id = _integer(json['id']);
    final username = _string(json['username']);
    if (id <= 0 || username.isEmpty) return null;
    final avatar = _map(json['avatar']);
    return CommunityUser(
      id: id,
      username: username,
      nickname: _string(json['nickname']),
      avatarUrl: _string(avatar?['large']).isNotEmpty
          ? _string(avatar?['large'])
          : _string(avatar?['small']),
      joinedAt: _dateTime(json['joinedAt']),
    );
  }

  CommunityUser? _fallbackUser(
    Map<String, dynamic> json,
    String? fallbackUsername,
    String? fallbackNickname,
    String? fallbackAvatarUrl,
  ) {
    final username = fallbackUsername?.trim() ?? '';
    if (username.isEmpty) return null;
    final uid = _integer(json['uid']);
    if (uid <= 0) return null;
    final avatar = fallbackAvatarUrl?.trim() ?? '';
    return CommunityUser(
      id: uid,
      username: username,
      nickname: fallbackNickname?.trim() ?? '',
      avatarUrl: avatar.isNotEmpty
          ? avatar
          : BangumiEndpoints.userAvatarUrl(uid),
    );
  }

  CommunityTimelineItem? _parseTimelineItem(
    Map<String, dynamic> json, {
    String? fallbackUsername,
    String? fallbackNickname,
    String? fallbackAvatarUrl,
  }) {
    final id = _integer(json['id']);
    final user =
        _parseUser(_map(json['user'])) ??
        // The own-timeline endpoint (/p1/users/{username}/timeline) omits the
        // redundant user object and only reports `uid`.
        _fallbackUser(
          json,
          fallbackUsername,
          fallbackNickname,
          fallbackAvatarUrl,
        );
    final createdAt = _dateTime(json['createdAt']);
    if (id <= 0 || user == null || createdAt == null) return null;
    final cat = _integer(json['cat']);
    final type = _integer(json['type']);
    final memo = _map(json['memo']) ?? const <String, dynamic>{};
    final source = _map(json['source']);
    final parsed = _timelineContent(cat, type, memo, json['batch'] == true);
    return CommunityTimelineItem(
      id: id,
      user: user,
      description: parsed.description,
      content: parsed.content,
      rawContent: parsed.rawContent,
      imageUrls: parsed.images,
      replyCount: _integer(json['replies']),
      createdAt: createdAt,
      sourceName: _string(source?['name']),
      sourceUrl: _string(source?['url']),
      isStatus: cat == 5 && type == 1,
      progress: parsed.progress,
      targets: _timelineTargets(cat, memo),
      reactions: _parseReactions(json['reactions']),
    );
  }

  List<CommunityTimelineTarget> _timelineTargets(
    int cat,
    Map<String, dynamic> memo,
  ) {
    final result = <CommunityTimelineTarget>[];
    void add(CommunityTimelineTargetKind kind, Map<String, dynamic>? data) {
      final id = _integer(data?['id']);
      if (data == null || id <= 0) return;
      final images = _map(data['images']);
      final title = kind == CommunityTimelineTargetKind.blog
          ? _string(data['title'])
          : _subjectTitle(data);
      result.add(
        CommunityTimelineTarget(
          kind: kind,
          id: id,
          title: title.isEmpty ? '#$id' : title,
          imageUrl: _string(images?['small'] ?? images?['medium']),
          subjectType: _integer(data['type']),
        ),
      );
    }

    if (cat == 2) {
      add(
        CommunityTimelineTargetKind.subject,
        _map(_map(memo['wiki'])?['subject']),
      );
    }
    if (cat == 3) {
      for (final item in _list(memo['subject']).map(_map)) {
        add(CommunityTimelineTargetKind.subject, _map(item?['subject']));
      }
    }
    if (cat == 6) add(CommunityTimelineTargetKind.blog, _map(memo['blog']));
    if (cat == 8) {
      final mono = _map(memo['mono']);
      for (final item in _list(mono?['characters']).map(_map)) {
        add(CommunityTimelineTargetKind.character, item);
      }
      for (final item in _list(mono?['persons']).map(_map)) {
        add(CommunityTimelineTargetKind.person, item);
      }
    }
    return result;
  }

  CommunityBlog parseBlog(
    Map<String, dynamic> json, {
    String? fallbackUsername,
  }) {
    final id = _integer(json['id']);
    if (id <= 0) throw const FormatException('日志编号无效');
    final user =
        _parseUser(_map(json['user'])) ??
        CommunityUser(
          id: _integer(json['uid']),
          username: fallbackUsername ?? '',
          nickname: fallbackUsername ?? '',
        );
    return CommunityBlog(
      id: id,
      title: _string(json['title']),
      user: user,
      content: _string(json['content']),
      summary: _string(json['summary']),
      tags: _list(
        json['tags'],
      ).map(_string).where((tag) => tag.isNotEmpty).toList(),
      isPublic: json['public'] != false,
      replyCount: _integer(json['replies']),
      createdAt: _dateTime(json['createdAt']),
      updatedAt: _dateTime(json['updatedAt']),
    );
  }

  CommunityTimelineReply? _parseTimelineReply(Map<String, dynamic> json) {
    final id = _integer(json['id']);
    final creatorId = _integer(json['creatorID']);
    final createdAt = _dateTime(json['createdAt']);
    if (id <= 0 || createdAt == null) return null;
    final user =
        _parseUser(_map(json['user'])) ??
        CommunityUser(
          id: creatorId,
          username: creatorId > 0 ? '$creatorId' : 'unknown',
          nickname: creatorId > 0 ? '用户 $creatorId' : '未知用户',
        );
    final rawContent = _string(json['content']);
    final images = _contentImages(rawContent);
    var content = _plain(rawContent);
    final isDeleted = _integer(json['state']) != 0 && content.isEmpty;
    if (isDeleted) content = '（该回复已被删除或不可见）';
    return CommunityTimelineReply(
      id: id,
      creatorId: creatorId,
      user: user,
      content: content,
      rawContent: rawContent,
      createdAt: createdAt,
      relatedId: _integer(json['relatedID']),
      imageUrls: images,
      replies: _list(json['replies'])
          .map(_map)
          .whereType<Map<String, dynamic>>()
          .map(_parseTimelineReply)
          .whereType<CommunityTimelineReply>()
          .toList(),
      isDeleted: isDeleted,
    );
  }

  _TimelineContent _timelineContent(
    int cat,
    int type,
    Map<String, dynamic> memo,
    bool batch,
  ) {
    switch (cat) {
      case 1:
        final daily = _map(memo['daily']) ?? memo;
        final groups = _list(
          daily['groups'],
        ).map(_map).whereType<Map<String, dynamic>>();
        final users = _list(
          daily['users'],
        ).map(_map).whereType<Map<String, dynamic>>();
        final target = type == 2
            ? users
                  .map(_userName)
                  .where((name) => name.isNotEmpty)
                  .take(3)
                  .join('、')
            : groups
                  .map((group) => _string(group['title']))
                  .where((name) => name.isNotEmpty)
                  .take(3)
                  .join('、');
        final action = switch (type) {
          1 => '注册成为了 Bangumi 成员',
          2 => '将 $target 加为了好友',
          3 => '加入了 $target 小组',
          4 => '创建了 $target 小组',
          _ => '进行了日常活动',
        };
        return _TimelineContent(action);
      case 2:
        final wiki = _map(memo['wiki']) ?? memo;
        final subject = _map(wiki['subject']);
        final title = _subjectTitle(subject);
        return _TimelineContent('添加或编辑了条目 $title');
      case 3:
        final collections = _list(
          memo['subject'],
        ).map(_map).whereType<Map<String, dynamic>>().toList();
        final subjects = collections
            .map((item) => _map(item['subject']))
            .whereType<Map<String, dynamic>>()
            .toList();
        final names = subjects
            .map(_subjectTitle)
            .where((name) => name.isNotEmpty);
        final action =
            const {
              1: '想读',
              2: '想看',
              3: '想听',
              4: '想玩',
              5: '读过',
              6: '看过',
              7: '听过',
              8: '玩过',
              9: '在读',
              10: '在看',
              11: '在听',
              12: '在玩',
              13: '搁置了',
              14: '抛弃了',
            }[type] ??
            '更新了收藏';
        final label = names.isEmpty
            ? '一个条目（详情暂不可用）'
            : batch
            ? '${names.take(3).join('、')} 等 ${subjects.length} 个条目'
            : names.first;
        final first = collections.isEmpty ? null : collections.first;
        final comment = _string(first?['comment']);
        final images = subjects
            .map((subject) => _map(subject['images']))
            .whereType<Map<String, dynamic>>()
            .map((images) => _string(images['small']))
            .where((url) => url.isNotEmpty)
            .take(5)
            .toList();
        return _TimelineContent(
          '$action $label',
          content: comment,
          images: images,
        );
      case 4:
        final progress = _map(memo['progress']) ?? memo;
        final batchProgress = _map(progress['batch']);
        final single = _map(progress['single']);
        final subject =
            _map(batchProgress?['subject']) ?? _map(single?['subject']);
        final title = _subjectTitle(subject);
        final timelineProgress = _parseTimelineProgress(
          batchProgress: batchProgress,
          single: single,
          subject: subject,
        );
        if (batchProgress != null) {
          final epsUpdate = _integer(batchProgress['epsUpdate']);
          final volsUpdate = _integer(batchProgress['volsUpdate']);
          final description = _integer(subject?['type']) == 1
              ? [
                  '读过 $title',
                  if (volsUpdate > 0) '第 $volsUpdate 卷',
                  if (epsUpdate > 0) '第 $epsUpdate 话',
                ].join(' ')
              : '观看 $title 的进度到第 $epsUpdate 话';
          return _TimelineContent(description, progress: timelineProgress);
        }
        final action = const {1: '想看', 2: '看过', 3: '抛弃了'}[type] ?? '更新了';
        final episode = timelineProgress?.episode;
        final episodeLabel = episode == null
            ? ''
            : '${_episodeTypeName(episode.type)}.${_number(episode.sort)}';
        return _TimelineContent(
          '$action $title${episodeLabel.isEmpty ? '' : ' $episodeLabel'}',
          progress: timelineProgress,
        );
      case 5:
        final status = _map(memo['status']) ?? memo;
        if (type == 1) {
          final content = _string(status['tsukkomi']);
          return _TimelineContent(
            '发表了吐槽',
            content: _plain(content),
            rawContent: content,
          );
        }
        if (type == 0) {
          return _TimelineContent('更新了签名', content: _string(status['sign']));
        }
        final nickname = _map(status['nickname']);
        return _TimelineContent(
          '从 ${_string(nickname?['before'])} 改名为 ${_string(nickname?['after'])}',
        );
      case 6:
        final blog = _map(memo['blog']) ?? memo;
        return _TimelineContent('发表了新日志 ${_string(blog['title'])}');
      case 7:
        final index = _map(memo['index']) ?? memo;
        return _TimelineContent(
          '${type == 0 ? '创建了' : '收藏了'}目录 ${_string(index['title'])}',
        );
      case 8:
        final mono = _map(memo['mono']);
        final characters = _list(
          mono?['characters'],
        ).map(_map).whereType<Map<String, dynamic>>().toList();
        final persons = _list(
          mono?['persons'],
        ).map(_map).whereType<Map<String, dynamic>>().toList();
        final targets = [...characters, ...persons];
        final labels = <String>[];
        for (final (kind, entries) in [('角色', characters), ('人物', persons)]) {
          final names = entries
              .map(_subjectTitle)
              .where((name) => name.isNotEmpty)
              .toList();
          if (names.isNotEmpty) labels.add('$kind ${names.join('、')}');
        }
        final action = type == 0 ? '创建了' : '收藏了';
        return _TimelineContent(
          labels.isEmpty
              ? '$action人物或角色（详情暂不可用）'
              : '$action${labels.join('、')}',
          images: targets
              .map((target) => _map(target['images']))
              .whereType<Map<String, dynamic>>()
              .map((images) {
                for (final key in ['small', 'medium', 'large', 'grid']) {
                  final url = _string(images[key]);
                  if (url.isNotEmpty) return _absolute(url);
                }
                return '';
              })
              .where((url) => url.isNotEmpty)
              .take(5)
              .toList(),
        );
      default:
        return const _TimelineContent('进行了新的活动');
    }
  }

  String _plain(String rawContent) => rawContent
      .replaceAll(_imageTag, '')
      .replaceAll(_htmlImage, '')
      .replaceAllMapped(_urlTag, (match) => match.group(1) ?? '')
      .replaceAll(_formatTag, '')
      .replaceAll('\r\n', '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();

  CommunityTimelineProgress? _parseTimelineProgress({
    required Map<String, dynamic>? batchProgress,
    required Map<String, dynamic>? single,
    required Map<String, dynamic>? subject,
  }) {
    final subjectId = _integer(subject?['id']);
    if (subjectId <= 0) return null;
    final images = _map(subject?['images']);
    final rating = _map(subject?['rating']);
    final episodeJson = _map(single?['episode']);
    return CommunityTimelineProgress(
      subjectId: subjectId,
      subjectName: _string(subject?['name']),
      subjectNameCn: _string(subject?['nameCN']),
      subjectType: _integer(subject?['type']),
      imageUrl: _string(images?['small']).isNotEmpty
          ? _string(images?['small'])
          : _string(images?['common']),
      score: _double(rating?['score']),
      rank: _integer(rating?['rank']),
      episode: episodeJson == null ? null : _parseTimelineEpisode(episodeJson),
      episodeProgress: batchProgress == null
          ? null
          : _nullablePositiveInteger(batchProgress['epsUpdate']),
      episodeTotal: _string(batchProgress?['epsTotal']),
      volumeProgress: batchProgress == null
          ? null
          : _nullablePositiveInteger(batchProgress['volsUpdate']),
      volumeTotal: _string(batchProgress?['volsTotal']),
    );
  }

  CommunityTimelineEpisode? _parseTimelineEpisode(
    Map<String, dynamic> episode,
  ) {
    final id = _integer(episode['id']);
    if (id <= 0) return null;
    return CommunityTimelineEpisode(
      id: id,
      subjectId: _integer(episode['subjectID']),
      type: _integer(episode['type']),
      sort: _double(episode['sort']),
      name: _string(episode['name']),
      nameCn: _string(episode['nameCN']),
      airDate: _string(episode['airdate']),
    );
  }

  List<String> _contentImages(String rawContent) => <String>{
    for (final match in _imageTag.allMatches(rawContent))
      if (_absolute(match.group(1)).isNotEmpty) _absolute(match.group(1)),
    for (final match in _htmlImage.allMatches(rawContent))
      if (_absolute(match.group(1)).isNotEmpty) _absolute(match.group(1)),
  }.toList();

  int? _nullablePositiveInteger(Object? value) {
    final number = _integer(value);
    return number > 0 ? number : null;
  }

  String _episodeTypeName(int type) => switch (type) {
    1 => 'SP',
    2 => 'OP',
    3 => 'ED',
    4 => 'PV',
    5 => 'MAD',
    6 => 'OTHER',
    _ => 'EP',
  };

  String _number(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(1);

  List<Map<String, dynamic>> _pageData(Map<String, dynamic> page) =>
      _list(page['data']).map(_map).whereType<Map<String, dynamic>>().toList();

  String _subjectTitle(Map<String, dynamic>? subject) {
    final nameCn = _string(subject?['nameCN']);
    return nameCn.isNotEmpty ? nameCn : _string(subject?['name']);
  }

  String _groupUrl(Map<String, dynamic>? group) {
    final slug = _string(group?['name']);
    return slug.isEmpty
        ? ''
        : _baseUri.resolve('/group/${Uri.encodeComponent(slug)}').toString();
  }

  String _subjectUrl(Map<String, dynamic>? subject) {
    final id = _integer(subject?['id']);
    return id <= 0 ? '' : _baseUri.resolve('/subject/$id').toString();
  }

  String _userName(Map<String, dynamic>? creator) {
    final nickname = _string(creator?['nickname']);
    return nickname.isNotEmpty ? nickname : _string(creator?['username']);
  }

  DateTime? _dateTime(Object? value) {
    final seconds = _integer(value);
    if (seconds <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
  }

  String _formatDateTime(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    final now = DateTime.now();
    if (value.year == now.year) {
      return '${two(value.month)}-${two(value.day)} ${two(value.hour)}:${two(value.minute)}';
    }
    return '${value.year}-${two(value.month)}-${two(value.day)}';
  }

  String _absolute(String? value) {
    if (value == null || value.trim().isEmpty) return '';
    final url = value.trim();
    if (url.startsWith('//')) return 'https:$url';
    return _baseUri.resolve(url).toString();
  }

  Map<String, dynamic>? _map(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : null;

  List<Object?> _list(Object? value) => value is List ? value : const [];

  int _integer(Object? value) =>
      value is num ? value.toInt() : int.tryParse(value?.toString() ?? '') ?? 0;

  double _double(Object? value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

  String _string(Object? value) => value?.toString().trim() ?? '';
}

class _TimelineContent {
  const _TimelineContent(
    this.description, {
    this.content = '',
    this.rawContent = '',
    this.images = const [],
    this.progress,
  });

  final String description;
  final String content;
  final String rawContent;
  final List<String> images;
  final CommunityTimelineProgress? progress;
}
