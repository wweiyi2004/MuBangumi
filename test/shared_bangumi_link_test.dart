import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/shortcuts/shared_bangumi_link.dart';
import 'package:mubangumi/state/shared_link_controller.dart';

void main() {
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
