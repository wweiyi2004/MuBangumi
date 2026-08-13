import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/network/bangumi_meta_tags.dart';
import 'package:mubangumi/core/network/bangumi_support.dart';
import 'package:mubangumi/models/bangumi_models.dart';

void main() {
  test('official anime meta tags cover type, source and region', () {
    expect(BangumiMetaTags.allFor(SubjectType.anime), [
      'TV',
      'WEB',
      'OVA',
      '剧场版',
      '动态漫画',
      '原创',
      '漫画改',
      '小说改',
      '游戏改',
      '日本',
      '欧美',
      '国产',
    ]);
  });

  test('every subject type has official meta-tag groups', () {
    for (final type in SubjectType.values) {
      expect(BangumiMetaTags.groupsFor(type), isNotEmpty, reason: type.label);
      expect(BangumiMetaTags.allFor(type), isNotEmpty, reason: type.label);
    }
    expect(BangumiMetaTags.allFor(SubjectType.book), containsAll(['漫画', '小说']));
    expect(
      BangumiMetaTags.allFor(SubjectType.music),
      containsAll(['专辑', '单曲']),
    );
    expect(BangumiMetaTags.allFor(SubjectType.game), containsAll(['PC', 'NS']));
    expect(
      BangumiMetaTags.allFor(SubjectType.real),
      containsAll(['日剧', '欧美剧', '综艺']),
    );
  });

  test('subject search filter sends official tags as meta_tags', () {
    final filter = BangumiSupport.subjectSearchFilter(
      subjectType: SubjectType.anime,
      metaTags: const ['TV', '日本'],
      tags: const ['科幻'],
    );
    expect(filter['meta_tags'], ['TV', '日本']);
    expect(filter['tag'], ['科幻']);
    expect(filter['type'], [SubjectType.anime.value]);
  });
}
