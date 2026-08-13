import '../../models/bangumi_models.dart';

/// Official Bangumi 公共标签 (wiki platform / source / region).
class BangumiMetaTagGroup {
  const BangumiMetaTagGroup({required this.label, required this.tags});

  final String label;
  final List<String> tags;
}

class BangumiMetaTags {
  BangumiMetaTags._();

  static List<BangumiMetaTagGroup> groupsFor(
    SubjectType type,
  ) => switch (type) {
    SubjectType.anime => const [
      BangumiMetaTagGroup(
        label: '分类',
        tags: ['TV', 'WEB', 'OVA', '剧场版', '动态漫画'],
      ),
      BangumiMetaTagGroup(label: '来源', tags: ['原创', '漫画改', '小说改', '游戏改']),
      BangumiMetaTagGroup(label: '地区', tags: ['日本', '欧美', '国产']),
    ],
    SubjectType.book => const [
      BangumiMetaTagGroup(
        label: '分类',
        tags: ['漫画', '小说', '画集', '绘本', '公式书', '写真', '杂志'],
      ),
    ],
    SubjectType.music => const [
      BangumiMetaTagGroup(label: '分类', tags: ['专辑', '单曲', 'EP', '广播剧', '有声书']),
    ],
    SubjectType.game => const [
      BangumiMetaTagGroup(
        label: '平台',
        tags: [
          'PC',
          'NS',
          'PS5',
          'PS4',
          'Xbox Series X/S',
          'Xbox One',
          'Android',
          'iOS',
          'Mac',
          '街机',
        ],
      ),
    ],
    SubjectType.real => const [
      BangumiMetaTagGroup(label: '分类', tags: ['日剧', '欧美剧', '华语剧', '纪录片', '综艺']),
    ],
  };

  static List<String> allFor(SubjectType type) => [
    for (final group in groupsFor(type)) ...group.tags,
  ];
}
