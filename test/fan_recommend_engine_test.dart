import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/recommend/fan_recommend_engine.dart';
import 'package:mubangumi/models/bangumi_models.dart';

Subject _subject({
  required int id,
  required String name,
  double score = 7.5,
  int rank = 100,
  List<String> tags = const [],
  String date = '2024-01-01',
}) => Subject(
  id: id,
  name: name,
  nameCn: name,
  imageUrl: '',
  summary: '',
  episodeCount: 12,
  score: score,
  rank: rank,
  date: date,
  tags: tags,
);

UserCollection _collection({
  required Subject subject,
  int rate = 8,
  CollectionType type = CollectionType.done,
  List<String> tags = const [],
}) => UserCollection(
  subjectId: subject.id,
  type: type,
  rate: rate,
  episodeStatus: 12,
  updatedAt: DateTime(2024),
  subject: subject,
  tags: tags,
);

void main() {
  test('builds taste tags from high-rated collections', () {
    final collections = [
      _collection(
        subject: _subject(id: 1, name: 'A', tags: ['治愈', '日常', 'TV']),
        rate: 9,
      ),
      _collection(
        subject: _subject(id: 2, name: 'B', tags: ['治愈', '校园']),
        rate: 8,
      ),
      _collection(
        subject: _subject(id: 3, name: 'C', tags: ['战斗']),
        rate: 5,
      ),
    ];
    final taste = FanRecommendEngine.buildTaste(collections);
    expect(taste.ownedIds, containsAll([1, 2, 3]));
    expect(taste.topTags.first, '治愈');
    expect(taste.topTags, isNot(contains('TV')));
    expect(taste.hasTaste, isTrue);
  });

  test('ranks candidates and excludes owned subjects', () {
    final taste = FanTasteProfile(
      topTags: const ['治愈', '日常'],
      ownedIds: {1},
      likedCount: 2,
      avgLikedScore: 8.5,
    );
    final request = const FanRecommendRequest(
      selectedTags: ['治愈'],
      minimumRating: 7,
      useTaste: true,
    );
    final ranked = FanRecommendEngine.rank(
      candidates: [
        _subject(id: 1, name: '已收藏', score: 9, tags: ['治愈']),
        _subject(id: 2, name: '匹配', score: 8.2, rank: 50, tags: ['治愈', '日常']),
        _subject(id: 3, name: '一般', score: 7.1, rank: 800, tags: ['战斗']),
      ],
      taste: taste,
      request: request,
    );
    expect(ranked.map((e) => e.subject.id), isNot(contains(1)));
    expect(ranked.first.subject.id, 2);
    expect(ranked.first.matchedTags, contains('治愈'));
    expect(ranked.first.reasons, isNotEmpty);
  });

  test('parses wish text into tags and keyword', () {
    const request = FanRecommendRequest(
      wishText: '想看治愈 日常，画风干净',
      selectedTags: ['恋爱'],
    );
    expect(request.effectiveTags, containsAll(['恋爱', '治愈', '日常']));
    expect(request.keyword.contains('画风'), isTrue);
  });
}
