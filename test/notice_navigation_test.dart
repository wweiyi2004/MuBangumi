import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/models/community_models.dart';

void main() {
  test('topic notices map to native topic kinds and canonical URLs', () {
    final cases = <int, (CommunityTopicKind, String, String)>{
      1: (
        CommunityTopicKind.group,
        'https://bgm.tv/rakuen/topic/group/123',
        'https://bgm.tv/group/topic/123',
      ),
      4: (
        CommunityTopicKind.subject,
        'https://bgm.tv/rakuen/topic/subject/123',
        'https://bgm.tv/subject/topic/123',
      ),
      5: (
        CommunityTopicKind.character,
        'https://bgm.tv/rakuen/topic/crt/123',
        'https://bgm.tv/character/123',
      ),
      9: (
        CommunityTopicKind.episode,
        'https://bgm.tv/rakuen/topic/ep/123',
        'https://bgm.tv/ep/123',
      ),
      13: (
        CommunityTopicKind.person,
        'https://bgm.tv/rakuen/topic/prsn/123',
        'https://bgm.tv/person/123',
      ),
      29: (
        CommunityTopicKind.blog,
        'https://bgm.tv/rakuen/topic/blog/123',
        'https://bgm.tv/blog/123',
      ),
    };

    for (final MapEntry(key: type, value: expected) in cases.entries) {
      final notice = _notice(type: type);
      expect(notice.nativeTopic?.kind, expected.$1);
      expect(notice.nativeTopic?.url, expected.$2);
      expect(notice.nativeTopic?.webUrl, expected.$3);
    }
  });

  test('timeline and friend notices stay inside native app surfaces', () {
    final timelineReply = _notice(type: 22);
    final timelineMention = _notice(
      type: 28,
      sender: const CommunityUser(id: 7, username: 'alice', nickname: '爱丽丝'),
    );
    final mentionWithoutSender = _notice(type: 28);
    final friendRequest = _notice(
      type: 14,
      sender: const CommunityUser(id: 7, username: 'alice', nickname: '爱丽丝'),
    );

    expect(timelineReply.opensNativeTimeline, isTrue);
    expect(timelineMention.opensNativeTimeline, isTrue);
    expect(timelineReply.nativeTopic, isNull);
    expect(
      timelineReply.nativeTimelineDestination?.mode,
      CommunityTimelineMode.me,
    );
    expect(timelineReply.nativeTimelineDestination?.username, isNull);
    expect(timelineReply.nativeTimelineDestination?.fetchUntil, 124);
    expect(timelineMention.nativeTimelineDestination?.username, 'alice');
    expect(
      timelineMention.nativeTimelineDestination?.mode,
      isNot(CommunityTimelineMode.me),
    );
    expect(
      mentionWithoutSender.nativeTimelineDestination?.mode,
      CommunityTimelineMode.all,
    );
    expect(mentionWithoutSender.nativeTimelineDestination?.username, isNull);
    expect(friendRequest.opensNativeTimeline, isFalse);
    expect(friendRequest.nativeTopic, isNull);
    expect(friendRequest.webUrl, 'https://bgm.tv/user/alice');
  });

  test('invalid topic ids do not produce a native topic destination', () {
    expect(_notice(type: 1, mainId: 0).nativeTopic, isNull);
  });
}

BangumiNotice _notice({
  required int type,
  int mainId = 123,
  CommunityUser? sender,
}) => BangumiNotice(
  id: 1,
  title: '测试提醒',
  type: type,
  mainId: mainId,
  relatedId: 456,
  unread: true,
  createdAt: DateTime(2026),
  sender: sender,
);
