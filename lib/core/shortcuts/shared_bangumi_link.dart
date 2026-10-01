enum SharedBangumiKind {
  subject,
  person,
  character,
  groupTopic,
  subjectTopic,
  episodeTopic,
  timeline,
  directory,
}

class SharedBangumiLink {
  static const downloadUrl =
      'https://github.com/wweiyi2004/MuBangumi/releases/latest';
  const SharedBangumiLink(
    this.kind,
    this.id, {
    this.username,
    this.isStatus = true,
  });
  final SharedBangumiKind kind;
  final int id;
  final String? username;
  final bool isStatus;
  String get path => switch (kind) {
    SharedBangumiKind.subject => '/subject/$id',
    SharedBangumiKind.directory => '/index/$id',
    SharedBangumiKind.person => '/person/$id',
    SharedBangumiKind.character => '/character/$id',
    SharedBangumiKind.groupTopic => '/group/topic/$id',
    SharedBangumiKind.subjectTopic => '/subject/topic/$id',
    SharedBangumiKind.episodeTopic => '/ep/$id',
    SharedBangumiKind.timeline =>
      isStatus
          ? '/user/$username/timeline/status/$id'
          : '/user/$username/timeline',
  };
  String get url =>
      'https://bgm.tv$path${kind == SharedBangumiKind.timeline && !isStatus ? '?until=${id + 1}' : ''}';

  /// Our scanner decodes the fragment locally; other readers open the download
  /// page through the same public HTTPS URL.
  String get qrUrl => Uri.parse(downloadUrl)
      .replace(
        fragment:
            '${path.substring(1)}${kind == SharedBangumiKind.timeline && !isStatus ? '?until=${id + 1}' : ''}',
      )
      .toString();
  String get label =>
      '${switch (kind) {
        SharedBangumiKind.subject => '条目',
        SharedBangumiKind.directory => '目录',
        SharedBangumiKind.person => '人物',
        SharedBangumiKind.character => '角色',
        SharedBangumiKind.groupTopic => '小组话题',
        SharedBangumiKind.subjectTopic => '条目讨论',
        SharedBangumiKind.episodeTopic => '章节讨论',
        SharedBangumiKind.timeline => '动态',
      }} #$id';

  static SharedBangumiLink? parse(String raw) {
    if (raw.length > 4096) return null;
    final uri = Uri.tryParse(raw);
    if (uri != null &&
        uri.scheme == 'https' &&
        uri.host == 'github.com' &&
        uri.userInfo.isEmpty &&
        (!uri.hasPort || uri.port == 443) &&
        uri.path == '/wweiyi2004/MuBangumi/releases/latest' &&
        !uri.hasQuery &&
        uri.fragment.isNotEmpty) {
      return parse('https://bgm.tv/${uri.fragment}');
    }
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme.toLowerCase()) ||
        !{
          'bgm.tv',
          'bangumi.tv',
          'chii.in',
          'www.bgm.tv',
          'www.bangumi.tv',
          'www.chii.in',
        }.contains(uri.host.toLowerCase()) ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != (uri.scheme == 'https' ? 443 : 80))) {
      return null;
    }
    final timeline = RegExp(
      r'^/user/([a-zA-Z0-9_]+)/timeline(?:/status/(\d+))?/?$',
    ).firstMatch(uri.path);
    if (timeline != null) {
      final status = timeline[2] != null;
      final value = int.tryParse(
        timeline[2] ?? uri.queryParameters['until'] ?? '',
      );
      final id = value == null
          ? null
          : status
          ? value
          : value - 1;
      if (id == null || id <= 0 || id > 2147483647) return null;
      return SharedBangumiLink(
        SharedBangumiKind.timeline,
        id,
        username: timeline[1],
        isStatus: status,
      );
    }
    final match = RegExp(
      r'^/(subject|person|character|index|ep|group/topic|subject/topic|rakuen/topic/(?:grp|sbj|ep))/(\d+)/?$',
    ).firstMatch(uri.path);
    if (match == null) return null;
    final id = int.tryParse(match[2]!);
    if (id == null || id <= 0 || id > 2147483647) return null;
    final kind = switch (match[1]) {
      'subject' => SharedBangumiKind.subject,
      'index' => SharedBangumiKind.directory,
      'person' => SharedBangumiKind.person,
      'character' => SharedBangumiKind.character,
      'group/topic' || 'rakuen/topic/grp' => SharedBangumiKind.groupTopic,
      'subject/topic' || 'rakuen/topic/sbj' => SharedBangumiKind.subjectTopic,
      _ => SharedBangumiKind.episodeTopic,
    };
    return SharedBangumiLink(kind, id);
  }

  static List<SharedBangumiLink> fromText(String text) {
    if (text.length > 16384) return const [];
    final found = <String, SharedBangumiLink>{};
    for (final match in RegExp(
      r'''https?://[^\s<>"'，。！？、（）【】]+''',
      caseSensitive: false,
    ).allMatches(text)) {
      final candidate = match[0]!.replaceAll(RegExp(r'[)\]},.;!?]+$'), '');
      final link = parse(candidate);
      if (link != null) found[link.url] = link;
      if (found.length == 8) break;
    }
    return found.values.toList();
  }
}
