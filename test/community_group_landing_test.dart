import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/network/community_html_parser.dart';

/// Regression guard: the sibling call sites in this parser guard
/// `pathSegments.last`, but the group-topic rakuen URL did not, so a topic
/// row whose href carried no path segments threw a StateError out of
/// parseGroupLanding and failed the whole group landing page.
void main() {
  String landingWith(String href) => '''
    <table class="topic_list"><tr>
      <td><a class="l" href="$href">某个话题标题</a></td>
      <td><a href="/group/1">某小组</a></td>
      <td><a href="/user/someone">某人</a></td>
      <td>3</td>
    </tr></table>''';

  final parser = CommunityHtmlParser();

  test('parses a normal group topic row', () {
    final landing = parser.parseGroupLanding(landingWith('/group/topic/123'));
    expect(landing.topics, hasLength(1));
    expect(landing.topics.single.url, 'https://bgm.tv/rakuen/topic/group/123');
  });

  for (final href in ['#', '?page=2', '']) {
    test('does not throw when the topic href has no path ($href)', () {
      final landing = parser.parseGroupLanding(landingWith(href));
      expect(landing.topics, hasLength(1));
    });
  }
}
