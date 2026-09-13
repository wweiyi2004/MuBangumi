enum SharedBangumiKind {
  subject,
  person,
  character,
  groupTopic,
  subjectTopic,
  episodeTopic,
}

class SharedBangumiLink {
  const SharedBangumiLink(this.kind, this.id);
  final SharedBangumiKind kind;
  final int id;
  String get path => switch (kind) {
    SharedBangumiKind.subject => '/subject/$id',
    SharedBangumiKind.person => '/person/$id',
    SharedBangumiKind.character => '/character/$id',
    SharedBangumiKind.groupTopic => '/group/topic/$id',
    SharedBangumiKind.subjectTopic => '/subject/topic/$id',
    SharedBangumiKind.episodeTopic => '/ep/$id',
  };
  String get url => 'https://bgm.tv$path';
  String get label =>
      '${switch (kind) {
        SharedBangumiKind.subject => '条目',
        SharedBangumiKind.person => '人物',
        SharedBangumiKind.character => '角色',
        SharedBangumiKind.groupTopic => '小组话题',
        SharedBangumiKind.subjectTopic => '条目讨论',
        SharedBangumiKind.episodeTopic => '章节讨论',
      }} #$id';

  static SharedBangumiLink? parse(String raw) {
    final uri = Uri.tryParse(raw);
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
    final match = RegExp(
      r'^/(subject|person|character|ep|group/topic|subject/topic|rakuen/topic/(?:grp|sbj|ep))/(\d+)/?$',
    ).firstMatch(uri.path);
    if (match == null) return null;
    final id = int.tryParse(match[2]!);
    if (id == null || id <= 0 || id > 2147483647) return null;
    final kind = switch (match[1]) {
      'subject' => SharedBangumiKind.subject,
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
      if (link != null) found[link.path] = link;
      if (found.length == 8) break;
    }
    return found.values.toList();
  }
}
