import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/shortcuts/shared_bangumi_link.dart';
import 'package:mubangumi/state/shared_link_controller.dart';

void main() {
  test(
    'discussion anchors survive aliases, QR round trips and share deduplication',
    () {
      for (final path in [
        'group/topic/9',
        'rakuen/topic/group/9',
        'rakuen/topic/grp/9',
        'subject/topic/9',
        'rakuen/topic/subject/9',
        'rakuen/topic/sbj/9',
        'ep/9',
        'person/9',
        'character/9',
        'rakuen/topic/prsn/9',
        'rakuen/topic/crt/9',
      ]) {
        final link = SharedBangumiLink.parse('https://bgm.tv/$path#post_80')!;
        expect(link.postId, 80);
        expect(link.url, endsWith('#post_80'));
        final decoded = SharedBangumiLink.parse(link.qrUrl)!;
        expect(decoded.url, link.url);
        expect(decoded.postId, 80);
      }
      expect(
        SharedBangumiLink.fromText(
          'https://bgm.tv/group/topic/9#post_80 https://bgm.tv/group/topic/9#post_81',
        ),
        hasLength(2),
      );
      expect(
        SharedBangumiLink.parse('https://bgm.tv/group/topic/9#post_0')!.postId,
        isNull,
      );
    },
  );
  test('accepts supported Bangumi aliases and canonicalizes shared text', () {
    final links = SharedBangumiLink.fromText(
      '推荐 https://bangumi.tv/subject/42?from=chat 。'
      'https://chii.in/subject/42#x https://bgm.tv/rakuen/topic/grp/9) '
      'https://bgm.tv/person/6 https://bgm.tv/character/8',
    );
    expect(links.map((link) => link.path), [
      '/subject/42',
      '/group/topic/9',
      '/person/6',
      '/character/8',
    ]);
  });
  for (final raw in [
    'https://bgm.tv.evil.test/subject/42',
    'https://evil.test/subject/42',
    'https://bgm.tv@evil.test/subject/42',
    'https://user@bgm.tv/subject/42',
    'file:///subject/42',
    'javascript:alert(1)',
    'https://bgm.tv:8000/subject/42',
    'https://bgm.tv/subject/0',
    'https://bgm.tv/subject/-1',
    'https://bgm.tv/subject/42/delete',
    'https://bgm.tv/subject/999999999999999999999',
    'https://bgm.tv/settings',
    'https://bgm.tv/user/alice/timeline/status/0',
    'https://bgm.tv/user/alice/timeline?until=1',
    'https://bgm.tv/user/alice/timeline?until=wat',
    'https://bgm.tv/user/a%2Fb/timeline/status/42',
    'https://bgm.tv/user/alice/timeline/status/42/delete',
  ]) {
    test('rejects unsupported or unsafe destination $raw', () {
      expect(SharedBangumiLink.parse(raw), isNull);
    });
  }
  test('unrecognized and oversized shares remain reviewable errors', () {
    expect(SharedBangumiLink.fromText('hello'), isEmpty);
    expect(
      SharedBangumiLink.fromText('${'x' * 16384} https://bgm.tv/subject/42'),
      isEmpty,
    );
  });
  test('shares wait in order for sign-in and are consumed only once', () {
    final pending = PendingSharedLinks();
    addTearDown(pending.dispose);
    pending.offer('https://bgm.tv/subject/42');
    pending.offer('not a link');
    expect(pending.state, hasLength(2));
    expect(pending.take()!.links.single.id, 42);
    expect(pending.take()!.links, isEmpty);
    expect(pending.take(), isNull);
  });
}
