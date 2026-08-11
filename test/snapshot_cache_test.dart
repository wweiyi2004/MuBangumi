import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/storage/snapshot_cache.dart';
import 'package:mubangumi/models/bangumi_models.dart';

void main() {
  test('Subject/UserCollection snapshot round-trips through JSON', () {
    const subject = Subject(
      id: 12,
      name: 'Test',
      nameCn: '测试',
      imageUrl: 'https://example.com/a.jpg',
      summary: '简介',
      episodeCount: 12,
      score: 8.5,
      rank: 10,
      date: '2024-01-01',
      type: SubjectType.anime,
      tags: ['科幻'],
    );
    final collection = UserCollection(
      subjectId: 12,
      type: CollectionType.doing,
      rate: 8,
      episodeStatus: 3,
      updatedAt: DateTime.parse('2024-06-01T12:00:00Z'),
      subject: subject,
      comment: '好看',
      tags: ['追番'],
    );

    final restoredSubject = Subject.fromJson(subject.toJson());
    expect(restoredSubject.id, 12);
    expect(restoredSubject.displayName, '测试');
    expect(restoredSubject.episodeCount, 12);
    expect(restoredSubject.score, 8.5);
    expect(restoredSubject.tags, contains('科幻'));

    final restored = UserCollection.fromJson(collection.toJson());
    expect(restored.subjectId, 12);
    expect(restored.type, CollectionType.doing);
    expect(restored.rate, 8);
    expect(restored.episodeStatus, 3);
    expect(restored.comment, '好看');
    expect(restored.subject.displayName, '测试');
  });

  test('discover browse cache keys are stable per filter', () {
    final a = SnapshotCache.discoverBrowseKey(
      type: SubjectType.anime,
      year: 2026,
      quarter: 2,
      sort: 'rank',
      supportsSeason: true,
    );
    final b = SnapshotCache.discoverBrowseKey(
      type: SubjectType.anime,
      year: 2026,
      quarter: 2,
      sort: 'rank',
      supportsSeason: true,
    );
    final c = SnapshotCache.discoverBrowseKey(
      type: SubjectType.anime,
      year: 2026,
      quarter: 1,
      sort: 'rank',
      supportsSeason: true,
    );
    expect(a, b);
    expect(a, isNot(c));
    expect(a, contains('discover_browse:'));
  });
}
